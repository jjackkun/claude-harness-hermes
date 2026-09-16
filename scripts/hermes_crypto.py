#!/usr/bin/env python3
"""`age` CLI 를 감싸 암호화·복호화만 제공한다. 열쇠 정책은 여기 없다(hermes_keys.py).

pip 의존을 두지 않는다는 기존 규칙에 따라 라이브러리가 아니라 단일 바이너리 `age` 를
subprocess 로 부른다(계획 §6, V-6 결정).
근거: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 3

비밀열쇠는 **파일 경로로만** 넘긴다 — 명령줄 인자로 주면 같은 기계의 다른 프로세스가
`ps` 로 볼 수 있다.

공개 함수 6개: age_available · generate_identity · public_key ·
encrypt_to · decrypt_with · CryptoError
"""

import os
import shutil
import subprocess
import tempfile

_TIMEOUT = 60


class CryptoError(RuntimeError):
    """age 실행 실패 — 미설치·열쇠 불일치·손상된 입력."""


def age_available() -> bool:
    """`age` 와 `age-keygen` 이 PATH 에 있는가."""
    return bool(shutil.which("age")) and bool(shutil.which("age-keygen"))


def _run(args: list, stdin: bytes = None) -> bytes:
    try:
        done = subprocess.run(args, input=stdin, capture_output=True, timeout=_TIMEOUT)
    except FileNotFoundError as exc:
        raise CryptoError("age 가 설치돼 있지 않다") from exc
    except subprocess.TimeoutExpired as exc:
        raise CryptoError(f"age 가 {_TIMEOUT}초 안에 끝나지 않았다") from exc
    if done.returncode != 0:
        raise CryptoError(done.stderr.decode("utf-8", "replace").strip() or "age 실행 실패")
    return done.stdout


def generate_identity(path: str) -> str:
    """새 age 열쇠 한 쌍을 만들어 <path>(0600)에 쓰고 공개 자물쇠를 돌려준다."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(_run(["age-keygen"]))
    except Exception:
        if os.path.exists(path):
            os.unlink(path)
        raise
    return public_key(path)


def public_key(identity_path: str) -> str:
    """비밀열쇠 파일에서 공개 자물쇠(age1…)를 얻는다."""
    out = _run(["age-keygen", "-y", identity_path]).decode().strip()
    if not out.startswith("age1"):
        raise CryptoError(f"공개 자물쇠를 읽지 못했다: {out[:40]}")
    return out


def encrypt_to(recipients, data: bytes, armor: bool = False) -> bytes:
    """수신자(자물쇠) 목록으로 암호화한다. 수신자가 없으면 거부한다.

    armor=True 면 PEM 형식 텍스트로 낸다 — JSON 칸 안에 넣을 때(작업 이력 자유 글 3칸).
    """
    locks = [r for r in (recipients or []) if r]
    if not locks:
        raise CryptoError("수신자가 없다 — 아무도 열 수 없는 파일을 만들지 않는다")
    args = ["age", "--encrypt"] + (["--armor"] if armor else [])
    for lock in locks:
        args += ["-r", lock]
    return _run(args, stdin=data)


def decrypt_with(identity_path: str, data: bytes) -> bytes:
    """비밀열쇠 파일로 복호화한다."""
    if not os.path.isfile(identity_path):
        raise CryptoError(f"열쇠 파일이 없다: {identity_path}")
    return _run(["age", "--decrypt", "-i", identity_path], stdin=data)


def decrypt_with_secret(secret_key: str, data: bytes) -> bytes:
    """문자열로 받은 비밀열쇠(니모닉 복원본)로 복호화한다 — 임시 파일 경유(0600)."""
    fd, tmp = tempfile.mkstemp(prefix=".hermes-key-", suffix=".txt")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(secret_key.strip() + "\n")
        return decrypt_with(tmp, data)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

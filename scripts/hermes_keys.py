#!/usr/bin/env python3
"""열쇠 **정책** — 어디에 두고, 어떻게 감싸고, 무엇을 원격에 올리는가.

암호 연산 자체는 `hermes_crypto.py` 가 한다. 여기서 정하는 것은 배치와 규칙이다.

  로컬(절대 원격에 나가지 않음)   ~/.hermes/keys/<universe_id>/
      master.key      조각을 여는 열쇠. 이 파일만 있으면 과거 전부를 읽는다(0600).
      computer.key    이 컴퓨터의 자물쇠 짝(0600).
  원격(refs/hermes/sync 안)
      keys/<사람>/<지문>.pub                자물쇠(공개)
      keys/<사람>/master.<지문>.age         마스터 열쇠를 그 자물쇠로 감싼 것

마스터 하나를 여러 자물쇠로 감싸는 이유(RV-03): 컴퓨터가 늘어도 조각을 다시 암호화하지
않는다. 조각 수신자는 언제나 마스터 자물쇠 하나다.
근거: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md 목표 3·4

공개 함수 6개: key_path · fingerprint · wrap_master · unwrap_master ·
registered_locks · master_recipient
"""

import hashlib
import os

import hermes_crypto as crypto

_HOME_DIR = "~/.hermes/keys"
_NAMES = {"root": "", "master": "master.key", "computer": "computer.key"}


def key_path(universe_id: str, kind: str = "root") -> str:
    """로컬 열쇠 경로. kind: root(폴더) · master · computer.

    소우주마다 폴더를 따로 둔다 — 한 열쇠가 여러 우주를 열지 않는다(D-05 격리).
    """
    if kind not in _NAMES:
        raise ValueError(f"모르는 열쇠 종류: {kind}")
    root = os.path.join(os.path.expanduser(_HOME_DIR), universe_id)
    return os.path.join(root, _NAMES[kind]) if _NAMES[kind] else root


def fingerprint(lock: str) -> str:
    """자물쇠의 짧은 지문 — 파일 이름에 쓴다(사람이 눈으로 대조할 수 있게)."""
    return hashlib.sha256(lock.encode()).hexdigest()[:12]


def wrap_master(universe_id: str, lock: str) -> bytes:
    """마스터 열쇠를 그 자물쇠로 감싼다. 감싼 것만 원격에 올라간다."""
    path = key_path(universe_id, "master")
    if not os.path.isfile(path):
        raise crypto.CryptoError(f"마스터 열쇠가 없다: {path} (hermes-keys.sh init)")
    with open(path, "rb") as fh:
        return crypto.encrypt_to([lock], fh.read())


def unwrap_master(identity_path: str, wrapped: bytes, dest: str) -> str:
    """감싼 마스터를 풀어 <dest>(0600)에 놓는다. 다른 컴퓨터가 합류하는 경로다."""
    plain = crypto.decrypt_with(identity_path, wrapped)
    os.makedirs(os.path.dirname(os.path.abspath(dest)), exist_ok=True)
    fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as fh:
        fh.write(plain)
    return dest


def registered_locks(sync_dir: str) -> dict:
    """원격 사본(`keys/`)에 등록된 자물쇠 {지문: 경로}. 사람 단위 폴더를 훑는다."""
    out = {}
    root = os.path.join(sync_dir, "keys")
    if not os.path.isdir(root):
        return out
    for person in sorted(os.listdir(root)):
        person_dir = os.path.join(root, person)
        if not os.path.isdir(person_dir):
            continue
        for name in sorted(os.listdir(person_dir)):
            if name.endswith(".pub"):
                out[name[:-4]] = os.path.join(person_dir, name)
    return out


def master_recipient(universe_id: str) -> str:
    """조각을 잠글 수신자 — 언제나 마스터 자물쇠 하나다."""
    return crypto.public_key(key_path(universe_id, "master"))

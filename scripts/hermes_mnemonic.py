#!/usr/bin/env python3
"""age 비밀열쇠 ↔ 24단어 니모닉 변환만 담당한다.

비상 열쇠는 사람이 손으로 옮겨 적는다. 74자 `AGE-SECRET-KEY-1…` 문자열은 오타가 나기 쉽고
났는지도 알 수 없다. 24단어(BIP-39 영어 사전)는 옮겨 적기 쉽고 **체크섬이 오타를 잡는다**.
age 비밀열쇠의 알맹이는 32바이트라 256비트 = 24단어에 파생 없이 그대로 담긴다.
근거: docs/exec-plans/active/2026-09-15-sync-transport-encryption.md §6(2026-09-16 결정)

변환 경로: AGE-SECRET-KEY-1… ─Bech32 해독→ 32바이트 ─BIP-39→ 24단어 (그리고 그 역)

공개 함수 4개: key_to_mnemonic · mnemonic_to_key · load_wordlist · MnemonicError
"""

import os
import hashlib

_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
_HRP = "AGE-SECRET-KEY-"
_WORDS = 24
_ENTROPY_BITS = 256
_WORDLIST_NAME = "bip39-english.txt"


class MnemonicError(ValueError):
    """옮겨 적은 단어가 사전에 없거나 체크섬이 맞지 않는다."""


def load_wordlist(path: str = None) -> list:
    """BIP-39 영어 사전 2048단어. 기본 위치는 설치된 `assets/data/`(또는 저장소 사본)."""
    candidates = [path] if path else [
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", _WORDLIST_NAME),
        os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                     "assets", "data", _WORDLIST_NAME),
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            with open(candidate, encoding="utf-8") as fh:
                words = [w.strip() for w in fh if w.strip()]
            if len(words) != 2048:
                raise MnemonicError(f"사전 단어 수가 2048이 아니다: {len(words)} ({candidate})")
            return words
    raise MnemonicError(f"BIP-39 사전을 찾지 못했다: {candidates}")


# ── Bech32 (BIP-173) — age 열쇠 표기 ─────────────────────────────────────────

def _polymod(values) -> int:
    generator = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
    chk = 1
    for value in values:
        top = chk >> 25
        chk = ((chk & 0x1FFFFFF) << 5) ^ value
        for i in range(5):
            chk ^= generator[i] if ((top >> i) & 1) else 0
    return chk


def _hrp_expand(hrp: str) -> list:
    return [ord(c) >> 5 for c in hrp] + [0] + [ord(c) & 31 for c in hrp]


def _convert_bits(data, frm: int, to: int, pad: bool):
    acc = bits = 0
    out = []
    maxv = (1 << to) - 1
    for value in data:
        acc = (acc << frm) | value
        bits += frm
        while bits >= to:
            bits -= to
            out.append((acc >> bits) & maxv)
    if pad and bits:
        out.append((acc << (to - bits)) & maxv)
    elif not pad and (bits >= frm or ((acc << (to - bits)) & maxv)):
        raise MnemonicError("Bech32 패딩이 맞지 않는다")
    return out


def _bech32_decode(text: str) -> bytes:
    lower = text.lower()
    pos = lower.rfind("1")
    if pos < 1:
        raise MnemonicError("age 열쇠 형식이 아니다")
    hrp, data_part = lower[:pos], lower[pos + 1:]
    if hrp != _HRP.lower():
        raise MnemonicError(f"age 비밀열쇠가 아니다(hrp={hrp})")
    try:
        data = [_CHARSET.index(c) for c in data_part]
    except ValueError as exc:
        raise MnemonicError("Bech32 문자표에 없는 글자가 있다") from exc
    if _polymod(_hrp_expand(hrp) + data) != 1:
        raise MnemonicError("Bech32 체크섬이 맞지 않는다")
    return bytes(_convert_bits(data[:-6], 5, 8, False))


def _bech32_encode(payload: bytes) -> str:
    hrp = _HRP.lower()
    data = _convert_bits(payload, 8, 5, True)
    chk = _polymod(_hrp_expand(hrp) + data + [0] * 6) ^ 1
    checksum = [(chk >> 5 * (5 - i)) & 31 for i in range(6)]
    return (hrp + "1" + "".join(_CHARSET[d] for d in data + checksum)).upper()


# ── BIP-39 — 32바이트 ↔ 24단어 ───────────────────────────────────────────────

def key_to_mnemonic(secret_key: str, wordlist: list = None) -> list:
    """`AGE-SECRET-KEY-1…` → 24단어."""
    words = wordlist or load_wordlist()
    payload = _bech32_decode(secret_key.strip())
    if len(payload) * 8 != _ENTROPY_BITS:
        raise MnemonicError(f"32바이트 열쇠가 아니다({len(payload)}바이트)")
    checksum = hashlib.sha256(payload).digest()[0]          # 256비트 → 체크섬 8비트
    bits = int.from_bytes(payload, "big") << 8 | checksum
    return [words[(bits >> (11 * (_WORDS - 1 - i))) & 0x7FF] for i in range(_WORDS)]


def mnemonic_to_key(mnemonic, wordlist: list = None) -> str:
    """24단어 → `AGE-SECRET-KEY-1…`. 오타는 체크섬이 잡는다."""
    words = wordlist or load_wordlist()
    given = mnemonic.split() if isinstance(mnemonic, str) else list(mnemonic)
    if len(given) != _WORDS:
        raise MnemonicError(f"24단어여야 한다(받은 단어 {len(given)}개)")
    index = {w: i for i, w in enumerate(words)}
    bits = 0
    for word in given:
        low = word.strip().lower()
        if low not in index:
            raise MnemonicError(f"사전에 없는 단어: {word}")
        bits = (bits << 11) | index[low]
    checksum = bits & 0xFF
    payload = (bits >> 8).to_bytes(_ENTROPY_BITS // 8, "big")
    if hashlib.sha256(payload).digest()[0] != checksum:
        raise MnemonicError("체크섬이 맞지 않는다 — 옮겨 적은 단어를 다시 확인하십시오")
    return _bech32_encode(payload)

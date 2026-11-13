"""Pick a block of unused TCP ports for one project (frontend dev/prod, API dev/prod, DB).

Ports are taken as base+1 .. base+5 for the first base (step 10) whose whole block is free,
so one project's ports read as a group, e.g. 8821-8825.
"""

import socket

PORT_NAMES = ("FRONT_DEV", "FRONT_PROD", "API_DEV", "API_PROD", "DB")
RANGE_START = 8810
RANGE_END = 9900
STEP = 10


def is_free(port: int) -> bool:
    for host in ("127.0.0.1", "0.0.0.0"):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind((host, port))
            except OSError:
                return False
    return True


def pick_ports(taken: frozenset[int] = frozenset()) -> dict[str, int]:
    """Return {name: port}. `taken` lets callers exclude ports reserved by other projects' .env files."""
    for base in range(RANGE_START, RANGE_END, STEP):
        block = [base + i for i in range(1, len(PORT_NAMES) + 1)]
        if all(p not in taken and is_free(p) for p in block):
            return dict(zip(PORT_NAMES, block, strict=True))
    raise RuntimeError(f"no free block of {len(PORT_NAMES)} ports in {RANGE_START}-{RANGE_END}")


if __name__ == "__main__":
    print(pick_ports())

"""DB 를 지우기 전에 복사해 두는 공용 함수 — 정리 명령들이 함께 쓴다.

파일 복사는 WAL 에만 있는 최근 기록을 놓칠 수 있어 sqlite 백업 API 를 쓴다.
같은 이름이 있으면 덮지 않도록 초 단위 시각을 붙인다.

공개: backup_db
"""

import sqlite3
from datetime import datetime


def backup_db(con: sqlite3.Connection, db_path: str) -> str:
    dest = f"{db_path}.bak-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    out = sqlite3.connect(dest)
    try:
        con.backup(out)
    finally:
        out.close()
    return dest

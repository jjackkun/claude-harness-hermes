#!/usr/bin/env python3
"""시안 폴더 → 단일 HTML (+ 아티팩트용 파일).

상대 경로 <link rel="stylesheet">·<script src> 를 파일 내용으로 바꾼다 (../ 공유 파일 포함).
외부 참조는 허용 목록(Google Fonts)만 남기고 그 밖이면 실패, 참조 파일이 없어도 실패 — 조용히 빠진
시안은 열어 봐야 깨진 걸 안다. 태그 위치는 HTML 파서로 잡는다 (주석 안 태그·스크립트 안 문자열은 건드리지 않음).

사용: python3 build_single.py <시안 폴더> [--out <단일 HTML>] [--artifact <아티팩트용 파일>]
      --out 기본값은 시안 폴더 옆 <이름>.html (예: docs/prototypes/core-loop.html)
"""
import argparse
import os
import sys
from html.parser import HTMLParser
from urllib.parse import urlparse

from artifact_strip import to_artifact

ALLOWED_HOSTS = ("fonts.googleapis.com", "fonts.gstatic.com")
RESOURCE_TAGS = {"link": "href", "script": "src", "img": "src", "source": "src", "iframe": "src"}


class BuildError(Exception):
    """단일 HTML 을 만들 수 없음."""


class _Locator(HTMLParser):
    """바꿀 태그의 원문 구간 [시작, 끝) 과 참조 경로를 모은다."""

    def __init__(self, text):
        super().__init__(convert_charrefs=False)
        self._starts = [0]
        for line in text.splitlines(keepends=True):
            self._starts.append(self._starts[-1] + len(line))
        self._text = text
        self._open_script = None
        self.spans = []  # (시작, 끝, 종류 css|js, 경로)
        self.external = []

    def _offset(self):
        line, col = self.getpos()
        return self._starts[line - 1] + col

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        url = a.get(RESOURCE_TAGS.get(tag, ""), None)
        if url and (urlparse(url).scheme in ("http", "https") or url.startswith("//")):
            self.external.append(url)
            return
        start = self._offset()
        end = start + len(self.get_starttag_text())
        if tag == "link" and "stylesheet" in (a.get("rel") or "") and url:
            self.spans.append((start, end, "css", url))
        elif tag == "script" and url:
            self._open_script = (start, url)

    def handle_endtag(self, tag):
        if tag == "script" and self._open_script:
            start, url = self._open_script
            close = self._text.index(">", self._offset()) + 1
            self.spans.append((start, close, "js", url))
            self._open_script = None


def _inline(kind, rel, body):
    if kind == "css":
        return f"<style>/* {rel} */\n{body}\n</style>"
    # 스크립트 안의 </script 는 HTML 파서가 끝 태그로 읽는다 — 문자열·주석 안에서도
    escaped = body.replace("</script", "<\\/script")
    return f"<script>/* {rel} */\n{escaped}\n</script>"


def build(folder):
    with open(os.path.join(folder, "index.html"), encoding="utf-8") as f:
        text = f.read()
    loc = _Locator(text)
    loc.feed(text)
    banned = [u for u in loc.external if urlparse(u if "//" in u else "//" + u).hostname not in ALLOWED_HOSTS]
    if banned:
        raise BuildError(f"허용 목록({', '.join(ALLOWED_HOSTS)}) 밖 외부 참조: {', '.join(banned)}")
    out, cursor = [], 0
    for start, end, kind, rel in sorted(loc.spans):
        path = os.path.normpath(os.path.join(folder, rel))
        if not os.path.isfile(path):
            raise BuildError(f"참조 파일이 없음: {rel} ({path})")
        with open(path, encoding="utf-8") as f:
            out += [text[cursor:start], _inline(kind, rel, f.read())]
        cursor = end
    return "".join(out + [text[cursor:]])


def main():
    ap = argparse.ArgumentParser(description="시안 폴더를 단일 HTML 로 묶는다")
    ap.add_argument("folder")
    ap.add_argument("--out", help="단일 HTML 경로 (기본: 시안 폴더 옆 <이름>.html)")
    ap.add_argument("--artifact", help="아티팩트용 파일 경로 (문서 뼈대 없이, <title> 이 맨 앞)")
    args = ap.parse_args()
    folder = os.path.abspath(args.folder)
    out = args.out or folder.rstrip(os.sep) + ".html"
    try:
        single = build(folder)
    except (BuildError, OSError) as err:
        print(f"[build 실패] {err}", file=sys.stderr)
        return 1
    with open(out, "w", encoding="utf-8") as f:
        f.write(single)
    print(f"단일 HTML: {out} ({len(single.encode('utf-8')):,} 바이트)")
    if args.artifact:
        with open(args.artifact, "w", encoding="utf-8") as f:
            f.write(to_artifact(single))
        print(f"아티팩트용: {args.artifact}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

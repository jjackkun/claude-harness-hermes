"""단일 HTML → 아티팩트 게시용 본문.

게시할 때 문서 뼈대(doctype·html·head·body·charset·viewport)가 자동으로 씌워지므로 지우고,
<title> 을 맨 앞으로 옮긴다. <meta name="claude:viewport-fit-sides">·폰트 링크·<style>·본문은 남긴다.
<script>·<style>·주석 안은 건드리지 않는다 — 화면 문자열 속 "<header" 같은 글자를 지우면 안 된다.
"""
import re

_PROTECTED = re.compile(r"(<script\b[^>]*>.*?</script>|<style\b[^>]*>.*?</style>|<!--.*?-->)", re.S | re.I)
_SKELETON = re.compile(
    r"<!doctype[^>]*>|</?html\b[^>]*>|</?head\b[^>]*>|</?body\b[^>]*>"
    r"|<meta\s+charset[^>]*>|<meta\s+name=[\"']viewport[\"'][^>]*>",
    re.I,
)
_TITLE = re.compile(r"<title\b[^>]*>.*?</title>", re.S | re.I)


def to_artifact(single_html):
    """단일 HTML 문자열 → <title> 로 시작하고 문서 뼈대가 없는 문자열."""
    parts = _PROTECTED.split(single_html)
    title = ""
    kept = []
    for i, part in enumerate(parts):
        if i % 2:  # split 의 홀수 칸이 보호 구간
            kept.append(part)
            continue
        found = _TITLE.search(part)
        if found and not title:
            title = found.group(0)
            part = part[:found.start()] + part[found.end():]
        kept.append(_SKELETON.sub("", part))
    body = re.sub(r"\n{3,}", "\n\n", "".join(kept)).strip()
    return f"{title}\n{body}\n"

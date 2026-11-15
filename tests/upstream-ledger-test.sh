#!/usr/bin/env bash
# 밖에서 가져온 에셋 장부 — 계획 docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G1·G2
#
#   G1 assets/upstream.json 의 항목마다 경로가 있고 필수 칸이 채워져 있다
#   G1 LICENSE·NOTICE·origin 주석 같은 원본 흔적이 있는 에셋이 장부에서 빠지지 않았다
#   G2 전수 조사 표의 이름 집합 = assets/ 의 스킬·규칙·에이전트·훅 이름 집합, 행마다 분류 하나
#
# 실행: bash tests/upstream-ledger-test.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import json, os, re, sys

root = sys.argv[1]
fails = []
def check(ok, msg):
    print(('  ✓ ' if ok else '  ✗ ') + msg)
    if not ok:
        fails.append(msg)

ledger = json.load(open(os.path.join(root, 'assets/upstream.json')))
items = ledger['items']
check(ledger.get('version') == 1 and len(items) > 0, f'장부 version 1, 항목 {len(items)}개')

REQUIRED = ('name', 'kind', 'path', 'mode', 'sources', 'tests')
bad = []
for it in items:
    missing = [k for k in REQUIRED if not it.get(k)]
    if missing:
        bad.append(f"{it.get('name')}: 빈 칸 {missing}")
        continue
    if it['mode'] not in ('vendored', 'adapted'):
        bad.append(f"{it['name']}: mode={it['mode']}")
    if not os.path.exists(os.path.join(root, it['path'])):
        bad.append(f"{it['name']}: 경로 없음 {it['path']}")
    for s in it['sources']:
        if not (s.get('repo') and s.get('path') and re.fullmatch(r'[0-9a-f]{40}', s.get('sha', ''))):
            bad.append(f"{it['name']}: 출처 칸이 비었거나 sha 형식이 아님")
    for t in it['tests']:
        if not os.path.exists(os.path.join(root, t)):
            bad.append(f"{it['name']}: 시험 없음 {t}")
    vf = it.get('version_from')
    if vf and not os.path.exists(os.path.join(root, it['path'], vf['file'])):
        bad.append(f"{it['name']}: version_from 파일 없음")
check(not bad, '항목마다 필수 칸·경로·출처 sha·시험 파일' + ('' if not bad else ' — ' + '; '.join(bad[:5])))

names = {(it['kind'], it['path'].rstrip('/').split('/')[-1]) for it in items}
untracked = {(u['kind'], u['name']) for u in ledger.get('untracked', [])}
check(len(names) == len(items), '같은 에셋이 장부에 두 번 들어 있지 않다')

# 원본 흔적이 있는 에셋은 장부에 있어야 한다 (흔적 없는 것은 G2 사람 조사에 기댄다)
TRACE = re.compile(r'^license:|<!-- origin:', re.M)
missing = []
for kind in ('skills', 'rules', 'agents'):
    base = os.path.join(root, 'assets', kind)
    for name in sorted(os.listdir(base)):
        p = os.path.join(base, name)
        files = [p] if os.path.isfile(p) else [os.path.join(d, f) for d, _, fs in os.walk(p) for f in fs]
        traced = any(os.path.basename(f) in ('LICENSE', 'LICENSE.txt', 'NOTICE.md') for f in files)
        if not traced:
            for f in files:
                if f.endswith('.md'):
                    head = open(f, errors='ignore').read(4000)
                    if TRACE.search(head):
                        traced = True
                        break
        if traced and (kind, name) not in names | untracked:
            missing.append(f'{kind}/{name}')
check(not missing, '원본 흔적이 있는 에셋이 모두 장부(감시 또는 untracked)에 있다' + ('' if not missing else ' — 빠짐: ' + ', '.join(missing)))

# G2 — 전수 조사 표
audit = open(os.path.join(root, 'docs/audits/2026-11-15-upstream-inventory.md')).read()
rows = re.findall(r'^\| (skills|rules|agents|hooks) \| ([^|]+?) \| ([^|]+?) \|', audit, re.M)
table = {(k, n.strip()): c.strip() for k, n, c in rows}
actual = {(k, n) for k in ('skills', 'rules', 'agents', 'hooks') for n in os.listdir(os.path.join(root, 'assets', k))}
check(set(table) == actual, f'조사 표의 이름 = assets/ 이름 ({len(actual)}개)'
      + ('' if set(table) == actual else f' — 표에만 {sorted(set(table) - actual)[:3]} · assets 에만 {sorted(actual - set(table))[:3]}'))
CLASSES = {'공장 제작', '그대로', '고쳐 씀', '확인 못 함'}
odd = [k for k, c in table.items() if c not in CLASSES]
check(not odd, '행마다 분류가 넷 중 하나' + ('' if not odd else f' — {odd[:3]}'))
mismatch = [it['name'] for it in items
            if table.get((it['kind'], it['path'].rstrip('/').split('/')[-1])) != {'vendored': '그대로', 'adapted': '고쳐 씀'}[it['mode']]]
check(not mismatch, '장부의 mode 와 조사 표의 분류가 같다' + ('' if not mismatch else f' — {mismatch[:5]}'))
unknown = sum(1 for c in table.values() if c == '확인 못 함')
print(f'  · 확인 못 함 {unknown}개 (통과로 치되 센다)')

print(f"\n{'PASS' if not fails else 'FAIL'}: {len(fails)} 실패")
sys.exit(1 if fails else 0)
PY

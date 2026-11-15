#!/usr/bin/env python3
"""밖에서 가져온 에셋의 원본이 바뀌었는지 확인한다 (모델 호출 0).

계획: docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G4·G5
소우주에도 복사되므로 다른 .py 를 import 하지 않는 한 파일로 둔다. 바깥에 내놓는 것은 main 하나다.

  --check   원본 저장소마다 git 트리를 한 번 받아 장부 경로의 sha 를 컴퓨터 공용 상태에 쓴다.
            20시간 안에 확인한 저장소는 건너뛴다. 잠금으로 한 번에 하나만 돈다.
            전부 실패하면 상태를 건드리지 않고 종료 코드 3.
  --notice  네트워크 없이 상태만 읽어, 뒤처진 항목이 있으면 시작 훅용 JSON 한 줄을 낸다(컴퓨터마다 하루 1회).
  --show    이 프로젝트 장부 기준 상태를 사람이 읽게 출력한다.

시험용: UPSTREAM_FIXTURE_DIR 가 있으면 네트워크 대신 그 폴더의 <owner>__<repo>.json 을 읽는다.
"""
import argparse, datetime as dt, json, os, re, sys, time, urllib.error, urllib.request

_FRESH_HOURS = 20          # 저장소 하나를 다시 묻기까지
_RETRY_AFTER_FAIL_SEC = 3600
_NOTICE_EVERY_HOURS = 20   # 알림 간격 (컴퓨터 공용)
_LOCK_STALE_SEC = 600
_LOCK_WAIT_SEC = 40
_REQ_TIMEOUT = 10
_TOTAL_BUDGET = 30
_EXIT_ALL_FAILED = 3


def _now():
    return dt.datetime.now(dt.timezone.utc)


def _iso(t):
    return t.strftime('%Y-%m-%dT%H:%M:%SZ')


def _parse_iso(s):
    try:
        return dt.datetime.strptime(s, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=dt.timezone.utc)
    except (TypeError, ValueError):
        return None


def _read_json(path, default):
    try:
        with open(path, encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def _write_json_atomic(path, data):
    tmp = f'{path}.{os.getpid()}.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


# ── 원본 조회 ──────────────────────────────────────────────────────────────
class _FetchError(Exception):
    pass


def _fixture(repo, count=True):
    d = os.environ.get('UPSTREAM_FIXTURE_DIR')
    if not d:
        return None
    log = os.environ.get('UPSTREAM_FETCH_LOG')        # 시험: API(트리) 요청 수를 센다 — raw 는 한도 밖이라 안 센다
    if count and log:
        with open(log, 'a') as f:
            f.write(repo + '\n')
    if count:
        time.sleep(float(os.environ.get('UPSTREAM_FIXTURE_DELAY', '0')))   # 시험: 잠금 경쟁을 만든다
    path = os.path.join(d, repo.replace('/', '__') + '.json')
    if not os.path.exists(path):
        raise _FetchError('연결 실패(시험)')
    data = _read_json(path, None)
    if data is None:
        raise _FetchError('응답 모양이 다름(시험)')
    if isinstance(data, dict) and '__status' in data:
        raise _FetchError(f"HTTP {data['__status']}(시험)")
    return data


def _download_tree(repo):
    url = f'https://api.github.com/repos/{repo}/git/trees/HEAD?recursive=1'
    req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json',
                                               'User-Agent': 'harness-upstream-check'})
    try:
        with urllib.request.urlopen(req, timeout=_REQ_TIMEOUT) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise _FetchError(f'HTTP {e.code}') from e
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
        raise _FetchError(f'연결 실패: {e}') from e


def _fetch_tree(repo):
    """{path: sha}. 잘린 트리·한도 초과·모양 변화는 _FetchError."""
    data = _fixture(repo)
    if data is None:
        data = _download_tree(repo)
    tree = data.get('tree') if isinstance(data, dict) else None
    if not isinstance(tree, list) or data.get('truncated'):
        raise _FetchError('트리가 없거나 잘림')
    return {e['path']: e['sha'] for e in tree if isinstance(e, dict) and 'path' in e and 'sha' in e}


def _fetch_version(repo, path, version_from):
    """원본 파일 frontmatter 의 버전. 실패하면 None (raw 는 API 한도 밖)."""
    try:
        data = _fixture(repo, count=False)
    except _FetchError:
        return None
    rel = f"{path}/{version_from['file']}"
    if data is not None:
        text = (data.get('__raw') or {}).get(rel)
    else:
        try:
            with urllib.request.urlopen(f'https://raw.githubusercontent.com/{repo}/HEAD/{rel}',
                                        timeout=_REQ_TIMEOUT) as r:
                text = r.read(65536).decode('utf-8', 'replace')
        except (urllib.error.URLError, TimeoutError, OSError):
            return None
    if not text:
        return None
    m = re.search(rf"^{re.escape(version_from['frontmatter'])}:\s*['\"]?([\w.\-+]+)", text, re.M)
    return m.group(1) if m else None


# ── 상태 파일·잠금 ─────────────────────────────────────────────────────────
class _Paths:
    def __init__(self, state_dir):
        self.dir = state_dir
        self.state = os.path.join(state_dir, 'upstream-status.json')
        self.lock = os.path.join(state_dir, 'upstream-check.lock')
        self.last_fail = os.path.join(state_dir, 'upstream-last-attempt')
        self.last_notice = os.path.join(state_dir, 'upstream-last-notice')
        self.factory_path = os.path.join(state_dir, 'factory-path')


def _take_lock(p):
    """mkdir 한 번. 주인 기록에 실패하면 잡은 잠금을 풀고 False."""
    try:
        os.mkdir(p.lock)
    except FileExistsError:
        return False
    try:
        with open(os.path.join(p.lock, 'owner'), 'w') as f:
            f.write(f'{os.getpid()} {int(time.time())}\n')
        return True
    except OSError:
        _remove_dir(p.lock)
        return False


def _break_stale(p):
    """10분 지난 잠금을 고유 이름으로 옮긴 뒤 지운다 — 둘이 동시에 깨도 새 잠금을 지우지 않는다."""
    try:
        if time.time() - os.path.getmtime(p.lock) <= _LOCK_STALE_SEC:
            return
        moved = f'{p.lock}.stale.{os.getpid()}.{time.time_ns()}'
        os.rename(p.lock, moved)
    except OSError:
        return
    _remove_dir(moved)


def _acquire_lock(p, wait_sec):
    """mkdir 잠금. 낡은 잠금(10분)은 깬다. 못 잡으면 False."""
    deadline = time.time() + wait_sec
    while True:
        if _take_lock(p):
            return True
        if not os.path.isdir(p.lock):     # 주인 기록 실패 등 — 잠금이 없는데도 못 잡았다
            return False
        _break_stale(p)
        if time.time() >= deadline:
            return False
        time.sleep(0.5)


def _remove_dir(path):
    try:
        for name in os.listdir(path):
            os.remove(os.path.join(path, name))
        os.rmdir(path)
    except OSError:
        pass


def _release_lock(p):
    _remove_dir(p.lock)


def _repos_of(ledger):
    out = {}
    for it in ledger.get('items', []):
        for s in it.get('sources', []):
            out.setdefault(s['repo'], []).append((it, s))
    return out


def _is_fresh(state, repo, pairs, t):
    """이번에 묻지 않아도 되는가. 실패한 저장소는 1시간, 성공한 저장소는 20시간 동안 묻지 않는다.
    단 이 장부의 경로가 상태에 하나라도 없으면 다시 묻는다 — 다른 프로젝트가 같은 저장소의 다른 경로만 확인했을 수 있다."""
    r = state.get('repos', {}).get(repo, {})
    checked = _parse_iso(r.get('checked_at'))
    if checked is None:
        return False
    age = (t - checked).total_seconds()
    if r.get('error'):
        return age < _RETRY_AFTER_FAIL_SEC
    have = state.get('sources', {})
    if any(f"{repo}:{s['path']}" not in have for _, s in pairs):
        return False
    return age < _FRESH_HOURS * 3600


# ── --check ───────────────────────────────────────────────────────────────
def _recently_failed(p):
    try:
        return time.time() - os.path.getmtime(p.last_fail) < _RETRY_AFTER_FAIL_SEC
    except OSError:
        return False


def _check_one(repo, pairs, state, t):
    """저장소 하나의 트리를 받아 상태에 반영한다. 성공하면 True."""
    try:
        tree = _fetch_tree(repo)
    except _FetchError as e:
        state['repos'][repo] = {'checked_at': _iso(t), 'error': str(e)}
        return False
    state['repos'][repo] = {'checked_at': _iso(t)}
    for it, s in pairs:
        entry = {'sha': tree.get(s['path']), 'checked_at': _iso(t)}
        if it.get('version_from'):
            entry['version'] = _fetch_version(repo, s['path'], it['version_from'])
        state['sources'][f"{repo}:{s['path']}"] = entry
    return True


def _run_check(ledger, p):
    if _recently_failed(p) or not _acquire_lock(p, _LOCK_WAIT_SEC):
        return 0
    try:
        state = _read_json(p.state, {})        # 잠금을 잡은 뒤에 다시 읽는다 — 다른 프로젝트가 방금 확인했을 수 있다
        state.setdefault('repos', {})
        state.setdefault('sources', {})
        t = _now()
        todo = {r: pairs for r, pairs in _repos_of(ledger).items() if not _is_fresh(state, r, pairs, t)}
        if not todo:
            return 0
        started, ok = time.time(), 0
        for repo, pairs in todo.items():
            if time.time() - started > _TOTAL_BUDGET:
                break
            ok += _check_one(repo, pairs, state, t)
        if ok == 0:
            with open(p.last_fail, 'w') as f:
                f.write(_iso(t) + '\n')
            return _EXIT_ALL_FAILED
        state['checked_at'] = _iso(t)
        _write_json_atomic(p.state, state)
        return 0
    finally:
        _release_lock(p)


# ── 판정·알림 ──────────────────────────────────────────────────────────────
_RANK = {'same': 0, 'unknown': 1, 'behind': 2}


def _source_status(got, s):
    """(상태, 보일 버전). 확인은 됐는데 경로가 없으면 원본에서 옮겨지거나 지워진 것 — 알린다."""
    if not got:
        return 'unknown', None
    if not got.get('sha'):
        return 'behind', '원본에서 경로가 사라짐'
    return ('behind' if got['sha'] != s['sha'] else 'same'), got.get('version')


def _evaluate(ledger, state):
    """[{name, kind, mode, status: behind|same|unknown, latest}] — 이 장부 기준."""
    out = []
    for it in ledger.get('items', []):
        status, latest = 'same', None
        for s in it.get('sources', []):
            st, ver = _source_status(state.get('sources', {}).get(f"{s['repo']}:{s['path']}"), s)
            if _RANK[st] > _RANK[status]:
                status = st
            latest = ver or latest
        out.append({'name': it['name'], 'kind': it['kind'], 'mode': it['mode'], 'status': status, 'latest': latest})
    return out


def _factory_ledger(p):
    try:
        root = open(p.factory_path, encoding='utf-8').read().strip()
    except OSError:
        return None
    return _read_json(os.path.join(root, 'assets', 'upstream.json'), None) if root else None


def _factory_also_stale(b, factory, state):
    fi = next((i for i in factory.get('items', []) if (i['kind'], i['name']) == (b['kind'], b['name'])), None)
    if fi is None:
        return True
    for s in fi.get('sources', []):
        got = state.get('sources', {}).get(f"{s['repo']}:{s['path']}")
        if got and got.get('sha') and got['sha'] != s['sha']:
            return True
    return False


def _notice_text(behind, factory, state):
    """알림 문구 셋: 공장 없음 / 공장도 낡음 / 공장은 최신(전파 필요)."""
    label = [f"{b['name']} {b['latest']}" if b.get('latest') else b['name'] for b in behind[:5]]
    more = f' 외 {len(behind) - 5}개' if len(behind) > 5 else ''
    head = f"[upstream] 원본이 바뀐 외부 에셋 {len(behind)}개: {' · '.join(label)}{more}"
    if factory is None:
        return head + ' — 공장이 있는 컴퓨터에서 올려 주세요.'
    if any(_factory_also_stale(b, factory, state) for b in behind):
        return head + ' — "공장에서 올려" 라고 하면 공장에서 업데이트합니다.'
    return head + ' — 공장은 이미 올라가 있습니다. 이 프로젝트에 전파가 필요합니다.'


def _run_notice(ledger, p):
    state = _read_json(p.state, {})
    behind = [r for r in _evaluate(ledger, state) if r['status'] == 'behind']
    if not behind:
        return 0
    try:
        if time.time() - os.path.getmtime(p.last_notice) < _NOTICE_EVERY_HOURS * 3600:
            return 0
    except OSError:
        pass
    text = _notice_text(behind, _factory_ledger(p), state)
    try:
        with open(p.last_notice, 'w') as f:
            f.write(_iso(_now()) + '\n')
    except OSError:
        return 0           # 표시를 못 남기면 알림도 하지 않는다 — 매 세션 반복을 막는다
    print(json.dumps({'systemMessage': text,
                      'hookSpecificOutput': {'hookEventName': 'SessionStart', 'additionalContext': text}},
                     ensure_ascii=False))
    return 0


def _run_show(ledger, p):
    state = _read_json(p.state, {})
    print(f"마지막 확인: {state.get('checked_at', '없음')}")
    for r in _evaluate(ledger, state):
        tail = f" → {r['latest']}" if r['latest'] else ''
        print(f"  {r['status']:8} {r['kind']}/{r['name']} ({r['mode']}){tail}")
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--check', action='store_true')
    g.add_argument('--notice', action='store_true')
    g.add_argument('--show', action='store_true')
    ap.add_argument('--ledger', help='장부 경로 (기본: $CLAUDE_PROJECT_DIR/.claude/.upstream.json)')
    ap.add_argument('--state-dir', default=os.path.join(os.path.expanduser('~'), '.hermes'))
    a = ap.parse_args(argv)
    ledger_path = a.ledger or os.path.join(os.environ.get('CLAUDE_PROJECT_DIR', '.'), '.claude', '.upstream.json')
    ledger = _read_json(ledger_path, None)
    if not isinstance(ledger, dict) or not isinstance(ledger.get('items'), list):
        print(f'장부를 읽지 못했습니다: {ledger_path}', file=sys.stderr)
        return 2
    p = _Paths(a.state_dir)
    try:
        os.makedirs(p.dir, exist_ok=True)
    except OSError:
        print(f'상태 폴더를 만들지 못했습니다: {p.dir}', file=sys.stderr)
        return 0
    if a.check:
        return _run_check(ledger, p)
    if a.notice:
        return _run_notice(ledger, p)
    return _run_show(ledger, p)


if __name__ == '__main__':
    sys.exit(main())

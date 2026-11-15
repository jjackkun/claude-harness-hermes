#!/usr/bin/env python3
"""공장에서 밖에서 가져온 에셋 하나를 원본에 맞춰 올린다 (모델 호출 0, 공장 전용).

계획: docs/exec-plans/active/2026-11-15-upstream-version-watch-plan.md G7

  upstream-update.py <이름>                 그대로(vendored): 원본으로 바꾸고 장부의 시험을 돌린다.
                                            시험이 실패하면 되돌린다. 고쳐 씀(adapted): 바뀐 원본 파일만 보인다.
  upstream-update.py <이름> --mark-reviewed 고쳐 쓴 것을 사람이 반영한 뒤 장부 sha 를 최신으로 맞춘다.

공장 위치: --factory, 없으면 이 스크립트가 든 저장소, 그것도 아니면 ~/.hermes/factory-path.
소우주 세션은 `python3 "$(cat ~/.hermes/factory-path)/scripts/upstream-update.py" <이름>` 으로 부른다.
커밋·전파는 하지 않는다 — 사람이 시킬 때 한다.
시험용: UPSTREAM_FIXTURE_DIR 의 <owner>__<repo>.json 에서 tree·__raw·__trees 를 읽는다.
"""
import argparse, json, os, re, shutil, subprocess, sys, tempfile, urllib.error, urllib.request

_TIMEOUT = 15


class _Fail(Exception):
    pass


def _read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def _fixture(repo):
    d = os.environ.get('UPSTREAM_FIXTURE_DIR')
    if not d:
        return None
    path = os.path.join(d, repo.replace('/', '__') + '.json')
    if not os.path.exists(path):
        raise _Fail(f'{repo}: 연결 실패(시험)')
    return _read_json(path)


def _get_json(url):
    req = urllib.request.Request(url, headers={'Accept': 'application/vnd.github+json', 'User-Agent': 'harness-upstream-update'})
    try:
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as r:
            return json.load(r)
    except (urllib.error.URLError, TimeoutError, OSError, ValueError) as e:
        raise _Fail(f'GitHub 요청 실패: {url} — {e}') from e


def _tree(repo, ref='HEAD'):
    """[{path, sha, type}] — ref 는 HEAD 또는 트리 sha."""
    fx = _fixture(repo)
    if fx is not None:
        data = fx if ref == 'HEAD' else {'tree': (fx.get('__trees') or {}).get(ref)}
    else:
        data = _get_json(f'https://api.github.com/repos/{repo}/git/trees/{ref}?recursive=1')
    if not isinstance(data.get('tree'), list) or data.get('truncated'):
        raise _Fail(f'{repo}: 트리를 받지 못했거나 잘렸습니다 ({ref})')
    return data['tree']


def _raw(repo, path):
    fx = _fixture(repo)
    if fx is not None:
        text = (fx.get('__raw') or {}).get(path)
        if text is None:
            raise _Fail(f'{repo}: 파일 없음 {path}(시험)')
        return text.encode()
    try:
        with urllib.request.urlopen(f'https://raw.githubusercontent.com/{repo}/HEAD/{path}', timeout=_TIMEOUT) as r:
            return r.read()
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise _Fail(f'{repo}: 파일을 받지 못했습니다 {path} — {e}') from e


def _sha_at(tree, path):
    return next((e['sha'] for e in tree if e['path'] == path), None)


def _files_under(tree, path):
    """원본 경로 아래 파일(blob)들. path 가 파일이면 그 하나."""
    blobs = [e for e in tree if e.get('type', 'blob') == 'blob']
    exact = [e for e in blobs if e['path'] == path]
    return exact or [e for e in blobs if e['path'].startswith(path + '/')]


# ── 공장·장부 ─────────────────────────────────────────────────────────────
def _factory_root(arg):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    cands = [arg] if arg else [here]
    fp = os.path.join(os.path.expanduser('~'), '.hermes', 'factory-path')
    if not arg and os.path.exists(fp):
        cands.append(open(fp, encoding='utf-8').read().strip())
    for c in cands:
        if c and os.path.isfile(os.path.join(c, 'assets', 'upstream.json')):
            return c
    raise _Fail('공장을 찾지 못했습니다 — 이 컴퓨터에 공장이 없으면 공장이 있는 컴퓨터에서 올려 주세요.')


def _find_item(ledger, name):
    found = [i for i in ledger['items'] if i['name'] == name]
    if len(found) != 1:
        raise _Fail(f'장부에 "{name}" 이 {len(found)}개 있습니다. 이름을 확인해 주세요.')
    return found[0]


def _save_ledger(root, ledger):
    path = os.path.join(root, 'assets', 'upstream.json')
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(ledger, f, ensure_ascii=False, indent=2)
        f.write('\n')
    os.replace(tmp, path)


# ── 그대로(vendored): 교체 → 시험 → 실패면 되돌림 ──────────────────────────
def _apply_prefix(skill_md, prefix):
    with open(skill_md, encoding='utf-8') as f:
        text = f.read()
    m = re.search(r'^description:\s*(["\']?)(.*)$', text, re.M)
    if not m or m.group(2).startswith(prefix.strip()):
        return
    new = f'description: {m.group(1)}{prefix}{m.group(2)}'
    with open(skill_md, 'w', encoding='utf-8') as f:
        f.write(text[:m.start()] + new + text[m.end():])


def _stage(item, src, tree, stage):
    """원본 파일을 stage 에 내려받는다. 반환: stage 안의 설치 대상 경로."""
    files = _files_under(tree, src['path'])
    if not files:
        raise _Fail(f"{src['repo']}: 원본 경로가 없습니다 {src['path']}")
    single = len(files) == 1 and files[0]['path'] == src['path']
    skip = set(item.get('skip_files', []))
    for e in files:
        rel = os.path.basename(e['path']) if single else os.path.relpath(e['path'], src['path'])
        if rel in skip:
            continue
        dst = os.path.join(stage, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, 'wb') as f:
            f.write(_raw(src['repo'], e['path']))
    out = os.path.join(stage, os.path.basename(files[0]['path'])) if single else stage
    prefix = (item.get('local_patch') or {}).get('description_prefix')
    if prefix and os.path.isfile(os.path.join(out, 'SKILL.md')):
        _apply_prefix(os.path.join(out, 'SKILL.md'), prefix)
    return out


def _replace(target, new):
    if os.path.isdir(target):
        shutil.rmtree(target)
    elif os.path.exists(target):
        os.remove(target)
    if os.path.isdir(new):
        shutil.copytree(new, target)
    else:
        shutil.copy2(new, target)


def _run_tests(root, tests):
    for t in tests:
        r = subprocess.run(['bash', os.path.join(root, t)], cwd=root, capture_output=True, text=True)
        if r.returncode != 0:
            tail = '\n'.join((r.stdout + r.stderr).strip().splitlines()[-5:])
            return f'{t} 실패:\n{tail}'
    return None


def _update_vendored(root, ledger, item, latest_sha, tree):
    src = item['sources'][0]
    target = os.path.join(root, item['path'])
    with tempfile.TemporaryDirectory() as tmp:
        new = _stage(item, src, tree, os.path.join(tmp, 'new'))
        backup = os.path.join(tmp, 'old')
        if os.path.isdir(target):
            shutil.copytree(target, backup)
        else:
            shutil.copy2(target, backup)
        _replace(target, new)
        failed = _run_tests(root, item.get('tests', []))
        if failed:
            _replace(target, backup)
            raise _Fail(f"시험이 실패해 되돌렸습니다 — {item['name']}\n{failed}")
    src['sha'] = latest_sha
    _save_ledger(root, ledger)
    print(f"올렸습니다: {item['name']} ← {src['repo']} {src['path']} · 시험 {len(item.get('tests', []))}개 통과")
    print('커밋·전파는 하지 않았습니다. 확인한 뒤 공장에서 커밋하고 전파해 주세요.')


# ── 고쳐 씀(adapted): 바뀐 원본 파일만 보인다 ─────────────────────────────
def _changed_files(src, latest_tree):
    old = {e['path']: e['sha'] for e in _tree(src['repo'], src['sha']) if e.get('type', 'blob') == 'blob'}
    new = {os.path.relpath(e['path'], src['path']) if e['path'] != src['path'] else os.path.basename(e['path']): e['sha']
           for e in _files_under(latest_tree, src['path'])}
    if not old:   # 기록한 sha 가 파일(blob)이면 하위 트리가 없다 — 파일 하나가 바뀐 것
        return sorted(new)
    return sorted(p for p in set(old) | set(new) if old.get(p) != new.get(p))


def _show_adapted(item, trees):
    print(f"{item['name']} 은 공장이 고쳐 쓴 에셋이라 덮어쓰지 않습니다. 원본에서 바뀐 파일:")
    for src in item['sources']:
        latest = _sha_at(trees[src['repo']], src['path'])
        if latest == src['sha']:
            continue
        try:
            files = _changed_files(src, trees[src['repo']])
        except _Fail as e:
            files = [f'(목록을 받지 못함: {e})']
        print(f"  {src['repo']} {src['path']}")
        for f in files:
            print(f'    - {f}')
        print(f"    원본: https://github.com/{src['repo']}/tree/HEAD/{src['path']}")
    print(f"반영한 뒤: upstream-update.py {item['name']} --mark-reviewed")


def _mark_reviewed(root, ledger, item, trees):
    for src in item['sources']:
        latest = _sha_at(trees[src['repo']], src['path'])
        if latest:
            src['sha'] = latest
    _save_ledger(root, ledger)
    print(f"장부를 최신으로 맞췄습니다: {item['name']}")


def _run(a):
    root = _factory_root(a.factory)
    ledger = _read_json(os.path.join(root, 'assets', 'upstream.json'))
    item = _find_item(ledger, a.name)
    trees = {s['repo']: _tree(s['repo']) for s in item['sources']}
    if a.mark_reviewed:
        _mark_reviewed(root, ledger, item, trees)
        return 0
    behind = [s for s in item['sources'] if _sha_at(trees[s['repo']], s['path']) not in (None, s['sha'])]
    if not behind:
        print(f"이미 최신입니다: {item['name']}")
        return 0
    if item['mode'] == 'adapted':
        _show_adapted(item, trees)
        return 0
    src = item['sources'][0]
    _update_vendored(root, ledger, item, _sha_at(trees[src['repo']], src['path']), trees[src['repo']])
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('name')
    ap.add_argument('--mark-reviewed', action='store_true')
    ap.add_argument('--factory')
    a = ap.parse_args(argv)
    try:
        return _run(a)
    except _Fail as e:
        print(str(e), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError) as e:
        print(f'올리지 못했습니다: {e}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())

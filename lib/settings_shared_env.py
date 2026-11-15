"""settings.json(커밋되는 설정)의 env 에 프리셋 값을 넣는 것만 담당한다.

계획: docs/exec-plans/active/2026-11-15-impeccable-4-upgrade.md G6
ENV_VARS 는 settings.local.json(커밋 안 됨)으로 간다. 공장 없이 clone 만 한 컴퓨터도 같은 값을 써야 하는
변수는 프리셋의 SHARED_ENV_VARS 로 settings.json env 에 넣는다.
사용자가 env 에 넣은 다른 키는 그대로 둔다. 프리셋을 빼도 키는 걷지 않는다(값이 무해한 위치 지정뿐이라).
"""


def apply_shared_env(existing: dict, values: list) -> dict:
    """values: ['KEY=VALUE', ...]. existing['env'] 에 덮어 넣은 새 dict 를 돌려준다."""
    pairs = {}
    for kv in values:
        if '=' in kv:
            k, v = kv.split('=', 1)
            if k.strip():
                pairs[k.strip()] = v.strip()
    if not pairs:
        return existing
    env = dict(existing.get('env') or {}) if isinstance(existing.get('env'), dict) else {}
    env.update(pairs)
    return {**existing, 'env': env}

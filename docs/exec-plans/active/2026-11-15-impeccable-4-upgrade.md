# 2026-11-15-impeccable-4-upgrade — 공장 impeccable 사본을 2.1.1 → 4.9.1 로

## 1. 동기 (Why)

- 사용자가 apt-curtain 결과 화면을 "AI 스럽고 구리다" 고 했다(2026-11-14).
- 확인해 보니 공장 사본 `assets/skills/impeccable` 은 Initial commit 때 들어온 2.1.1 이었다. 명령은 craft·teach·extract 셋뿐이었다.
- 원본(pbakaus/impeccable)은 4.9.1(2026-11-14)이다. 명령 24개, 결정적 검출 규칙 62개, critique·audit·polish 가 있다.
- 공장이 소우주에 스킬을 깔아 주므로, 공장 사본이 낡으면 모든 소우주가 낡는다.

## 2. 목표 (What — 검증 가능한 형태)

- [x] G1 `assets/skills/impeccable/SKILL.md` frontmatter `version: 4.9.1` — `sed -n 1,8p` 로 확인
- [x] G2 원본 `.claude/skills/impeccable/` (Claude Code 판)의 SKILL.md·reference/·scripts/ 와 공장 사본이 설명 한 줄과 `scripts/live-browser.js`(§6) 를 빼고 같다 — `diff -rq`
- [x] G3 설명 첫머리에 한국어 한 문장(공장 관례, 커밋 38559cd)
- [x] G4 `assets/rules/web/design-quality.md` 가 teach/craft 대신 init·critique·audit·polish 와 PRODUCT.md·DESIGN.md 를 가리킨다
- [x] G5 `tests/claude-md-skill-index-test.sh` · `tests/mods-install-test.sh` 종료 0
- [ ] G6 엔진 바이너리·원격 통계 방침을 사용자가 정한다 (아래 §6 열린 결정)
- [x] G7 소우주 전파(update-all) — 2026-11-15 공장 1bee51d 를 4곳에 설치(jj-agent-room 은 설치만, drh-cloth-shop 커밋·푸시 747db52, apt-curtain 커밋 e6bc04e, 공장 baf49b3)

## 2-bis. 착수 전 확인한 사실 (2026-11-15)

- 원본 저장소 커밋 `1b2aa57` (2026-11-14), 최신 릴리스 `cli-v4.9.1`.
- 4.x 의 `scripts/impeccable` 은 런처다. 엔진 바이너리를 GitHub 릴리스에서 `~/.impeccable/bin/` 로 받는다(`IMPECCABLE_HOME` 으로 옮길 수 있음). 받은 파일은 `engine-checksums.txt` 의 sha256 으로 검증한다.
- 엔진은 새 디자인을 시작할 때 원격 통계를 보낸다. 끄는 법: `.impeccable/config.json` 의 `"telemetry": false` 또는 `DO_NOT_TRACK=1`.
- 이 세션에서 런처 실행은 자동 안전 판정이 막았다. SKILL.md 에 런처가 없을 때의 길("Launcher unavailable")이 있어 글만으로도 동작한다.
- 4.x 는 `.impeccable.md` 를 읽지 않는다. `PRODUCT.md`·`DESIGN.md` 를 읽는다.

## 3. 비목표 (Out of Scope)

- 엔진 바이너리를 공장에 넣거나 설치기가 받아 오게 하는 것 (G6 결정 뒤).
- `ui-prototype` 스킬의 `.impeccable.md` 참조 갱신 — 따로 한다.
- 소우주의 `.impeccable.md` → `PRODUCT.md` 이전.

## 4. 영향 영역

- `assets/skills/impeccable/**` (원본 소유 파일 — 공장이 고친 곳은 설명 첫 문장뿐)
- `assets/rules/web/design-quality.md`
- 이 계획서

## 5. 단계 (Steps)

### Step 1. 사본 교체 [단순]
원본 Claude Code 판을 통째로 복사하고 LICENSE·NOTICE.md 를 함께 둔다. 옛 reference 7개(typography 등)는 원본에서 없어졌으므로 지운다.

### Step 2. 공장 규칙 문구 [단순]

### Step 3. 결정·전파 [사용자]

## 6. 의사결정 로그

- `plugin/skills/impeccable` 이 아니라 `.claude/skills/impeccable` 판을 썼다 — 경로가 `.claude/skills/impeccable/scripts` 로 적혀 있어 소우주 설치 위치와 맞는다 — 틀리면 런처 경로가 어긋난다.
- 원본 파일은 설명 한 줄 말고 고치지 않았다 — 다음 갱신 때 덮어쓰기만 하면 되게 — 공장 고유 지침은 규칙 파일에만 있다.
- `scripts/live-browser.js`(13,901줄)는 공장 사본에서 뺐다 — R-size(500줄)가 막고, 이 파일은 엔진이 띄우는 `/impeccable live` 모드에서만 쓰인다 — live 모드는 이 파일이 없어 동작하지 않는다. G6 에서 엔진을 쓰기로 하면 R-size 원본 소유 예외를 `docs/audits/` 근거와 함께 정하고 되살린다.
- 열린 결정(G6): 엔진 바이너리를 쓰게 할지, 쓴다면 `IMPECCABLE_HOME` 을 프로젝트 안으로 둘지, 원격 통계를 끌지.

## 7. 발견·예외

- 같은 날 apt-curtain 결과 화면 시험(브랜치 `design/result-screen-trial`, 커밋 전)에서 4.9.1 의 Operate 규칙으로 배치를 고쳤다. 배치만으로는 AI 느낌이 남았고, 색·글꼴 세계를 바꾼 뒤에야 달라졌다.

## 8. 회고 (완료 시 작성)

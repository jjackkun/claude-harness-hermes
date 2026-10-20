# 검증 절차

`<스킬>` 은 이 스킬 폴더 (설치된 프로젝트에서는 `.claude/skills/ui-prototype`), `<시안>` 은 `docs/prototypes/<이름>`.

## ⑤ 기계 검사 — 브라우저 없이, 매번 전부

```bash
for f in <시안>/scripts/*.js <시안>/scripts/shell/*.js; do node --check "$f" || echo "문법 오류: $f"; done
python3 <스킬>/scripts/check_spec.py <시안>          # 명세표 ↔ 등록 장면 (종료 0 이어야 함)
grep -rlE 'type="module"|fetch\(' <시안>            # 0 줄이어야 함 — file:// 에서 빈 화면이 된다
wc -l <시안>/scripts/*.js <시안>/styles/*.css | sort -n | tail -3   # 250줄 넘는 화면 파일은 나눈다
grep -rnE '<금지어 원문>' <시안>                    # content-rules.md 금지어
```

`check_spec.py` 출력 읽기:

| 표식 | 뜻 | 고치는 곳 |
|---|---|---|
| `[불일치]` | 1차 명세 장면이 등록 안 됨, 또는 명세표에 없는 장면이 등록됨 | 화면 파일 또는 spec.md |
| `[끊김]` | 버튼이 명세표에 없는 번호를 가리킴 | 화면 파일 (번호 오타가 대부분) |
| `[행동]` | 명세표에 적힌 버튼이 화면에 없음 | 화면 파일 |
| `[틀]` | 명세 틀과 등록 틀이 다름, 또는 틀 값이 4종 밖 | 둘 중 맞는 쪽으로 |
| `[요구 누락]` | `requires` 의 요구 ID 가 어느 행 근거에도 없음 | spec.md (화면이 빠졌으면 화면도) |
| `[번호]` | 글자 규칙 위반·중복 | spec.md |
| `[로드]` | `screens-*.js` 가 index.html 에 안 실림 | index.html |
| `[render]` | 장면 render() 가 예외 | 화면 파일 |
| `[알림]` | 들어오는 버튼 없는 장면·아직 안 그린 2차 대상 | 실패 아님 — 의도면 근거 칸에 "목록 진입" |

종료 2(`[읽을 수 없음]`)는 명세표 양식이 깨졌거나 스크립트가 로드 중 멈춘 것 — 메시지의 파일부터 본다.

## ⑥ 시각 점검 — Playwright 가 있을 때

1. **서버는 배경으로.** `python3 -m http.server <포트> --bind 127.0.0.1` 을 `<시안>` 에서 배경 실행. 끌 때는 PID 를 골라 kill (`pkill -f` 를 다른 명령과 한 줄에 쓰면 자기 셸까지 죽는다).
2. **폭 4 × 테마 2 × 전 장면, 페이지 넘침을 숫자로.** 폭 1280 · 768 · 375 · 360 마다 창 크기를 바꾸고 아래를 실행한다. `overflow` 가 빈 배열이어야 한다.

   ```javascript
   async () => {
     const pick = document.getElementById("frame-pick"); const bad = [];
     for (const theme of ["light", "dark"]) {
       document.documentElement.dataset.theme = theme;
       for (const fr of ["", "phone", "tablet", "browser", "desktop"]) {
         pick.value = fr; pick.dispatchEvent(new Event("change"));
         for (const s of NB.list()) {
           NB.go(s.id); await new Promise((r) => requestAnimationFrame(() => r()));
           const de = document.documentElement;
           if (de.scrollWidth > de.clientWidth) bad.push(`${theme}/${fr || "기본"}/${s.id}: +${de.scrollWidth - de.clientWidth}`);
         }
       }
     }
     pick.value = ""; pick.dispatchEvent(new Event("change")); delete document.documentElement.dataset.theme;
     return { width: innerWidth, overflow: bad };
   }
   ```

   틀 **안** 넘침도 같은 반복에서 본다 — 페이지는 멀쩡해도 앱 화면 안이 가로로 밀리는 경우가 있다(크기 없는 아이콘 svg 가 원인이었다):

   ```javascript
   [...document.querySelectorAll("#device *")].filter((e) =>
     e.scrollWidth > e.clientWidth + 1 && !["visible", "hidden"].includes(getComputedStyle(e).overflowX)
     && !e.classList.contains("table-wrap"))   // 표 상자처럼 일부러 가로 스크롤을 둔 곳은 뺀다
   ```
3. **눈으로 보기.** 틀마다 대표 장면을 1280 라이트 · 1280 다크 · 375 라이트로 찍는다. **창 전체 스크린숏**만 쓴다 (요소 스크린숏은 장면을 바꾼다). 장면을 바꿀 때는 `NB.go(id)` 를 evaluate 로 부르고, 돌아온 캡션(`#stage-caption`)이 원하는 번호인지 확인한 뒤 찍는다.
4. **클릭 경로.** 명세표의 핵심 고리를 첫 장면부터 실제 click() 으로 끝까지 누른다. 확인 단계(시트·요약)가 있으면 그 안의 버튼도 누른다.
5. **고친 뒤 다시.** 고친 장면만이 아니라 2번을 다시 돈다 — 한 부품을 고치면 다른 장면이 넘친다.
6. **치우기.** `.playwright-mcp/` 를 지우고 `git status` 로 산출물이 안 남았는지 본다. 스크린숏은 `.playwright-mcp/` 아래에만 저장된다(작업 폴더 밖 경로는 거부).

Playwright 가 없으면: 2·3 을 사용자에게 부탁한다 — "폭을 줄였을 때 가로 스크롤이 생기는 장면이 있는지, 다크 모드에서 안 보이는 글자가 있는지" 처럼 볼 것을 구체적으로.
`file://` 로 직접 열기는 Playwright 가 막는 경우가 많다 — 그때는 ⑤ 의 모듈·fetch 검사로 갈음하고 보고에 "못 한 것" 으로 적는다.

## ⑦ 출력

```bash
python3 <스킬>/scripts/build_single.py <시안> --artifact <임시 폴더>/<이름>.artifact.html
# → docs/prototypes/<이름>.html (단일 파일, 문서 뼈대 포함) + 아티팩트용 (뼈대 없이 <title> 이 맨 앞)
```

- 외부 참조는 Google Fonts 만 통과한다. 다른 CDN 을 쓰면 build 가 실패한다 — 시안은 오프라인에서도 열려야 한다.
- 아티팩트 도구가 있으면 아티팩트용 파일을 게시한다. 다시 게시할 때는 **같은 파일 경로**로 — 주소가 유지된다. 도구가 없으면 단일 HTML 까지가 완료다.
- 빌드한 단일 HTML 을 한 번 열어 `NB.list().length` 가 장면 수와 같은지 본다.

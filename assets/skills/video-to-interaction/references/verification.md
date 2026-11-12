# 검증 — 수치와 나란히 대조

미리보기 폴더에 `check/verify.mjs` 를 두고, 사용자와 **같은 방식(file://)** 으로 연다. 전체 시험 묶음이 초록이어도
"끌면 접힌다" 를 재는 단언이 없으면 그 주장은 검증되지 않은 것이다 — 주장마다 수치 하나.

## 1. 페이지에 재는 구멍을 둔다

미리보기 스크립트 끝에 검증용 읽기 함수를 둔다(보기 전용, 상태를 바꾸지 않음).

```js
TK.debug = {
  stubCorner: () => ({ x, y }),   // 잡을 점의 페이지 좌표 (투영해서)
  center: () => ({ x, y }),
  depth: () => maxAbsZ,           // 제자리 평면에서 벗어난 정도
};
// 상태는 data 속성으로: canvas.dataset.torn = '0.46', dataset.side = 'back', dataset.ready = '1'
```

## 2. 스크립트 뼈대

```js
import { createRequire } from 'node:module';
// 브라우저는 프로젝트 e2e 설정과 같은 자리 — 예 apps/web/.playwright (없으면 ~/.cache/ms-playwright)
process.env.PLAYWRIGHT_BROWSERS_PATH ??= '<프로젝트>/apps/<앱>/.playwright';
const { chromium } = createRequire('<프로젝트>/apps/<앱>/package.json')('@playwright/test');
const browser = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] }); // 헤드리스 WebGL
// 콘솔 오류 수집 → 마지막에 0 단언
page.on('console', (m) => m.type() === 'error' && errors.push(m.text()));
page.on('pageerror', (e) => errors.push(String(e)));
await page.goto(pathToFileURL('<미리보기>/index.html').href);
await page.waitForSelector('[data-ready="1"]');
```

- 끌기: `mouse.down` → 30걸음 이동(걸음마다 16ms) → 수치 → `mouse.up` → 3초 뒤 수치
- 찢기: 영상의 손길 그대로(예 오른쪽 아래 끝 → 왼쪽 아래 60걸음), 중간 비율과 끝 비율·상태 문구
- 단추·키보드 대체 수단도 한 번씩 (뒤집기 단추와 F 키, 시연 단추)
- 라이트·다크 × 휴대폰 크기 스크린숏 → 미리보기 폴더 `shots/`
- 실패가 하나라도 있으면 종료 코드 1

## 3. 영상과 나란히

```bash
FF=$(bash <스킬>/scripts/video_frames.sh ffmpeg)
$FF -y -i shots/tearing.png -i .harness/out/<주제>-video/f/f0093.png \
  -filter_complex "[0]scale=-1:896[a];[1]scale=-1:896[b];[a][b]hstack" .harness/out/compare-tearing.png
```

- 높이가 다르면 hstack 이 실패한다 → 둘 다 같은 높이로 scale
- 헤드리스 소프트웨어 WebGL 은 초당 12~13프레임 — 0.9초짜리 뒤집기 중간은 클릭 직후 연속 스크린숏이나 짧은 대기(200ms)로 잡는다
- 실제 기기의 부드러움은 헤드리스로 알 수 없다 → 보고에 "체감 속도는 사용자 확인" 을 적는다

## 4. 브라우저가 없을 때

2026-11-12 평가: Linux Chromium 이 없었고, Playwright MCP 는 무응답으로 1814초를 잡아먹었다. 그 30분 동안 검증은 한 걸음도 나가지 않았다.

1. **찾는 순서 (명령 셋, 1분 안)** — 프로젝트 e2e 설정의 브라우저 자리(`PLAYWRIGHT_BROWSERS_PATH`, 예 `apps/<앱>/.playwright`) → `~/.cache/ms-playwright/chromium-*` → `command -v chromium google-chrome`.
   디스크 전체를 `find /` 로 뒤지지 않는다.
2. **무응답 한도 2분** — 브라우저 도구(Playwright MCP 포함)가 2분 안에 첫 응답을 주지 않으면 그 도구를 버리고 다음 길로 간다. 같은 도구를 다시 부르지 않는다.
3. **설치는 프로젝트 안에만, 사용자 승인 뒤** — 예 `PLAYWRIGHT_BROWSERS_PATH=.harness/out/pw-browsers npx playwright install chromium` (약 150MB 내려받기).
   전역 설치(`sudo`, `-g`, `--with-deps`)는 제안하지 않는다. 승인을 기다리는 동안 아래 5번을 먼저 한다.
4. **node 로 잴 수 있는 것은 node 로** — 물리·상태 계산(스프링 정지 시간, 넘김 판정, 찢김 비율)은 브라우저 없이 `check/unit.mjs` 로 잰다.
   이것은 브라우저 검증의 **일부**다. 화면 모양·콘솔 오류·영상과 나란히 대조를 대신하지 못한다.
5. **보고에 "검증 못 한 주장" 목록** — 주장마다 한 줄: `주장 — 못 잰 이유 — 사용자가 열어서 볼 곳`.
   예 `덜 밀면 한 번 넘쳐 돌아온다 — 브라우저 없음(node 수치만: 87px → −24px) — 카드를 반쯤 끌고 놓아 본다`.
   이 목록이 비어 있지 않으면 첫 줄에 "브라우저 검증 못 함" 을 쓴다.

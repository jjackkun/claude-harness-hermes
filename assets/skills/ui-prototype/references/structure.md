# 시안 폴더 구조와 화면 등록 규약

## 위치

```text
docs/prototypes/
├── <이름>/                  원본 — 여기를 고친다
│   ├── index.html           셸 마크업 + 스크립트 로드 순서
│   ├── spec.md              시안 명세표 (원본 중의 원본)
│   ├── styles/
│   │   ├── tokens.css       색·글꼴·간격 토큰 — .impeccable.md 로 채운다
│   │   ├── components.css   공통 부품 (버튼·시트·탭·입력·알약·표)
│   │   ├── shell.css        왼쪽 화면 목록 + 오른쪽 무대 (손대지 않음)
│   │   └── frames.css       틀 4종 (손대지 않음)
│   └── scripts/
│       ├── config.js        시안 이름·기본 틀·묶음 순서·좁은 화면 기준
│       ├── content.js       표시 내용 (문서 예시만 — content-rules.md)
│       ├── parts.js         공통 부품 HTML 함수
│       ├── screens-<역할>.js 화면 파일 (역할·묶음마다 하나)
│       └── shell/           공통 장치 — 손대지 않음
│           ├── frame.js     틀 적용·전환·축소 맞춤
│           └── registry.js  화면 등록·이동·화면 목록·테마
└── <이름>.html              단일 파일 출력 (build_single.py 가 만든다, 손으로 고치지 않음)
```

`<이름>` 은 영문 소문자·숫자·`-` (예 `customer-app`, `admin-web`). 한 저장소에 여러 시안이 폴더별로 공존한다.

## 파일을 고를 때

| 바꾸려는 것 | 고칠 파일 |
|---|---|
| 기능·흐름(화면 추가·버튼 연결) | `spec.md` 먼저 → `screens-*.js` |
| 색·글꼴·간격 | `tokens.css` |
| 여러 화면에 같이 나오는 덩어리 | `parts.js` + `components.css` |
| 화면에 보이는 값 | `content.js` (출처 주석과 함께) |
| 시안 이름·기본 틀·묶음 순서 | `config.js` |

화면 파일은 역할별로 나누고, 한 파일이 250줄을 넘으면 묶음을 하나 더 만든다(하류 최대 249줄).
새 화면 파일은 `index.html` 의 로드 태그에도 더한다 — 빠지면 `check_spec.py` 가 `[로드]` 로 잡는다.

## 로드 순서

`file://` 로 더블클릭해 열 수 있어야 하므로 ES 모듈·`fetch` 를 쓰지 않고 일반 `<script src>` 만 쓴다.
순서는 고정: `config` → `content` → `shell/frame` → `shell/registry` → `parts` → `screens-*` → `NB.start()`.

## 화면 등록

```javascript
NB.register({
  id: "EB-01a",          // 번호 — spec.md 의 번호와 같다
  group: "참여자",        // 화면 목록 묶음
  name: "엔빵 상세",      // 화면 목록에 보이는 이름
  state: "모집중",        // 선택 — 같은 화면의 상태
  caption: "앱 첫 화면",  // 선택 — 무대 아래 한 줄
  frame: "phone",        // 선택 — 없으면 config.js 의 frame
  render: () => `<div class="app">...</div>`,
  mount(root) { /* 선택 — 같은 화면 안의 변화(시트 여닫기·탭 전환) */ },
});
```

- 화면 안 이동은 `data-go="번호"`. 등록기가 무대 하나에 클릭을 한 번만 건다.
- 장면 사이에 이어져야 하는 값(결제 후 홈에 "진행 중" 표시)은 `NB.state` 에 둔다.
- 시트를 독립 장면으로 둘 때는 `NB.parts.overSheet(배경 번호, 시트 HTML, 닫으면 갈 번호, 이름)` — 배경 화면을 다시 그리지 않고 재사용한다.
- 앱 화면은 `<div class="app">`(위·아래 띠 고정, 가운데 스크롤), 웹 화면은 `<div class="web">`(통째 스크롤).

## 틀 4종

| 틀 | 쓰는 곳 | 크기 | 좁은 화면에서 |
|---|---|---|---|
| `phone` | 휴대폰 앱 | 390×844 | 틀 없이 전체 화면 |
| `tablet` | 태블릿 앱·키오스크 | 820×1180 (가로·세로 전환) | 축소 |
| `browser` | 웹 서비스·랜딩·웹앱 | 무대 폭 (최대 1280) × 800 | 틀 없이 전체 화면 |
| `desktop` | 관리자 웹·업무 도구 | 1440×900 | 축소 |

- 셸 위쪽 **틀 전환 도구**: 사용자가 고르면 그 세션 동안 모든 장면에 덮어쓴다 — 반응형 웹을 같은 장면으로 폭만 바꿔 볼 때. "틀: 장면 기본" 으로 해제.
- 축소는 바깥 상자에만 걸리고 안쪽 크기는 그대로라 클릭이 어긋나지 않는다.
- 좁은 화면 기준 폭은 `config.js` 의 `mobileMax` 하나다. CSS 는 `html[data-narrow]` 로 그 판정을 받는다 — 미디어쿼리에 숫자를 따로 적지 않는다.

## 두 시안이 같은 브랜드일 때

복사하지 말고 상대 경로로 재사용한다 — 복사본은 갈라진다.

```html
<link rel="stylesheet" href="../customer-app/styles/tokens.css">
<script src="../customer-app/scripts/shell/registry.js"></script>
```

`collect_scenes.js`·`check_spec.py`·`build_single.py` 모두 `../` 를 따라간다.

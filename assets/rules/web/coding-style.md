> This file extends [common/coding-style.md](../common/coding-style.md) with web-specific frontend content.

# Web Coding Style

## File Organization

### 폴더·배럴 구조 강제 범위 (R-struct — pre-commit)

게이트 `check-structure.mjs` 가 언어 설정표(`structure-langs.json`)대로 검사한다.
Tier A 는 그 확장자 파일이 있으면 자동으로, Tier B 는 `.harnessrc` 의 `STRUCT_LANGS_EXTRA="go rust"` 로 켠다.
끄기: `.harnessrc` 에 `HARNESS_STRUCT_LANGS=` (빈 값). 예외 경로: `STRUCT_EXEMPT="src/gen/"`.
기존 위반은 기준선(`.structbaseline`)에 넣으면 막지 않는다 — 갱신은 사람이 `node .git/hooks/check-structure.mjs --update-baseline`.

규칙 번호: 1·2·3 Vue 컴포넌트 · 4 전량 재노출 · 5 배럴 존재 · 6 깊은 import · 7 언어 무관(폴더당 파일 5개 초과·포괄 이름·타입별 폴더·깊이 8 초과, 전부 경고).
기능 루트는 `features/` 이고(Ruby 는 `lib/`), 그 바로 아래 폴더가 기능 폴더다. 이 표는 시험(`tests/structure-gate-test.sh`)이 설정표와 대조한다.

<!-- struct-scope:begin -->
| 언어 | Tier | 확장자 | 배럴 존재 | 깊은 import | 전량 재노출 |
|---|---|---|---|---|---|
| vue | A | .vue .js .jsx .ts .tsx | 1·2 차단 | 3 차단 | 4 차단 |
| js | A | .js .jsx .ts .tsx .mjs .cjs | 5 차단(feature-root) | 6 경고 | 4 차단 |
| svelte | A | .svelte | 5 차단(component-dir) · 5 차단(feature-root) | 6 경고 | — |
| python | A | .py | 5 차단(feature-root) · 5 경고(package-child) | 6 경고 | 4 경고 |
| java | A | .java | — | 6 경고 | 4 경고 |
| dart | A | .dart | 5 차단(feature-root) | 6 경고 | 4 경고 |
| go | B | .go | — | — | — |
| rust | B | .rs | 5 차단(feature-root) | 6 경고 | 4 차단 |
| kotlin | B | .kt .kts | — | 6 경고 | 4 경고 |
| csharp | B | .cs | — | 6 경고 | — |
| php | B | .php | — | 6 경고 | — |
| swift | B | .swift | — | — | 4 차단 |
| ruby | B | .rb | 5 차단(feature-root) | 6 경고 | — |
<!-- struct-scope:end -->

### Component Structure Rules — Vue (R-struct-1~3, 기계 강제 — pre-commit + ESLint)

Vue 컴포넌트는 아래 구조를 **반드시** 따른다. 위반 시 pre-commit hook 이 커밋을 차단한다.

```text
src/components/
└── Foo/                   ← 컴포넌트와 동일한 이름의 폴더
    ├── Foo.vue             ← 컴포넌트 파일
    └── index.js            ← 배럴: export { default } from './Foo.vue'

src/components/SomeFeature/
└── parts/
    └── Bar/               ← parts/ 하위도 동일 규칙
        ├── Bar.vue
        └── index.js
```

**금지:**
- `parts/Bar.vue` — 폴더 없이 `.vue` 직접 배치 (R-struct-1)
- `Foo/` 폴더에 `index.js` 없음 (R-struct-2)
- `import Foo from './Foo.vue'` — .vue 파일 경로 직접 import (R-struct-3)

**허용:**
- `import Foo from './Foo'` — 폴더명 import (배럴 경유)
- `components/ui/` — shadcn 등 자동생성물은 allowlist 처리

**에러 메시지 예시:**
```
[R-struct-1] src/components/parts/Bar.vue
  → src/components/parts/Bar/Bar.vue 로 이동 후 index.js 배럴 추가
  → import 경로를 './Bar.vue' 대신 './Bar' (폴더명) 으로 변경
  근거: assets/rules/web/coding-style.md §File-Organization
```

강제 장치: `assets/hooks/check-structure.mjs` (pre-commit, 옛 이름 `check-component-structure.mjs` 는 호환 래퍼), `lint-configs/harness-component-structure.config.js` (ESLint)

---

Organize by feature or surface area, not by file type:

```text
src/
├── components/
│   ├── hero/
│   │   ├── Hero.tsx
│   │   ├── HeroVisual.tsx
│   │   └── hero.css
│   ├── scrolly-section/
│   │   ├── ScrollySection.tsx
│   │   ├── StickyVisual.tsx
│   │   └── scrolly.css
│   └── ui/
│       ├── Button.tsx
│       ├── SurfaceCard.tsx
│       └── AnimatedText.tsx
├── hooks/
│   ├── useReducedMotion.ts
│   └── useScrollProgress.ts
├── lib/
│   ├── animation.ts
│   └── color.ts
└── styles/
    ├── tokens.css
    ├── typography.css
    └── global.css
```

## CSS Custom Properties

Define design tokens as variables. Do not hardcode palette, typography, or spacing repeatedly:

```css
:root {
  --color-surface: oklch(98% 0 0);
  --color-text: oklch(18% 0 0);
  --color-accent: oklch(68% 0.21 250);

  --text-base: clamp(1rem, 0.92rem + 0.4vw, 1.125rem);
  --text-hero: clamp(3rem, 1rem + 7vw, 8rem);

  --space-section: clamp(4rem, 3rem + 5vw, 10rem);

  --duration-fast: 150ms;
  --duration-normal: 300ms;
  --ease-out-expo: cubic-bezier(0.16, 1, 0.3, 1);
}
```

## Animation-Only Properties

Prefer compositor-friendly motion:
- `transform`
- `opacity`
- `clip-path`
- `filter` (sparingly)

Avoid animating layout-bound properties:
- `width`
- `height`
- `top`
- `left`
- `margin`
- `padding`
- `border`
- `font-size`

## Semantic HTML First

```html
<header>
  <nav aria-label="Main navigation">...</nav>
</header>
<main>
  <section aria-labelledby="hero-heading">
    <h1 id="hero-heading">...</h1>
  </section>
</main>
<footer>...</footer>
```

Do not reach for generic wrapper `div` stacks when a semantic element exists.

## Naming

- Components: PascalCase (`ScrollySection`, `SurfaceCard`)
- Hooks: `use` prefix (`useReducedMotion`)
- CSS classes: kebab-case or utility classes
- Animation timelines: camelCase with intent (`heroRevealTl`)

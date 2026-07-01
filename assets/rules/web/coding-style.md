> This file extends [common/coding-style.md](../common/coding-style.md) with web-specific frontend content.

# Web Coding Style

## File Organization

### Component Structure Rules (기계 강제 — pre-commit + ESLint)

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

강제 장치: `assets/hooks/check-component-structure.mjs` (pre-commit), `lint-configs/harness-component-structure.config.js` (ESLint)

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

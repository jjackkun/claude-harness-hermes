---
name: svelte-patterns
description: Svelte 5 runes, SvelteKit routing/load/form patterns, store patterns, and SSR/CSR decisions.
---

# Svelte / SvelteKit Patterns

Modern Svelte 5 + SvelteKit patterns. Prefer runes over legacy `$:` and `export let`.

## When to Activate

- Editing `.svelte` / `.svelte.ts` / `.svelte.js` files
- Working under `src/routes/` (+page, +layout, +server, +error)
- Writing `load()` functions, form actions, or hooks
- Designing stores, reactive state, or derived values
- SSR vs CSR decisions, data fetching, progressive enhancement

## Runes (Svelte 5)

```svelte
<script lang="ts">
  // state — reactive local state
  let count = $state(0);

  // derived — pure computed, re-runs only when deps change
  let double = $derived(count * 2);

  // effect — side effects, runs after DOM updates
  $effect(() => {
    document.title = `Count: ${count}`;
    return () => {}; // cleanup
  });

  // props — replace `export let`
  let { title, onclick }: { title: string; onclick: () => void } = $props();

  // bindable props
  let { value = $bindable() }: { value: string } = $props();
</script>
```

**Rules:**
- `$state` only for values that change. Never wrap immutable data.
- `$derived` for pure computation. No side effects inside.
- `$effect` for DOM/IO sync only. If you're using it to compute a value, use `$derived` instead.
- Avoid `$:` legacy syntax in new code.

## Component Props

```svelte
<script lang="ts">
  interface Props {
    user: { id: string; name: string };
    variant?: 'primary' | 'secondary';
    onclick?: (e: MouseEvent) => void;
    children?: import('svelte').Snippet;
  }

  let { user, variant = 'primary', onclick, children }: Props = $props();
</script>

<button class={variant} {onclick}>
  {user.name}
  {@render children?.()}
</button>
```

Use `Snippet` type for slot-like content. Snippets replace `<slot />` in Svelte 5.

## Stores (`$lib/stores`)

전역 상태는 `$lib/stores/` 에만. 컴포넌트 로컬이 기본.

```ts
// $lib/stores/auth.svelte.ts  — rune-based store
class AuthStore {
  user = $state<User | null>(null);
  loading = $state(false);

  get isAuthenticated() {
    return this.user !== null;
  }

  async login(email: string, password: string) {
    this.loading = true;
    try {
      const res = await fetch('/api/login', {
        method: 'POST',
        body: JSON.stringify({ email, password })
      });
      this.user = await res.json();
    } finally {
      this.loading = false;
    }
  }

  logout() {
    this.user = null;
  }
}

export const auth = new AuthStore();
```

Legacy `writable`/`readable`도 여전히 동작하지만 Svelte 5 프로젝트 신규 스토어는 rune class 방식 권장.

## SvelteKit Routing

```
src/routes/
├── +layout.svelte        # 공통 레이아웃
├── +layout.server.ts     # 모든 페이지에 props 주입 (서버)
├── +page.svelte          # 페이지 UI
├── +page.server.ts       # 서버 전용 load + actions
├── +page.ts              # universal load (SSR + CSR)
├── +server.ts            # API 엔드포인트 (GET/POST/...)
└── +error.svelte         # 에러 바운더리
```

## `load()` — 데이터 로딩

**서버 전용** (`+page.server.ts`) — DB 직접 접근, 시크릿 사용 가능:

```ts
import type { PageServerLoad } from './$types';

export const load: PageServerLoad = async ({ params, locals, fetch }) => {
  const user = await locals.db.user.findUnique({ where: { id: params.id } });
  if (!user) throw error(404, 'User not found');
  return { user };
};
```

**Universal** (`+page.ts`) — 클라이언트에서도 재실행됨. public API만:

```ts
export const load: PageLoad = async ({ fetch, params }) => {
  const res = await fetch(`/api/users/${params.id}`);
  return { user: await res.json() };
};
```

컴포넌트에서 사용:

```svelte
<script lang="ts">
  let { data } = $props();
</script>

<h1>{data.user.name}</h1>
```

## Form Actions + Progressive Enhancement

```ts
// +page.server.ts
import { fail, redirect } from '@sveltejs/kit';
import type { Actions } from './$types';

export const actions: Actions = {
  create: async ({ request, locals }) => {
    const data = await request.formData();
    const title = data.get('title') as string;

    if (!title) {
      return fail(400, { title, missing: true });
    }

    await locals.db.post.create({ data: { title } });
    throw redirect(303, '/posts');
  }
};
```

```svelte
<script lang="ts">
  import { enhance } from '$app/forms';
  let { form } = $props();
</script>

<form method="POST" action="?/create" use:enhance>
  <input name="title" value={form?.title ?? ''} />
  {#if form?.missing}<span class="error">Title required</span>{/if}
  <button>Create</button>
</form>
```

`use:enhance`는 JS 꺼진 환경에서도 동작하는 progressive enhancement 보장.

## `+server.ts` API Endpoints

```ts
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ url, locals }) => {
  const q = url.searchParams.get('q') ?? '';
  const results = await locals.db.search(q);
  return json(results);
};

export const POST: RequestHandler = async ({ request, locals }) => {
  const body = await request.json();
  if (!body.title) throw error(400, 'title required');
  const created = await locals.db.create(body);
  return json(created, { status: 201 });
};
```

## Hooks

```ts
// src/hooks.server.ts
import type { Handle } from '@sveltejs/kit';

export const handle: Handle = async ({ event, resolve }) => {
  const token = event.cookies.get('session');
  event.locals.user = token ? await verifyToken(token) : null;
  return resolve(event);
};
```

`event.locals` 에 넣은 값은 모든 `load()` / `+server.ts` 에서 접근 가능. 타입은 `src/app.d.ts` 의 `App.Locals` 에 선언.

## SSR vs CSR

- 기본은 SSR. SEO, 초기 로딩, noscript 환경 모두 대응.
- CSR만 필요한 페이지(대시보드, 내부 툴):
  ```ts
  // +page.ts
  export const ssr = false;
  export const csr = true;
  ```
- Static export: `+page.ts` 에 `export const prerender = true`.

## Anti-patterns

- ❌ `$state` 로 감싼 값을 다시 `writable()` 로 한 번 더 래핑
- ❌ `$effect` 안에서 다른 `$state` 값을 업데이트 (무한 루프 주의)
- ❌ 컴포넌트 내부에서 `fetch()` 직접 호출 → `load()` 사용
- ❌ 서버 시크릿을 `+page.ts` 나 클라이언트 컴포넌트로 import
- ❌ `.svelte-kit/` 커밋 (빌드 산출물)
- ❌ `<slot />` — Svelte 5 에선 `{@render children()}` 사용
- ❌ `export let foo` — Svelte 5 에선 `$props()` 사용

**Remember**: SvelteKit은 규약 기반이다. 파일명(`+page`, `+layout`, `+server`) 이 곧 API이므로 규약을 따르는 게 항상 옳다.

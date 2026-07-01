---
name: typescript-patterns
description: TypeScript type system patterns — strict mode, generics, discriminated unions, branded types, inference, utility types.
---

# TypeScript Patterns

Type-system-first TypeScript. Assume `strict: true`. Runtime patterns live in `node-patterns`; UI patterns live in `frontend-patterns` / `svelte-patterns`.

## When to Activate

- Designing types, interfaces, or type-level APIs
- Writing generic functions / classes
- Modeling domain data with discriminated unions
- Debugging type errors or fighting inference
- Configuring `tsconfig.json`

## tsconfig Baseline

```jsonc
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",   // or "NodeNext" for Node libraries
    "strict": true,
    "noUncheckedIndexedAccess": true, // arr[i] is T | undefined
    "noImplicitOverride": true,
    "exactOptionalPropertyTypes": true,
    "verbatimModuleSyntax": true,
    "skipLibCheck": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "isolatedModules": true
  }
}
```

**`noUncheckedIndexedAccess` is the single biggest correctness win** — forces you to handle undefined on array/object lookups.

## `type` vs `interface`

- **`type`** for unions, intersections, mapped types, conditional types, tuples, primitives.
- **`interface`** for object shapes that might be extended or declaration-merged (React props, API contracts).
- When in doubt, `type`. Interfaces are mostly legacy affordance.

## Discriminated Unions

The single most important domain-modeling tool.

```ts
type Result<T, E = Error> =
  | { ok: true;  value: T }
  | { ok: false; error: E };

function parseUser(json: string): Result<User> {
  try {
    return { ok: true, value: UserSchema.parse(JSON.parse(json)) };
  } catch (e) {
    return { ok: false, error: e as Error };
  }
}

// Narrowing is automatic
const r = parseUser(input);
if (r.ok) {
  console.log(r.value.name);   // User
} else {
  console.error(r.error);       // Error
}
```

```ts
// Finite state modeling
type LoadingState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

// Exhaustive switch
function render(state: LoadingState<User>) {
  switch (state.status) {
    case 'idle':    return '...';
    case 'loading': return 'Loading';
    case 'success': return state.data.name;
    case 'error':   return state.error.message;
    default:        return assertNever(state);
  }
}

function assertNever(x: never): never {
  throw new Error(`Unhandled: ${JSON.stringify(x)}`);
}
```

## Branded / Nominal Types

```ts
type Brand<T, B> = T & { readonly __brand: B };

type UserId    = Brand<string, 'UserId'>;
type SessionId = Brand<string, 'SessionId'>;

function makeUserId(raw: string): UserId {
  if (!/^u_[a-z0-9]+$/.test(raw)) throw new Error('bad UserId');
  return raw as UserId;
}

// Now UserId and SessionId can't be mixed up even though both are strings
function getUser(id: UserId) { /* ... */ }
// getUser(someSessionId);  // TYPE ERROR
```

Use for IDs, currencies, units, any primitive that has meaning beyond its type.

## Generics

```ts
// PASS: constrained generic — T must have an id
function indexById<T extends { id: string }>(items: T[]): Record<string, T> {
  return Object.fromEntries(items.map(item => [item.id, item]));
}

// PASS: inferred from usage, no need to specify <User>
const byId = indexById(users);
```

- Constrain with `extends` when the generic needs structure. Unconstrained `<T>` is usually a sign you don't really need a generic.
- Let inference do the work — don't specify type args unless inference fails.
- Don't use generics for "optional shape" — use discriminated unions.

## Utility Types (built-in)

```ts
type User = { id: string; name: string; email: string; passwordHash: string };

type PublicUser    = Omit<User, 'passwordHash'>;
type UserUpdate    = Partial<Pick<User, 'name' | 'email'>>;
type UserFields    = keyof User;                 // 'id' | 'name' | ...
type UserByField   = { [K in keyof User]: User[K] };  // mapped type

// Record
type UsersById = Record<string, User>;

// Return type inference
type CreateUserFn = typeof createUser;
type CreateUserResult = Awaited<ReturnType<CreateUserFn>>;
```

Know these cold: `Partial`, `Required`, `Pick`, `Omit`, `Record`, `ReturnType`, `Parameters`, `Awaited`, `NonNullable`, `Readonly`.

## Type Guards & Narrowing

```ts
// User-defined type guard
function isError(x: unknown): x is Error {
  return x instanceof Error;
}

// Assertion function
function assertDefined<T>(x: T | undefined, msg = 'undefined'): asserts x is T {
  if (x === undefined) throw new Error(msg);
}

// in operator narrowing
type Dog = { bark: () => void };
type Cat = { meow: () => void };

function speak(animal: Dog | Cat) {
  if ('bark' in animal) animal.bark();
  else animal.meow();
}
```

Prefer user-defined guards over type assertions (`as`). Each `as` is a lie to the compiler.

## Runtime Validation at Boundaries

The type system is a static check. At runtime boundaries (HTTP, file IO, user input), **validate with Zod or Valibot**, don't trust.

```ts
import { z } from 'zod';

const UserSchema = z.object({
  id: z.string(),
  name: z.string().min(1),
  email: z.string().email(),
  age: z.number().int().nonnegative().optional(),
});

type User = z.infer<typeof UserSchema>;   // one source of truth

const user = UserSchema.parse(await res.json()); // throws on mismatch
```

- Derive the type from the schema, not the other way around.
- Parse once at the boundary. Downstream code operates on trusted, typed data.

## `unknown` Over `any`

```ts
async function fetchJson(url: string): Promise<unknown> {
  const res = await fetch(url);
  return res.json();
}

// Caller must validate before using
const raw = await fetchJson('/api/user');
const user = UserSchema.parse(raw);
```

- `any` disables type checking. `unknown` forces narrowing before use.
- Prefer `unknown` as the return type for untrusted data, then validate.

## `readonly` and Immutability

```ts
type Config = {
  readonly port: number;
  readonly hosts: readonly string[];
};

function freeze<T>(x: T): Readonly<T> {
  return Object.freeze(x) as Readonly<T>;
}
```

- Mark props `readonly` when they shouldn't change. Mutation bugs go from "subtle runtime" to "compile error."
- Use `as const` on literal values for deep readonly narrow types.

## Module Boundaries

- **Export only the public surface.** Internal helpers stay unexported.
- **No circular imports.** If A imports B and B imports A, extract shared types into a third module.
- Use `import type` for type-only imports — erases at compile, avoids runtime cycles.
- Barrel files (`index.ts` re-exporting everything) make tree-shaking harder — use only at package boundaries.

## Anti-patterns

- ❌ `any` — if you must, comment *why* (e.g., `// any: 3rd-party untyped lib foo@1.2`)
- ❌ `// @ts-ignore` / `// @ts-expect-error` without a comment explaining the bug
- ❌ Type assertions (`as Foo`) to "fix" a type error — usually hides a real bug
- ❌ `!` non-null assertion on anything you don't 100% control
- ❌ `object` or `Function` types — too loose
- ❌ Mixing enums with union types. Prefer union-of-literals (`type Role = 'admin' | 'user'`).
- ❌ `namespace` — use modules
- ❌ Deeply nested conditional types when a discriminated union would do
- ❌ Generics everywhere — a function that takes `T` but never uses the type parameter is just noise
- ❌ `interface` declaration-merging to add fields to third-party types without isolating it

**Remember**: TypeScript's job is to make illegal states unrepresentable. If a bug can be expressed in the type, expressing it stops the bug at compile time. Invest in precise types at domain boundaries and the rest of the code writes itself.

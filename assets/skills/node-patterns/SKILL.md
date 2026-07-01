---
name: node-patterns
description: Node.js runtime patterns — ESM, package manager discipline, async/await, streams, error handling, environment config.
---

# Node.js Patterns

Modern Node.js (≥20) runtime patterns. Runtime-level concerns; framework patterns live in their own skills (svelte-patterns, fastapi-patterns, etc.).

## When to Activate

- Editing Node.js scripts, CLIs, or server entrypoints
- Configuring `package.json`, `tsconfig.json`, build/run scripts
- Working with the filesystem, streams, child processes
- Designing async flows, error propagation
- Deciding ESM vs CJS, dependency choices

## Package Management

**Always follow the existing lockfile** — don't switch managers casually.

| Lockfile | Manager |
|---|---|
| `pnpm-lock.yaml` | pnpm |
| `yarn.lock` | yarn |
| `package-lock.json` | npm |
| `bun.lockb` | bun |

- `engines` field in `package.json` pinning Node version
- `packageManager` field locks the manager version
- Prefer `npm ci` / `pnpm install --frozen-lockfile` in CI
- Never commit `node_modules/`

## ESM First

```json
// package.json
{
  "type": "module",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    }
  }
}
```

```ts
// use .js extensions in imports even for .ts source (TS ESM convention)
import { foo } from './foo.js';
import { readFile } from 'node:fs/promises';  // always 'node:' prefix for built-ins
```

- Use `node:` prefix for all built-in modules — makes intent explicit, avoids user-package shadowing.
- CJS only when forced by a legacy dependency. Document why.
- Top-level `await` is available in ESM — use it for bootstrap code.

## Async / Await

```ts
// PASS: parallel independent work
const [users, posts] = await Promise.all([
  fetchUsers(),
  fetchPosts(),
]);

// PASS: sequential when order matters
const user = await createUser(data);
const profile = await createProfile(user.id);

// PASS: bounded concurrency
import pLimit from 'p-limit';
const limit = pLimit(5);
const results = await Promise.all(
  urls.map(url => limit(() => fetch(url)))
);
```

- Never `await` inside a `for` loop when items are independent — use `Promise.all`.
- Never fire-and-forget a promise without `.catch()` or `void` — unhandled rejections crash Node 15+.
- Use `AbortController` / `AbortSignal` to cancel long operations (`fetch`, `setTimeout`, streams).

## Error Handling

```ts
// Typed error hierarchy
class AppError extends Error {
  constructor(
    message: string,
    public readonly code: string,
    public readonly cause?: unknown,
  ) {
    super(message);
    this.name = this.constructor.name;
  }
}

class NotFoundError extends AppError {
  constructor(resource: string, id: string) {
    super(`${resource} ${id} not found`, 'not_found');
  }
}

// Wrap with cause
try {
  await db.query(sql);
} catch (err) {
  throw new AppError('DB query failed', 'db_error', { cause: err });
}
```

- Use native `Error` with `cause` option (Node 16.9+) for chains.
- Catch at boundaries (request handlers, CLI entry) — not at every call site.
- Never `catch` and swallow silently. At minimum log + re-throw.
- Synchronous throws and promise rejections are different — don't mix them in one API.

## Streams & Backpressure

```ts
import { pipeline } from 'node:stream/promises';
import { createReadStream, createWriteStream } from 'node:fs';
import { createGzip } from 'node:zlib';

// PASS: pipeline handles backpressure + cleanup automatically
await pipeline(
  createReadStream('input.txt'),
  createGzip(),
  createWriteStream('output.txt.gz'),
);
```

- Prefer `stream/promises.pipeline` over manual `.pipe()` — handles errors and cleanup.
- For large files, never `readFile` the whole thing into memory — stream it.
- `for await (const chunk of readable)` is the idiomatic async iteration.

## Child Processes

```ts
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
const execFileAsync = promisify(execFile);

// PASS: execFile with argv array — no shell interpolation risk
const { stdout } = await execFileAsync('git', ['rev-parse', 'HEAD']);
```

- Always use `execFile` or `spawn` with an argv array. Never build a shell command string from user input — that's classic shell injection.
- The shell-based child-process API takes a single string and interprets metacharacters; prefer the argv-array form always.
- For long-running processes, `spawn` and stream stdout/stderr.

## Environment & Config

```ts
// config.ts
import { z } from 'zod';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().url(),
  JWT_SECRET: z.string().min(32),
});

export const env = EnvSchema.parse(process.env);
```

- Validate env vars at startup with a schema. Fail loud on missing/invalid.
- Never access `process.env.FOO` scattered across the codebase — read once into a typed config.
- Secrets via env vars, never committed files. `.env` in `.gitignore`.

## File System

```ts
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { join } from 'node:path';

// PASS: always use path.join / path.resolve, never string concatenation
const filePath = join(dataDir, 'users', `${id}.json`);

// PASS: async by default
const data = await readFile(filePath, 'utf8');

// PASS: ensure parent exists
await mkdir(join(dataDir, 'users'), { recursive: true });
```

- Use `node:fs/promises`, not the callback API, not `fs.*Sync` (except top-level startup).
- Always pass encoding (`'utf8'`) when reading text — otherwise you get a Buffer.
- Use `path.*` for all path manipulation — Windows has `\` separators.

## Logging

- Use a structured logger (pino, winston) in production. `console.log` is fine for CLIs and dev scripts.
- Log JSON lines to stdout. Let the platform (systemd, Docker, k8s) handle rotation.
- Never log secrets, tokens, passwords, PII. Scrub or redact.

## Testing

- `node --test` is built-in and fine for libraries. Vitest for apps with more tooling.
- Separate unit tests (pure functions) from integration tests (real IO).
- For async tests, await explicitly — don't return promises from `describe` callbacks.

## Anti-patterns

- ❌ `require()` in ESM projects — use `import`, or `createRequire` if you must
- ❌ `fs.readFileSync` in request handlers — blocks the event loop
- ❌ `new Promise((resolve, reject) => ...)` wrapping something that's already a promise
- ❌ Unhandled promise rejection — Node will crash on it
- ❌ Catching `Error` broadly, ignoring, and continuing
- ❌ Global mutable state across requests in a server process
- ❌ `npm install --force` to bypass peer dep warnings — fix the underlying mismatch
- ❌ Committing `.env` files
- ❌ `process.exit()` inside a library — let callers decide
- ❌ Mixing `await` and `.then()` in the same chain

**Remember**: Node's concurrency model is cooperative. One blocking operation in the event loop stalls everything. Async everything, stream everything, validate at the edges.

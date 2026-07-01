# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing ones:

```
// Pseudocode
WRONG:  modify(original, field, value) → changes original in-place
CORRECT: update(original, field, value) → returns new copy with change
```

Rationale: Immutable data prevents hidden side effects, makes debugging easier, and enables safe concurrency.

## Core Principles

### KISS (Keep It Simple)

- Prefer the simplest solution that actually works
- Avoid premature optimization
- Optimize for clarity over cleverness

### DRY (Don't Repeat Yourself)

- Extract repeated logic into shared functions or utilities
- Avoid copy-paste implementation drift
- Introduce abstractions when repetition is real, not speculative

### YAGNI (You Aren't Gonna Need It)

- Do not build features or abstractions before they are needed
- Avoid speculative generality
- Start simple, then refactor when the pressure is real

## Surgical Changes

When editing existing code, change only what the task requires. LLM edits tend
to sprawl — reformatting, "tidying" neighbors, refactoring untouched code — which
buries the real change and creates review and rollback hazards.

- **Touch only what you must.** Do not "improve" adjacent code, comments, or formatting.
- **Do not refactor what isn't broken.** A working block left alone is safer than a gratuitously rewritten one.
- **Match the existing style**, even if you would do it differently. Consistency over personal preference.
- **Mention unrelated dead code — do not delete it.** Surface it for the author to decide; removing it is a separate, explicit task.
- **Clean up only your own mess.** Remove the imports/variables/functions that *your* change made unused; never remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the request. If a diff line
cannot be explained by the task, it does not belong in the change.

> Adapted from Andrej Karpathy's notes on common LLM coding pitfalls.

## File Organization

**BEFORE writing any code**, design the file structure first:
1. List all features/responsibilities this task involves
2. Assign each responsibility to a separate file (1 FILE = 1 RESPONSIBILITY)
3. Define the per-feature barrel export plan (language-appropriate re-export file)
4. Only then start implementing, one file at a time

This prevents mid-implementation rewrites and token waste from hitting line limits.

Barrel pattern rules:
- Filename names the single responsibility; if a file ends up with 2+ responsibilities → split immediately
- Each **feature folder** has its own re-export file so call sites import from the folder, not individual files:
  - TypeScript/JavaScript: `<feature>/index.ts` or `<feature>/index.js`
  - Python: `<feature>/__init__.py`
  - Go: package boundary serves the same role (no extra file needed)
  - Other: follow the standard module re-export pattern (Rust: `mod.rs` with `pub use`, Java: package structure, etc.)
- The barrel lives at the **feature folder level**, not the project root
- The 4-step pre-implementation design prevents most line-limit violations. The thresholds below are safety nets for unexpected growth during implementation:
  - Soft limit (400 lines): warn that a split is needed soon
  - Hard limit (500 lines): stop adding code; extract one responsibility into a new file, update the barrel — **never rewrite the file from scratch**
- High cohesion, low coupling; organize by feature/domain, not by type

## Error Handling

ALWAYS handle errors comprehensively:
- Handle errors explicitly at every level
- Provide user-friendly error messages in UI-facing code
- Log detailed error context on the server side
- Never silently swallow errors

## Input Validation

ALWAYS validate at system boundaries:
- Validate all user input before processing
- Use schema-based validation where available
- Fail fast with clear error messages
- Never trust external data (API responses, user input, file content)

## Naming Conventions

- Variables and functions: `camelCase` with descriptive names
- Booleans: prefer `is`, `has`, `should`, or `can` prefixes
- Interfaces, types, and components: `PascalCase`
- Constants: `UPPER_SNAKE_CASE`
- Custom hooks: `camelCase` with a `use` prefix

## Code Smells to Avoid

### Deep Nesting

Prefer early returns over nested conditionals once the logic starts stacking.

### Magic Numbers

Use named constants for meaningful thresholds, delays, and limits.

### Long Functions

Split large functions into focused pieces with clear responsibilities.

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Functions are small (<50 lines)
- [ ] Files have a single responsibility named by filename; barrel re-exports used (≥400: warn / ≥500: split into new file, never rewrite)
- [ ] No deep nesting (>4 levels)
- [ ] Proper error handling
- [ ] No hardcoded values (use constants or config)
- [ ] No mutation (immutable patterns used)
- [ ] Surgical diff — every changed line traces to the request; no unrelated reformatting or refactors

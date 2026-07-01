# Method catalog

Tag vocabulary for `plan-verification-split`. One tag per criterion. Pick the most specific tag that actually fits — prefer `[auto:db-query]` over a generic `[auto:code-check]` when a row exists to prove the point.

Examples below are deliberately generic (common table/endpoint names, stack-neutral commands). Replace them with your project's real commands when you use the tag in an audit.

## `[auto:*]` — the agent can verify this now

### `[auto:db-query]`

Direct database read. Best for state-mutation criteria: "record created", "status changed", "counter incremented", "flag set", "soft-delete applied".

**Evidence shape**: SQL statement + raw rows (or row count).

```
SELECT id, email, status, last_login_at
FROM users WHERE id = 42;
--
(42, 'alice@example.com', 'active', 2026-01-15 09:30:11+00)
```

### `[auto:api-call]`

Hit an HTTP endpoint with curl / httpx / the project's API client. Best for: "endpoint returns X", "validation rejects Y", "status code is Z".

**Evidence shape**: method + path + request body + response status + relevant response body fields.

```
POST /api/orders  (body: {"user_id":42,"items":[]})
→ 422 {"detail":"items must not be empty"}
```

If auth is required and you don't have a token, say so and either downgrade to `[auto:code-review]` with a clear note, or escalate to `[human:access]`.

### `[auto:code-grep]`

Static verification that a behavior exists by reading the source. Best for: "endpoint exists", "route is registered", "filter is applied", "constant has this value", "import was added".

**Evidence shape**: grep pattern + the actual matching file:line (not a summary).

```
grep -n 'status=active' src/services/users.py
# 87:    query = query.filter(User.status == "active")
```

Use sparingly — grep proves the code path exists, not that it runs. If runtime proof is achievable via db-query or api-call, prefer those.

### `[auto:log-scan]`

Grep / tail application logs for an event after triggering an action. Best for: "background job ran", "error was logged", "event was emitted", "warning fired on edge case".

**Evidence shape**: log file path + grep pattern + the matched line with timestamp.

```
grep 'order.created' logs/app.log | tail -3
2026-01-15 09:31:02 INFO order.created id=1001 user_id=42 total=29.99
```

### `[auto:process-check]`

Inspect running processes, listeners, or managed services. Best for: "service is up on port X", "daemon is online", "worker pool has N workers".

**Evidence shape**: `ps` / `lsof` / `systemctl status` / process-manager `list` output — whichever fits your stack.

```
lsof -iTCP:8080 -sTCP:LISTEN
node   12345 alice  20u  IPv6 ...  TCP *:8080 (LISTEN)
```

### `[auto:file-check]`

A file / directory / symlink exists or has a given shape. Best for: "migration file was added", "config was written", "artifact was produced", "generated SDK is present".

**Evidence shape**: `ls -la` or `stat` or a small `head`/`wc -l` excerpt.

```
ls -la migrations/ | grep 2026_01_15
-rw-r--r-- 1 alice alice 1823 Jan 15 09:20 2026_01_15_add_status_to_users.sql
```

### `[auto:diff-inspect]`

Git diff / git show of the relevant commit demonstrates the change. Best for: "commit X touches file Y", "field Z was added to the schema", "old behavior was removed".

**Evidence shape**: `git show <sha> -- <path>` excerpt (just the relevant hunk).

### `[auto:code-review]`

Fallback: a non-trivial piece of code was reviewed by a reviewer subagent (spec or quality) and found correct. Use only when the other auto tags don't fit — e.g., the behavior is a multi-step UI interaction you cannot execute as the agent.

**Evidence shape**: the reviewer's verdict sentence + the reviewer agent name + the exact file:line ranges they cite. Never just "the reviewer said PASS" — include the citations.

This tag is honest about its limits: it proves the code is *structured* to satisfy the criterion, not that a real user clicking produces the expected visual outcome.

## `[human:*]` — the agent cannot verify this

### `[human:visual]`

The criterion is about how something looks or feels: color, spacing, hierarchy, animation smoothness, copy tone, empty-state friendliness. Even if you can grep the class name, the user has to look.

**What to ask**: show the user the exact URL and a minimal step to reach the view. Keep the question scoped to one thing.

### `[human:env]`

Physical or environment-owned action the agent cannot perform: drop a file in a folder on the user's machine, plug in a USB device, receive an SMS, click a real OAuth consent screen, upload from a phone camera, press a hardware button.

**What to ask**: describe the exact action in one sentence and what to observe after. Don't pad it with setup the user already knows.

### `[human:judgment]`

A call the user has to make: "does this error message make sense", "is this UX confusing", "is this warning severe enough to block". No amount of automation substitutes for human judgment on subjective quality.

**What to ask**: show the current output + what the alternative would be, and let them decide.

### `[human:access]`

Something you technically could verify but don't have credentials/permissions for: production DB, an SSO-protected admin panel, a paid API key, a staging environment behind VPN.

**What to ask**: either request temporary access, or ask the user to run the exact command you would have run and paste the output.

## Picking the right tag — quick rules

- If it's about **state** (DB row, response code, counter, flag), it's almost always `[auto:db-query]` or `[auto:api-call]`.
- If it's about **structure** (route exists, field added, enum includes X), it's `[auto:code-grep]` or `[auto:diff-inspect]`.
- If it's about **events** (log emitted, message published, email queued), it's `[auto:log-scan]`.
- If it's about **appearance or feel**, it's `[human:visual]`.
- If it's about **real-world physical action**, it's `[human:env]`.
- If you hesitate between `auto` and `human`, default to `human:<reason>` and say why. Over-tagging `auto` is how this skill loses credibility.

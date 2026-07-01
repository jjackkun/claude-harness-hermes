---
name: plan-verification-split
description: Use this skill whenever a plan or spec contains an acceptance-criteria checklist ("수용 기준", "acceptance criteria", "manual verification", "수동 검증", browser walk-through, feature sign-off) that the agent needs to confirm before marking the work done. Split every item into programmatically-verifiable (auto) and human-only (human) parts, run the auto parts immediately, record evidence in the audit doc, and ask the user only for the residual human items. Invoke even when the plan labels the step "수동 검증" or "manual test" — most such checklists have items an agent can prove without user eyes via a DB query, API call, grep, or log scan. The point is to stop dumping the entire checklist on the user when half of it is mechanically verifiable.
---

# plan-verification-split

A lot of implementation plans end with a list of acceptance criteria that the agent is supposed to "verify" before closing the task. The default reflex is to paste the whole list into chat and ask the user to click through it. That's lazy and it wastes the user's time, because most items can be proven by evidence the agent can collect itself — a DB row, a response body, a grep hit, a file existing — while only a smaller set genuinely requires human eyes (visual rendering, real user input, external hardware).

This skill exists so you split the list once, do the auto work yourself, and only pull the user in for the parts that actually need them.

## Core idea

Every acceptance criterion gets one tag. Tags are of two families:

- `[auto:<method>]` — the agent can verify this directly, right now, with tools it already has.
- `[human:<reason>]` — the agent cannot verify this; a human (or a physical environment) must.

The method or reason goes after the colon so future readers can see **how** the item was checked, not just that it was. This matters because "auto" without a method is a lie — six months later nobody remembers whether "item 4 PASS" meant "I saw the DB row" or "the toast popped up in my head."

## When to use this skill

Invoke it the moment you encounter a verification checklist in a plan or spec — before you type "please check items 1 through 8" into the chat. Also invoke it when:

- A user asks you to run a plan's Task 5 / Task N "manual verification" step.
- You've finished implementing and want to close the loop on a feature's acceptance criteria.
- You're writing an audit document and need a defensible record of which items actually passed and which are pending.
- You catch yourself about to list 8 things for the user to click — stop, tag them first.

It is *not* for general build/test gates (use `verification-loop` for those). This skill operates at the **feature acceptance** layer, one level above unit/integration tests.

## The flow

1. **Read the checklist**. Find it in the plan doc. If the plan doesn't have an explicit list, derive one from the design doc's success criteria.

2. **Tag every item**. Use the tag vocabulary in `references/method-catalog.md`. One tag per item. If you genuinely can't decide, default to `[human:judgment]` and say why — never fake an `auto` tag. You can optionally show the tagged list to the user for a quick sanity check before running the autos; do this if the list is long or the tagging is non-obvious, skip it if the tags are clearly right.

3. **Run the autos before you ask anything**. For each `[auto:*]` item, execute the check and capture the evidence (a command output, a row count, a grep line, a status code). Don't batch questions to the user first — the whole point is to shrink the human list.

4. **When an auto FAILs, diagnose before declaring a defect**. A FAIL can mean (a) a real code bug introduced by this feature, (b) stale data state left over from a previous session or aborted run, or (c) an environment drift (wrong branch deployed, old service running, etc.). Check (b) and (c) before opening a fix loop. A DB row stuck in a terminal state, a cache not cleared, a process running on the wrong port — these are not bugs in the feature under test. Say in your report which category you think the FAIL belongs to and why.

5. **Record each result in the audit doc**. Use the template in `references/audit-template.md`. Every row should have: criterion text, tag, status (PASS / FAIL / PENDING), evidence or command, and — if a defect was found and fixed — a link to the fix commit.

6. **Present only the human residual**. Show the user a short list containing only `[human:*]` items (or `auto` items that FAILed and still need confirmation). If the list is empty, say so and close the loop.

7. **Keep the tags in the audit**. Don't strip them after verification — the tags *are* the trail that lets someone re-run or audit the same checklist next time without re-discovering which items are automatable.

## How to tag honestly

The biggest risk with this skill is over-tagging things as `auto` because it's convenient. Some heuristics:

- "Visual" is not the same as "rendered". If the criterion says "red badge appears" and you can prove the badge component receives the right prop and the DOM emits the class, that's `[auto:code-grep]` or `[auto:dom-snapshot]`. If the criterion says "the badge *looks* right / color is tasteful / animation feels smooth", that's `[human:visual]`. The word "feels" is a dead giveaway.

- "WS broadcast arrives at other tabs" sounds human but usually isn't. You can verify the backend emits the event and the store handler updates state; the user only needs to confirm if you suspect a browser/device-specific bug. Default to `[auto:log-scan]` or `[auto:code-review]` + note that cross-tab propagation is inferred, not observed.

- Anything involving real physical I/O (drop files in a folder, plug in a device, upload from a phone) is `[human:env]` and you should be upfront that you can't do it. Don't pretend `touch /tmp/fake.txt` is equivalent.

- Anything requiring a human value judgment ("is the copy clear", "is the error message helpful", "does the empty state feel welcoming") is `[human:judgment]`. These deserve real review; don't try to fake them with a grader subagent.

## What evidence looks like

Good evidence is copy-pastable and reproducible: a command plus the raw output it produced. Bad evidence is a summary ("I checked and it works", "the code looks right", "per the review agent it passes"). See `references/method-catalog.md` for the exact evidence shape expected per tag.

If you spawn a subagent to do the verification for you, the subagent's report is not evidence — the subagent's *commands and outputs* are evidence. Require it to include raw command output in its report and copy that into the audit.

## Defects discovered during verification

When an `[auto:*]` item FAILs, you've just found a defect that unit tests missed. Don't silently fix it and mark PASS. Instead:

1. Record the FAIL in the audit with full evidence.
2. Open a fix loop (implementer → spec review → code quality review if the harness uses sandwich reasoning).
3. After the fix lands, add a new row or annotate the existing one with "PASS (fix <commit-sha>)" and a one-line explanation of the defect and the fix. This is load-bearing for the audit's credibility.

The verify-then-fix discipline is *how* this skill earns its keep. Otherwise the checklist is just ceremony.

## Scope boundaries

- **Not** for pre-commit gates (build, lint, typecheck). Use `verification-loop` or the existing git hook for those.
- **Not** for subjective design review (copy, typography, visual hierarchy). Those go through `critique`, `typeset`, `clarify`, etc.
- **Not** a substitute for unit or integration tests. If an item is going to be verified repeatedly in CI, write a test; the checklist is for the one-shot acceptance confirmation at feature-complete time.

## Reference files

- `references/method-catalog.md` — the `[auto:*]` and `[human:*]` tag vocabulary with one-line descriptions and example evidence for each.
- `references/audit-template.md` — the markdown table format the audit doc should use, plus an example row for each tag.

Read the catalog when you're unsure which tag fits a given criterion; read the template when you're about to write the audit doc.

## Anti-patterns

1. **"Run the whole checklist on the user"** — the behavior this skill exists to prevent. If you're about to list 8 items and ask the user to report back, stop and tag first.

2. **Fake auto tags** — marking `[auto:*]` on something you actually can't verify, then writing "PASS" with no evidence. Worse than marking `human:*` because it hides the gap.

3. **Evidence by agent report** — "my subagent said it passed". Subagents lie, especially when under pressure to close the task. Demand raw output.

4. **Tagging after the fact** — tagging items only after you've guessed the answer. The point of the tags is to decide **before** doing the work which items you can prove yourself. Tag first, run second.

5. **Dropping the tags after the audit** — future auditors need to know *how* each item was verified. Keep the tags in the committed audit doc, not just in your scratchpad.

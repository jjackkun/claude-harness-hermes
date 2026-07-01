# Agent Orchestration

## Available Agents

Located in `~/.claude/agents/`:

| Agent | Purpose | When to Use |
|-------|---------|-------------|
| planner | Implementation planning | Complex features, refactoring |
| architect | System design | Architectural decisions |
| tdd-guide | Test-driven development | New features, bug fixes |
| code-reviewer | Code review | High-impact or risky code changes |
| security-reviewer | Security analysis | Security-sensitive changes |
| build-error-resolver | Fix build errors | When build fails |
| e2e-runner | E2E testing | Critical user flows |
| refactor-cleaner | Dead code cleanup | Code maintenance |
| doc-updater | Documentation | Updating docs |
| rust-reviewer | Rust code review | Rust projects |

## Agent Usage Guidance

Use agents when they materially reduce risk or clarify a non-trivial task:
1. Complex feature or refactor - consider **planner**.
2. Architectural decision or shared boundary change - consider **architect**.
3. Security, auth, payment, data-loss, concurrency, or broad API changes - consider **code-reviewer** or a domain reviewer.
4. Simple local edits, obvious bug fixes, and documentation updates usually do not need agent review.

## Parallel Task Execution

For independent high-value checks, parallel Task execution is preferred:

```markdown
# GOOD: Parallel execution
Launch 3 agents in parallel:
1. Agent 1: Security analysis of auth module
2. Agent 2: Performance review of cache system
3. Agent 3: Type checking of utilities

# BAD: Sequential when unnecessary
First agent 1, then agent 2, then agent 3
```

## Multi-Perspective Analysis

For complex problems, use split role sub-agents:
- Factual reviewer
- Senior engineer
- Security expert
- Consistency reviewer
- Redundancy checker

# Code Review Standards

## When to Review

Review is recommended when the change carries meaningful risk:

- When security-sensitive code is changed (auth, payments, user data)
- When architectural changes are made
- When DB schema/migration, concurrency, public API, or broad cross-module behavior changes
- Before merging pull requests

Small local fixes, formatting-only changes, docs, and low-risk test updates usually do not need an agent review.

## Before Review

- Run available automated checks first.
- Establish review scope with `git diff`, staged diff, or PR diff.
- Note any checks that could not be run.

## Review Checklist

- [ ] Code is readable and well-named
- [ ] Files have a single responsibility named by filename
- [ ] Errors are handled explicitly
- [ ] No hardcoded secrets or credentials
- [ ] Tests exist for new functionality
- [ ] Changed behavior has a reproducible verification path

## Security Review Triggers

Consider `security-reviewer` when the change touches:

- Authentication or authorization code
- User input handling
- Database queries
- File system operations
- External API calls
- Cryptographic operations
- Payment or financial code

## Agent Selection

Use the narrowest reviewer that matches the risk:

| Agent | Purpose |
|-------|---------|
| **code-reviewer** | General code quality, patterns, best practices |
| **security-reviewer** | Security vulnerabilities, OWASP Top 10 |
| **typescript-reviewer** | TypeScript/JavaScript specific issues |
| **python-reviewer** | Python specific issues |
| **go-reviewer** | Go specific issues |
| **rust-reviewer** | Rust specific issues |

## Approval Criteria

- **Block**: Critical security, data loss, or clear correctness regression
- **Warn**: Significant bug or missing verification
- **Note**: Maintainability or follow-up concern

## Integration with Other Rules

This rule works with:

- [testing.md](testing.md) - Test coverage requirements
- [security.md](security.md) - Security checklist
- [git-workflow.md](git-workflow.md) - Commit standards
- [agents.md](agents.md) - Agent delegation

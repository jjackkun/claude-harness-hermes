# Performance Optimization

## Model Selection Strategy

Current generation (2026-09): Claude 5 family + Haiku 4.5. Pick by task shape, not by habit —
newer models often match the previous generation's high effort at a lower effort setting, so
re-measure before assuming a bigger model is needed.

**Haiku 4.5** (`claude-haiku-4-5-20251001`) — cheapest, fastest:
- Lightweight agents with frequent invocation
- Short classification / summarization in background hooks (hermes summarize · dream · crystallize)
- Worker agents in multi-agent systems

**Sonnet 5** (`claude-sonnet-5`) — default for coding:
- Main development work
- Orchestrating multi-agent workflows
- Most code review and refactoring

**Opus 5** (`claude-opus-5`) — deep reasoning:
- Complex architectural decisions
- Research and analysis tasks
- Long-context or ambiguous investigations

**Fable 5.1** (`claude-fable-5-1`) — most capable, reserve for:
- Decisions where a wrong answer is expensive to reverse
- Cases where Opus 5 measurably falls short (keep the measurement)

## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Extended Thinking + Plan Mode

Extended thinking is enabled by default, reserving up to 31,999 tokens for internal reasoning.

Control extended thinking via:
- **Toggle**: Option+T (macOS) / Alt+T (Windows/Linux)
- **Config**: Set `alwaysThinkingEnabled` in `~/.claude/settings.json`
- **Budget cap**: `export MAX_THINKING_TOKENS=10000`
- **Verbose mode**: Ctrl+O to see thinking output

For complex tasks requiring deep reasoning:
1. Ensure extended thinking is enabled (on by default)
2. Enable **Plan Mode** for structured approach
3. Use multiple critique rounds for thorough analysis
4. Use split role sub-agents for diverse perspectives

## Build Troubleshooting

If build fails:
1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix

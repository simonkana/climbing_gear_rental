# CLAUDE.md

@AGENTS.md
@GUARDRAILS.md

## Claude Code specifics
- Start each phase in plan mode; exit only after the human approves the file list and commit steps.
- Keep the `Co-Authored-By` trailer in proposed commit messages: AI usage is intentionally visible in history.
- Use the task list with one task per commit step; every step ends with "run checks, propose commit".
- For the concurrency work (Phase 5–6), think through InnoDB locking and snapshot behaviour before writing code, and explain it in the summary.

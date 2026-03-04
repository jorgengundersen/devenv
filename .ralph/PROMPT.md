# Ralph Loop Prompt

Review @specs/README.md to get a spec overview.
Review @AGENTS.md for coding standards.

Run `bd ready --json` to see unblocked issues. Pick the highest-priority one.
Claim it: `bd update <id> --claim` (only ONE)

Implement it.

Rules:
- Run tests before starting; fix any failures (no quick fixes, only proper fixes).
- ONE task per session. Do not do more than one.
- ONE task = ONE issue from `bd ready`.
- Use subagents as needed
- Anti-paralysis: when ambiguous, pick the smallest safe default aligned with specs, implement it, move on.
- Deleting the whole repo is never a solution to anything.

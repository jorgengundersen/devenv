---
description: Stage changes and create professional commits
agent: build
model: github-copilot/claude-haiku-4.5
subtask: true
---

You are acting inside an OpenCode session with access to bash.

Goal: create git commits for the current repo.

Ignore list (space-separated paths/globs):
$ARGUMENTS

Context:
- Recent commits (match style):
!`git log --oneline -10`
- Current status:
!`git status --porcelain=v1 --untracked-files=all`

Rules (must follow):
- If there are ANY staged changes (git diff --cached not empty):
  - Inspect ONLY the staged diff, write a concise professional commit message, commit, then STOP (do not stage anything else).
  - If any ignored files are staged, unstage those ignored files first (keep their working tree changes), then commit the remaining staged changes and STOP.
- If there are NO staged changes:
  - Inspect the unstaged diff and untracked files.
  - Do NOT stage or commit anything from the ignore list.
  - Stage files and commit with a professional message.
  - If the changes should be logically split into multiple commits, do so (split by files; do not use interactive commands like `git add -p`).
  - After each commit, re-check status and continue until nothing remains to commit except ignored files.

Safety:
- Do not commit likely secrets (e.g. .env, credentials, private keys). If encountered, stop and warn.
- Do not use destructive git commands (no hard reset, no force push).
- Do not amend existing commits.

For inspection (run as needed):
- Staged diff: `git diff --cached`
- Unstaged diff: `git diff`
- Untracked list: `git ls-files --others --exclude-standard`

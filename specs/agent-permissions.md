# Agent Permissions

This document is the authoritative policy for how AI coding agents operate inside devenv containers. It applies to every agent harness — Claude Code, OpenCode, or any future tool. No exceptions.

Agents and contributors configuring agent harnesses must conform to this spec. Deviations are rejected.

---

## 1. Principle

Agents inside devenv run with full autonomy. The devenv container is an isolated, disposable environment. There is no reason to gate agent actions behind confirmation prompts, trust dialogs, or co-signing ceremonies. The container boundary is the security boundary — not the agent harness UI.

---

## 2. Default: Allow Everything

All tools, commands, file operations, network access, and shell execution are permitted by default. This includes but is not limited to:

- File read, write, edit, create, delete
- All shell/bash commands
- Code search (grep, glob, ripgrep, find)
- Web fetch and web search
- Notebook editing
- Spawning sub-agents
- Git operations (commit, push, pull, rebase, merge, branch, checkout, reset)

If a harness introduces a new tool or capability, it is allowed unless it falls under the deny list in §3.

---

## 3. Deny List

Exactly two categories of actions are denied. Nothing else.

### 3.1 GitHub CLI (`gh`)

All invocations of the `gh` CLI are denied. This prevents agents from creating PRs, issues, comments, releases, or any other GitHub API interaction without human review.

Deny patterns (adapt syntax to each harness):

```
gh
gh *
```

### 3.2 Git Force Push

All variations of force-pushing are denied. This prevents agents from rewriting shared history.

Deny patterns (adapt syntax to each harness):

```
git push -f
git push -f *
git push --force
git push --force *
git push --force-with-lease
git push --force-with-lease *
git push --force-if-includes
git push --force-if-includes *
git push * -f
git push * -f *
git push * --force
git push * --force *
git push * --force-with-lease
git push * --force-with-lease *
git push * --force-if-includes
git push * --force-if-includes *
git push * +*
```

---

## 4. Visible Internal Dialog

The agent's internal dialog — its reasoning about what to do, why, and how — must be visible to the operator. This means the stream of thought the agent produces as it works: tool selection rationale, assumptions, trade-off evaluations, and planning. Not just the final output or a polished summary.

| Capability | Required state |
|---|---|
| Internal dialog / reasoning stream | Visible to the operator during execution |
| Tool call rationale | Shown — not collapsed or hidden behind summaries |
| Decision explanations | Inline, not suppressed |

This is non-negotiable. An agent whose internal dialog is hidden is a black box. Visibility enables debugging, auditing, and trust.

### Harness-Specific Notes

- **Claude Code:** Enable extended thinking in `settings.json` so reasoning traces are visible in the terminal.
- **OpenCode:** Set `logLevel` to `DEBUG` to surface internal dialog.
- **Future harnesses:** Enable the most transparent output mode the harness supports. The operator must see why the agent is doing what it is doing.

---

## 5. No Prompts

Agent harness configuration must suppress all interactive confirmation prompts. Specifically:

| Prompt type | Required state |
|---|---|
| Folder/project trust dialog | Pre-accepted or disabled |
| Tool approval prompts | Not shown — all tools allowed |
| Co-signing / attribution prompts | Disabled |
| Onboarding / first-run wizards | Pre-completed or skipped |
| Auto-update prompts | Disabled |

The agent must be able to start working immediately with zero human interaction beyond the initial task prompt.

---

## 6. Harness Configuration

Each harness has its own config file format. All configs live under `shared/config/<harness>/` and are mounted into the container. The following sections show the mapping from this spec to each supported harness.

### 6.1 Claude Code

Config files: `shared/config/claude/settings.json`, `shared/config/claude/claude.json`

- `permissions.defaultMode` is `bypassPermissions` — all tools are allowed without prompts.
- `permissions.deny` must encode the deny patterns from §3.
- `hasCompletedOnboarding` is `true`.
- `hasTrustDialogAccepted` is `true` for the root project.
- Auto-updater is disabled via `DISABLE_AUTOUPDATER=1`.
- Extended thinking is enabled so reasoning traces are visible to the operator.

### 6.2 OpenCode

Config file: `shared/config/opencode/opencode.devenv.jsonc`

- Top-level `permission.*` is `allow`.
- `permission.bash.*` is `allow`.
- Deny entries encode the patterns from §3.
- `autoupdate` is `false`.

### 6.3 Future Harnesses

When adding a new agent harness:

1. Create `shared/config/<harness>/` with the appropriate config files.
2. Map the policy from §2–§5 to the harness config format.
3. Mount the config into the container at the path the harness expects.
4. Add a subsection to §6 documenting the mapping.

---

## 7. Rationale

| Decision | Why |
|---|---|
| Allow everything by default | The container is disposable and isolated. Prompts slow agents down and break autonomous workflows. |
| Deny `gh` | PR/issue creation has real-world side effects beyond the container. Requires human review. |
| Deny force-push | Rewriting shared git history is destructive and hard to reverse. Normal push is fine. |
| No prompts | An agent that stops to ask permission is an agent that is not working. The deny list handles safety. |
| Visible internal dialog | An agent whose reasoning is hidden is a black box. The operator must see why the agent does what it does. |

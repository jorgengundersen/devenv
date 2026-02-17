# Plan: devenv Multi-Project Enhancement

## Prerequisite Reading

Before executing any phase, the agent MUST read and internalize:

1. `specs/coding-standard.md` — authoritative coding standard. All code must conform. No exceptions.
2. `plans/summary.md` — comprehensive conversation summary with all decisions, tradeoffs, and rationale
3. The current source files: `devenv`, `build-devenv`, `install-devenv`, `specs/spec.md`, `README.md`
4. The current Dockerfiles: `Dockerfile.base`, `Dockerfile.devenv`, and all `tools/Dockerfile.*`

## Guiding Principles

All coding standards, safety rules, and quality requirements are defined in `specs/coding-standard.md`. That document is the single source of truth. This section does not duplicate it.

Agents must read and internalize `specs/coding-standard.md` before executing any phase. Key areas covered:

- **Bash:** Script structure, primitives/composition architecture, logging framework (DEBUG/INFO/WARNING/ERROR via `DEVENV_LOG_LEVEL`), stdout/stderr discipline, `getopts` for flag parsing, `readonly` constants, ShellCheck compliance
- **Dockerfiles:** Layer hygiene, pinned base images, stage naming, `COPY --from` discipline, forbidden patterns
- **Security:** Localhost-only SSH, no Docker socket, `devuser` runtime, `:ro` config mounts, `--rm` on all containers
- **General:** No slop, idempotency, fail fast, naming conventions, documentation style

---

## Phase 1: Create New Specification (`specs/spec.md`)

### Goal

Create a comprehensive specification document that reflects ALL decisions from the conversation summary. This becomes the authoritative reference for the project.

### Instructions

1. Remove any archived spec file if present (`rm -f specs/archived_spec.md`)
2. Create a new `specs/spec.md` that covers everything below

### Required Content

The new spec must include these sections (in order):

#### 1.1 Title and Overview
- Project name: "Containerized Development Environment"
- One-paragraph description: A containerized development environment for terminal-based agentic workflows, providing an alternative to Microsoft Dev Containers using pure Docker.

#### 1.2 Motivation
- Carry forward the existing motivation section
- Add: supports concurrent multi-project workflows with persistent containers

#### 1.3 Architecture
- File tree diagram (carry forward, no changes)
- Build system architecture (base → tools → devenv → project)
- Multi-stage build strategy

#### 1.4 Design Principles
- Configuration via Build Arguments (carry forward)
- Persistent container model (NEW): one container per project, background lifecycle, multiple sessions via exec
- Localhost-only SSH by default (NEW)
- Named containers with labels for discoverability (NEW)

#### 1.5 Image Specifications
Carry forward ALL of these from the archived spec:
- Base Image (`Dockerfile.base`) — responsibilities, build args
- Tool Images (`tools/`) — stage naming, build order, dependency table
- Main Development Environment (`Dockerfile.devenv`) — composition strategy
- Project-Specific Extensions (`.devenv/Dockerfile`) — templates

#### 1.6 Installation Methods
Carry forward ALL tool installation methods exactly as they are in archived spec (cargo, go, gh, fnm, node, uv, opencode, nvim, copilot-cli, starship, jq, yq, ripgrep)

#### 1.7 Configuration Mount Points
Carry forward the mount table exactly

#### 1.8 Build System
Carry forward `build-devenv` interface, build context rules, tool image tags, tool isolation strategy

#### 1.9 Runtime Interface (MAJOR UPDATE)

This section gets the most changes. Spec the new `devenv` command:

**Command Structure:**
```
devenv .                      # start/attach to env for current directory
devenv <path>                 # start/attach to env for given path
devenv --port <number> .      # start with explicit SSH port
devenv list                   # list running environments
devenv stop .                 # stop env for current directory
devenv stop <path>            # stop env for given path
devenv stop <name>            # stop env by container name
devenv stop --all             # stop all devenv containers
devenv help                   # show help
```

**Container Lifecycle:**
- When `devenv .` is invoked and NO container exists for the project:
  1. Pre-allocate a free port: `python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'`
  2. Start container in background: `docker run -d --rm --name <container_name> ...`
  3. Main process: `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"`
  4. Log SSH port to user
  5. `docker exec -it <container_name> bash --login`

- When `devenv .` is invoked and a container IS already running:
  1. `docker exec -it <container_name> bash --login`
  2. Log that attaching to existing container

**Container Naming:**
- Format: `devenv-<parent_basename>-<project_basename>`
- Where `parent_basename` = basename of the parent directory of the project path
- Where `project_basename` = basename of the project path
- Example: `/home/user/Repos/local/api` → `devenv-local-api`

**Container Labels:**
- `devenv=true` — identifies all devenv containers
- `devenv.project=<parent_basename>/<project_basename>` — project identifier

**SSH Port Binding:**
- Default: `127.0.0.1:<pre-allocated>:22`
- `DEVENV_SSH_PORT` env var: `127.0.0.1:<value>:22`
- `--port <number>` flag: `127.0.0.1:<number>:22` (overrides env var)
- SSH only enabled when `~/.ssh/authorized_keys` exists

**`devenv list` output format:**
```
NAME                    SSH                     STATUS    STARTED
devenv-local-api        127.0.0.1:54321         running   2h ago
devenv-repos-frontend   127.0.0.1:54987         running   15m ago
```

**`devenv stop` behavior:**
- `devenv stop .` / `devenv stop <path>` — resolves path to container name, runs `docker stop`
- `devenv stop <name>` — stops by container name directly
- `devenv stop --all` — stops all containers with label `devenv=true`

**Docker Run Command Structure (updated):**
```bash
docker run -d --rm \
  --name devenv-<parent>-<project> \
  --user devuser:devuser \
  --workdir /workspaces/<project_name> \
  --label devenv=true \
  --label devenv.project=<parent>/<project> \
  -v "<project_path>:/workspaces/<project_name>:rw" \
  -v "$HOME/.bashrc:/home/devuser/.bashrc:ro" \
  ... (all config mounts, conditional) \
  -v "$SSH_AUTH_SOCK:/ssh-agent:ro" \
  -v "$HOME/.ssh/authorized_keys:/home/devuser/.ssh/authorized_keys:ro" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  -e TERM \
  -p "127.0.0.1:<port>:22" \
  --network bridge \
  <image_name> \
  bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
```

Then: `docker exec -it devenv-<parent>-<project> bash --login`

#### 1.10 Image Management
Carry forward tagging strategy and cleanup practices. Update project image tag format to `devenv-project-<parent>-<basename>:latest`.

#### 1.11 Environment Variables
Carry forward PATH and environment variable conventions

#### 1.12 Installation Scripts
Carry forward `install-devenv` section

#### 1.13 Error Handling
Carry forward error handling conventions (set -euo pipefail, validation, logging, main() structure)

#### 1.14 Security
Updated section:
- SSH binds to `127.0.0.1` by default
- No Docker socket mounting
- Containers run as `devuser`
- Read-only config mounts
- `authorized_keys` enables SSH access

#### 1.15 Target Audience
Carry forward

### Verification

- The new spec must be self-contained — a developer unfamiliar with the project should be able to understand the entire system by reading only `specs/spec.md`
- Every decision from `plans/summary.md` must be reflected in the spec
- No information from the prior archived spec should be lost unless it contradicts a decision from the summary

---

## Phase 2: Create Research Document (`plans/research.md`)

### Goal

Analyze the gap between the new specification (Phase 1 output) and the current implementation. Produce a detailed mapping that an implementation agent can use to execute changes precisely.

### Instructions

Read the following files completely and produce analysis:

1. New `specs/spec.md` (Phase 1 output)
2. `devenv` (228 lines)
3. `build-devenv` (219 lines)
4. `install-devenv` (144 lines)
5. `README.md` (213 lines)

### Required Content

#### 2.1 Gap Analysis

For each section of the new spec, compare with current implementation and categorize:

| Category | Meaning |
|----------|---------|
| NO CHANGE | Spec matches current implementation exactly |
| UPDATE | Code exists but needs modification |
| NEW | Feature does not exist, must be created |
| REMOVE | Code exists but is no longer needed |

#### 2.2 File-Level Change Map

For each file that needs changes, list:
- Filename
- Current line count
- Sections that change (with line numbers)
- Nature of change (update/new/remove)
- Dependencies on other changes

Format:
```
### devenv (228 lines)

- Lines 16-44: `usage()` — UPDATE: add list, stop, --port to help text
- Lines 95-100: `run_devenv()` — UPDATE: container lifecycle change
- Lines 160-170: SSH port logic — UPDATE: localhost binding, pre-allocate
- NEW: `cmd_list()` function — list running containers
- NEW: `cmd_stop()` function — stop containers
- NEW: `derive_container_name()` function — parent-basename derivation
- NEW: `derive_project_identity()` function — parent/basename for labels
- Lines 180-195: `main()` — UPDATE: route new commands
```

#### 2.3 Function-Level Change Detail

For each function that changes, document:
- Current behavior (what it does now)
- Target behavior (what spec says it should do)
- Specific lines that change
- New functions needed
- Functions to remove

#### 2.4 Tradeoffs and Edge Cases to Handle

List all edge cases the implementation must handle:
- Container died between `docker ps` check and `docker exec`
- Python3 not available for port pre-allocation (fallback?)
- Container name already in use but not a devenv container
- Project path with special characters in basename
- `docker exec` session exits but container stays running (by design)
- Multiple calls to `devenv .` racing to start the same container
- `devenv stop .` when no container is running

#### 2.5 External Dependencies

List any new dependencies:
- `python3` for port pre-allocation (already in most Linux systems)
- Any new tools needed inside the container

#### 2.6 Files That Don't Change

Explicitly list files that require NO changes:
- `build-devenv` — explain why
- `install-devenv` — explain why  
- All Dockerfiles — explain why
- All templates — explain why

### Verification

- Every section of the new spec must map to either a "NO CHANGE" or a specific code change
- No ambiguity — an implementation agent reading this doc should know exactly what to do

---

## Phase 3: Create Implementation Plan

### Goal

Based on the research document, produce an ordered list of implementation tasks with enough detail that a coding agent can execute each task without creative problem solving.

### Instructions

Read `plans/research.md` (Phase 2 output) and produce a task list (`plans/implementation_plan.md`).

### Required Content

#### 3.1 Task List

Each task must include:
- **Task ID:** Sequential number (T1, T2, ...)
- **Title:** Short descriptive title
- **File:** Which file(s) to modify
- **Dependencies:** Which tasks must complete first
- **Description:** What to do (1-3 sentences)
- **Before:** The exact current code (with line numbers) or "new function"
- **After:** The exact target code or pseudocode precise enough to implement without ambiguity
- **Verification:** How to verify this specific task is correct

Order tasks to minimize conflicts and enable incremental verification.

Suggested task ordering:

1. **T1: Remove archived spec** — `rm -f specs/archived_spec.md` (no code)
2. **T2: Create new specs/spec.md** — Write the complete spec per Phase 1 instructions
3. **T3: Add `derive_container_name()` to `devenv`** — New helper function
4. **T4: Add `derive_project_identity()` to `devenv`** — New helper function  
5. **T5: Add `allocate_ssh_port()` to `devenv`** — Port pre-allocation function
6. **T6: Refactor `run_devenv()` to new lifecycle** — Background + exec model
7. **T7: Add `cmd_list()` to `devenv`** — New list command
8. **T8: Add `cmd_stop()` to `devenv`** — New stop command
9. **T9: Update `usage()` in `devenv`** — Reflect new commands
10. **T10: Update `main()` in `devenv`** — Route new commands, parse `--port`
11. **T11: Update image naming in `get_image_name()` and `ensure_project_image()`** — Parent-basename format
12. **T12: Update `build-devenv` project naming** — Match new image naming convention
13. **T13: Update `README.md`** — Reflect new commands, lifecycle, SSH defaults
14. **T14: End-to-end verification** — Full test plan

#### 3.2 Verification Plan

A comprehensive verification plan that confirms ALL changes work correctly:

**Unit-level checks (per task):**
- Each task's verification as specified above

**Integration checks:**
```bash
# 1. Basic start/attach cycle
tmp_dir=$(mktemp -d)
cd "$tmp_dir" && mkdir -p test-project
devenv "$tmp_dir/test-project"
# Verify: container runs, shell opens, SSH port printed

# 2. Second session attaches
# In another terminal:
devenv "$tmp_dir/test-project"
# Verify: same container, no new container started

# 3. List shows running environments
devenv list
# Verify: table with name, SSH port, status, started time

# 4. SSH access works (if authorized_keys present)
ssh -p <printed_port> devuser@localhost
# Verify: connects to the same container

# 5. Stop by path
devenv stop "$tmp_dir/test-project"
# Verify: container stops, next `devenv list` shows nothing

# 6. Concurrent projects
devenv "$tmp_dir/test-project-a"
# In another terminal:
devenv "$tmp_dir/test-project-b"
devenv list
# Verify: two containers, different SSH ports

# 7. Stop all
devenv stop --all
# Verify: all containers stopped

# 8. --port flag
devenv --port 3333 "$tmp_dir/test-project"
# Verify: SSH bound to 127.0.0.1:3333

# 9. Edge case: stop when nothing running
devenv stop .
# Verify: graceful message, no error
```

**Regression checks:**
- Build system (`build-devenv`) still works unchanged
- Project images still build correctly
- Volume mounts still work
- SSH agent forwarding still works

---

## Phase 4: Implementation Instructions

### Goal

Provide precise instructions for a coding agent (with subagents) to implement the plan from Phase 3.

### Instructions for the Implementation Agent

#### 4.1 Setup

1. Read ALL of these files before writing any code:
  - `specs/coding-standard.md` (authoritative coding standard — read first)
  - `plans/summary.md`
  - `specs/spec.md` (the new one from Phase 1)
  - `plans/research.md` (from Phase 2)
  - `plans/implementation_plan.md` (from Phase 3)

2. Verify the current state:
   ```bash
   cd ~/.config/devenv
   cat devenv | wc -l    # should be 228
   docker images | grep devenv  # verify images exist
   ```

#### 4.2 Execution Strategy

- Execute tasks in order (T1 → T14)
- After each task, verify it before moving to the next
- Use subagents for parallel independent tasks where possible (e.g., T3, T4, T5 can be developed in parallel)
- After all code changes, run the full verification plan from Phase 3
- Do NOT modify any Dockerfiles unless the spec explicitly requires it
- Do NOT modify `build-devenv` unless the spec explicitly requires it (it may need image naming updates)
- Do NOT modify `install-devenv`

#### 4.3 Code Standards

All coding standards are defined in `specs/coding-standard.md`. Read it in full before writing any code.

Key requirements that directly affect implementation tasks:

- **Script structure:** Constants → Logging → Primitives → Commands → `main()` → source guard (§1.2)
- **Primitives never exit.** They return non-zero on failure. Only commands and `die()` may exit (§1.3, §1.4)
- **Logging:** Use `log_debug`, `log_info`, `log_warning`, `log_error`, `die`. Not `echo`, not bare `log()` (§1.5)
- **Output:** Program data to stdout, all diagnostics to stderr (§1.6)
- **Parsing:** Subcommand dispatch via `case`, flags via `getopts` (§1.7)
- **Constants:** `readonly UPPER_SNAKE_CASE` (§1.8)
- **ShellCheck:** Zero warnings. Mandatory. (§1.10)

When modifying existing functions:
- Preserve the function signature where possible
- Add parameters rather than changing meaning of existing ones
- The existing code predates this standard — refactor it to conform, do not match the old style

#### 4.4 Safety Checklist

All security rules are defined in `specs/coding-standard.md` §3. Before marking implementation complete, verify every rule in that section is satisfied, plus these implementation-specific checks:

- [ ] Port pre-allocation uses `127.0.0.1` in the socket bind
- [ ] `devenv stop` cannot stop non-devenv containers (filter by label)
- [ ] Container names are sanitized (no special characters that break Docker)
- [ ] Error messages guide the user to the fix
- [ ] All scripts pass `shellcheck` with zero warnings
- [ ] Logging uses the framework from `specs/coding-standard.md` §1.5 (not ad-hoc `echo` or `log()`)

#### 4.5 Verification Execution

After completing all implementation tasks:

1. Run each integration check from the Phase 3 verification plan
2. Record the actual output of each check
3. Note any failures and fix them before proceeding
4. Run the regression checks
5. Produce a brief verification report: which checks passed, which needed fixes, what was fixed

#### 4.6 Deliverables

The implementation is complete when:
1. Archived spec removed (no stale references)
2. `specs/spec.md` is the new comprehensive spec
3. `plans/research.md` documents the gap analysis
4. `plans/implementation_plan.md` lists all tasks in order with details
5. `devenv` script implements the new lifecycle, all commands, port pre-allocation
6. `README.md` reflects the new commands and behavior
7. All verification checks pass
8. All bash scripts pass `shellcheck` with zero warnings (not optional)
9. All code conforms to `specs/coding-standard.md`

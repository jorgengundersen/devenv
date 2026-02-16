# Research Document: Gap Analysis & Implementation Guide

This document analyzes the gap between the new specification (`specs/spec.md`) and the current implementation. It provides a detailed mapping that an implementation agent can use to execute changes precisely.

Source files analyzed:

| File | Lines | Role |
|------|-------|------|
| `devenv` | 228 | Runtime launcher (primary change target) |
| `build-devenv` | 219 | Build management |
| `install-devenv` | 144 | Symlink installer |
| `README.md` | 213 | User documentation |
| `specs/spec.md` | 660 | New specification (Phase 1 output) |
| `specs/coding-standard.md` | 448 | Authoritative coding standard |

---

## 2.1 Gap Analysis

Each section of the new specification is compared against the current implementation and categorized.

### 2.1.1 Architecture (spec §Architecture)

| Spec Element | Category | Notes |
|---|---|---|
| File tree layout | NO CHANGE | Current workspace matches the spec file tree exactly. |
| Build pipeline (base → tools → devenv → project) | NO CHANGE | `build-devenv` already implements this layered pipeline. |

### 2.1.2 Design Principles (spec §Design Principles)

| Spec Element | Category | Notes |
|---|---|---|
| Configuration via Build Arguments | NO CHANGE | Dockerfiles already use build args. |
| Persistent container model | **NEW** | Current: `docker run -it --rm` (foreground, ephemeral). Spec: `docker run -d --rm` (background, persistent) + `docker exec -it` (attach). Entire container lifecycle must change. |
| Localhost-only SSH | **UPDATE** | Current (`devenv` line 172): `-p "${ssh_port}:22"` binds to `0.0.0.0`. Spec: `127.0.0.1:<port>:22`. |
| Named containers with labels | **NEW** | Current: no `--name` or `--label` flags on `docker run`. Spec: `--name devenv-<parent>-<basename>`, `--label devenv=true`, `--label devenv.project=<parent>/<basename>`. |

### 2.1.3 Image Specifications (spec §Image Specifications)

| Spec Element | Category | Notes |
|---|---|---|
| Base image (`Dockerfile.base`) | NO CHANGE | Spec carries forward existing base image definition. |
| Tool images (`tools/Dockerfile.*`) | NO CHANGE | Spec carries forward existing tool build system. |
| Tool stage naming (`tool_<name>`) | NO CHANGE | Already implemented in tool Dockerfiles. |
| Tool build order & dependencies | NO CHANGE | Already documented and implemented. |
| Main dev environment (`Dockerfile.devenv`) | NO CHANGE | Composition strategy unchanged. |
| Project extensions (`.devenv/Dockerfile`) | NO CHANGE | Template system unchanged. |
| Project image naming | **UPDATE** | Current: `devenv-project-<basename>:latest`. Spec: `devenv-project-<parent>-<basename>:latest`. Affects `devenv` (`get_image_name()`, `ensure_project_image()`) and `build-devenv` (`build_project()`). |

### 2.1.4 Installation Methods (spec §Installation Methods)

| Spec Element | Category | Notes |
|---|---|---|
| All tool installation methods (cargo, go, gh, fnm, node, uv, jq, ripgrep, nvim, opencode, copilot-cli, starship, yq) | NO CHANGE | Spec carries forward all methods verbatim. |

### 2.1.5 Configuration Mount Points (spec §Configuration Mount Points)

| Spec Element | Category | Notes |
|---|---|---|
| Mount table (bash, nvim, starship, gh, opencode) | NO CHANGE | Current `devenv` lines 119–146 implement exactly these mounts. |

### 2.1.6 Build System (spec §Build System)

| Spec Element | Category | Notes |
|---|---|---|
| `build-devenv` interface (`--stage`, `--tool`, `--project`) | NO CHANGE | Current interface matches spec. |
| Build context always `~/.config/devenv` | NO CHANGE | Already implemented. |
| Tool image tags (`devenv-tool-<name>:latest`) | NO CHANGE | Already implemented in `build_tool()`. |
| Tool isolation strategy | NO CHANGE | Already implemented. |

### 2.1.7 Runtime Interface (spec §Runtime Interface)

| Spec Element | Category | Notes |
|---|---|---|
| `devenv .` / `devenv <path>` — start/attach | **UPDATE** | Current: starts foreground container. Spec: start background container if not running, then attach via `docker exec -it`. |
| `devenv --port <number> .` | **NEW** | No `--port` flag exists. Spec: CLI flag to override SSH port. |
| `devenv list` | **NEW** | Command does not exist. Spec: list running devenv containers with name, SSH, status, started. |
| `devenv stop .` / `devenv stop <path>` | **NEW** | Command does not exist. Spec: resolve path → container name → `docker stop`. |
| `devenv stop <name>` | **NEW** | Command does not exist. Spec: stop by container name directly. |
| `devenv stop --all` | **NEW** | Command does not exist. Spec: stop all containers with label `devenv=true`. |
| `devenv help` | **UPDATE** | Help text (lines 16–42) must be updated to show new commands and flags. |
| Container naming (`devenv-<parent>-<basename>`) | **NEW** | No container naming in current code. |
| Container labels (`devenv=true`, `devenv.project=...`) | **NEW** | No labels in current code. |
| SSH port pre-allocation via `python3` | **NEW** | Current (line 171): hardcoded `DEVENV_SSH_PORT:-2222`. Spec: `python3 -c 'import socket; ...'` with fallback to env var and `--port` flag. |
| SSH port priority (flag > env > auto) | **NEW** | Current: only env var. Spec: three-tier priority. |
| SSH only when `authorized_keys` exists | NO CHANGE | Current (lines 154–158) already checks `~/.ssh/authorized_keys` before enabling SSH. |
| `docker run` command flags (`-d`, `--name`, `--label`) | **NEW** | Current (lines 178–186): uses `-it`, no `--name`, no `--label`, no `-d`. |
| Container main process `sleep infinity` | **NEW** | Current (line 168–173): main process is `bash --login` or `bash -lc "sudo /usr/sbin/sshd; exec bash --login"`. Spec: `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"`. |
| `docker exec -it` for shell attachment | **NEW** | Not used in current code. |

### 2.1.8 Image Management (spec §Image Management)

| Spec Element | Category | Notes |
|---|---|---|
| Tagging strategy (version + latest) | NO CHANGE | Already implemented in `build-devenv`. |
| Project image tag format | **UPDATE** | Current: `devenv-project-<basename>`. Spec: `devenv-project-<parent>-<basename>`. |
| Cleanup practices | NO CHANGE | Documentation only, no script changes. |

### 2.1.9 Environment Variables (spec §Environment Variables)

| Spec Element | Category | Notes |
|---|---|---|
| PATH via mounted `~/.bashrc` | NO CHANGE | Current behavior. |
| `TERM` env passthrough | NO CHANGE | Current (line 165): already passes `TERM`. |
| `SSH_AUTH_SOCK` passthrough | NO CHANGE | Current (lines 149–151, 162–163): already handles SSH agent. |

### 2.1.10 Installation Scripts (spec §Installation Scripts)

| Spec Element | Category | Notes |
|---|---|---|
| `install-devenv` creates symlinks | NO CHANGE | Already implemented. |
| Scripts have no `.sh` extension | NO CHANGE | Already the case. |

### 2.1.11 Error Handling (spec §Error Handling)

| Spec Element | Category | Notes |
|---|---|---|
| `set -euo pipefail` | NO CHANGE | All scripts already have this. |
| Validation of inputs | NO CHANGE (logic), **UPDATE** (style) | Logic exists but must be refactored to use `die()` instead of `error()`. |
| `main()` structure | NO CHANGE (concept), **UPDATE** (implementation) | Exists but needs subcommand dispatch and source guard. |

### 2.1.12 Security (spec §Security)

| Spec Element | Category | Notes |
|---|---|---|
| SSH binds to `127.0.0.1` | **UPDATE** | Current: binds to `0.0.0.0` (line 172). |
| No Docker socket mounting | NO CHANGE | Not mounted. |
| Containers run as `devuser` | NO CHANGE | Current (line 179): `--user devuser:devuser`. |
| Read-only config mounts | NO CHANGE | All `:ro` (lines 121–146). |
| `authorized_keys` enables SSH | NO CHANGE | Conditional check exists (lines 154–158). |
| `--rm` on all containers | NO CHANGE | Already present (line 178). |

### 2.1.13 Coding Standard Conformance

| Standard Requirement | Category | Current State |
|---|---|---|
| Script structure (Constants → Logging → Primitives → Commands → main → source guard) | **UPDATE** | All three scripts use a flat structure without the required ordering. |
| Logging framework (`log_debug`, `log_info`, `log_warning`, `log_error`, `die`) | **UPDATE** | Current: `log()` and `error()` (simple echo-based). Must be replaced with leveled logging framework. |
| `DEVENV_LOG_LEVEL` env var | **NEW** | Does not exist. Default `WARNING`. |
| `printf` instead of `echo` for return values | **UPDATE** | Current: `echo` used in `get_image_name()` (lines 63, 65). Must use `printf '%s'`. |
| `readonly` for constants | **UPDATE** | Current (lines 12–13): `DEVENV_HOME` and `IMAGE_PREFIX` not `readonly`. |
| Source guard (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`) | **NEW** | Current: bare `main "$@"` at end of all scripts. |
| Subcommand dispatch via `case` | **UPDATE** | Current `main()` uses if/elif chain. Spec requires `case` dispatch. |
| `getopts` for flag parsing | **NEW** | Current: no flags parsed. Spec: `--port` flag via `getopts`. |
| Primitives never call `exit` | **UPDATE** | Current `validate_docker()` calls `error()` which calls `exit`. Must return non-zero instead, with caller deciding action. |
| Parameter expansion over external commands | **UPDATE** | Current: `basename "$(cd "${project_path}" && pwd)"` should use `"${path##*/}"`. |
| Function documentation (one-line comment above each) | **UPDATE** | Some functions have comments, but style is inconsistent. |
| ShellCheck compliance | **UPDATE** | Untested; likely needs minor fixes after refactoring. |

---

## 2.2 File-Level Change Map

### `devenv` (228 lines) — MAJOR REWRITE

This file requires the most extensive changes. The entire script must be restructured to conform to the coding standard and implement the new persistent container model.

```
Lines 1-5:     Header                    — UPDATE: no functional change, style preserved
Lines 7-9:     log(), error()            — REMOVE: replace with leveled logging framework
Lines 11-13:   Configuration             — UPDATE: add readonly, keep values
Lines 15-42:   usage()                   — UPDATE: rewrite help text for new commands/flags
Lines 44-53:   validate_docker()         — UPDATE: refactor to primitive (no exit, return non-zero)
Lines 55-67:   get_image_name()          — UPDATE: change echo→printf, add parent-basename naming
Lines 69-92:   ensure_project_image()    — UPDATE: parent-basename image naming
Lines 94-187:  run_devenv()              — REMOVE: replaced by cmd_start(), start_container(), attach_container()
Lines 189-225: main()                    — UPDATE: case-based dispatch, getopts for --port
Lines 227-228: main "$@"                 — UPDATE: wrap in source guard

NEW functions to add:
  - Logging framework: _log(), log_debug(), log_info(), log_warning(), log_error(), die()
  - resolve_project_path()       — extract path resolution from main()
  - derive_container_name()      — path → "devenv-<parent>-<basename>"
  - derive_project_label()       — path → "<parent>/<basename>"
  - allocate_port()              — pre-allocate free TCP port
  - is_container_running()       — check if named container is running
  - build_mounts()               — extract mount logic from run_devenv()
  - build_env_vars()             — extract env var logic from run_devenv()
  - start_container()            — docker run -d --rm (replaces docker run -it --rm)
  - attach_container()           — docker exec -it <name> bash --login
  - cmd_start()                  — orchestrate start/attach (replaces run_devenv)
  - cmd_list()                   — list running devenv containers
  - cmd_stop()                   — stop containers by path/name/--all

REMOVE:
  - log()                        — replaced by logging framework
  - error()                      — replaced by die()
  - run_devenv()                 — replaced by cmd_start() composing primitives

Dependencies: None (self-contained script)
```

### `build-devenv` (219 lines) — MODERATE UPDATE

```
Lines 7-9:     log(), error()            — REMOVE: replace with leveled logging framework
Lines 11-13:   Configuration             — UPDATE: add readonly
Lines 40-53:   validate_docker()         — UPDATE: refactor to primitive (no exit)
Lines 126-154: build_project()           — UPDATE: project image naming to parent-basename format
Lines 156-219: main()                    — UPDATE: source guard at bottom

NEW:
  - Logging framework (same as devenv)
  - Source guard

Dependencies: Must be updated AFTER devenv to use same naming convention
```

### `install-devenv` (144 lines) — MINOR UPDATE (coding standard only)

```
Lines 7-9:     log(), error()            — REMOVE: replace with leveled logging framework
Lines 11-13:   Configuration             — UPDATE: add readonly
Lines 143-144: main "$@"                 — UPDATE: wrap in source guard

NEW:
  - Logging framework (same as devenv)
  - Source guard

Dependencies: None
```

### `README.md` (213 lines) — MODERATE UPDATE

```
Lines 96-105:  Commands > devenv section — UPDATE: add list, stop, --port documentation
Lines 115-130: Security section          — UPDATE: add localhost-only SSH, persistent containers
General:       Add persistent container model explanation
General:       Add SSH port behavior documentation

Dependencies: Must be updated AFTER devenv changes are finalized
```

---

## 2.3 Function-Level Change Detail

### `devenv` Script Functions

#### `log()` (line 8) — REMOVE

- **Current behavior:** `echo "[timestamp] $*" >&2`
- **Target:** Remove entirely. Replace all call sites with `log_info`, `log_debug`, `log_warning` as appropriate.
- **Replacement mapping for current call sites:**
  - Line 80: `log "Project image not found, building..."` → `log_info "Project image not found, building..."`
  - Line 84: `log "build-devenv not found in PATH..."` → `log_warning "build-devenv not found in PATH..."`
  - Line 102: `log "Starting development environment..."` → `log_info "Starting development environment..."`
  - Line 103: `log "Using image: ..."` → `log_debug "Using image: ${image_name}"`
  - Line 177: `log "Launching container..."` → `log_info "Launching container..."`
  - Line 197: `log "Starting devenv..."` → `log_debug "Starting devenv..."`
  - Line 224: `log "Development environment exited"` → `log_debug "Development environment exited"`

#### `error()` (line 9) — REMOVE

- **Current behavior:** Calls `log "ERROR: $*"` then `exit 1`.
- **Target:** Replace with `die()` from logging framework. All call sites become `die "message"`.
- **Replacement mapping:**
  - Line 47: `error "Docker is not installed..."` → must move to caller; `validate_docker` returns non-zero
  - Line 51: `error "Docker daemon is not running"` → must move to caller
  - Line 108: `error "Devenv image not found..."` → `die "Devenv image not found..."`
  - Line 219: `error "Project path does not exist..."` → `die "Project path does not exist..."`

#### `usage()` (lines 16–42) — UPDATE

- **Current behavior:** Shows help for `devenv [help | . | <path>]`.
- **Target behavior:** Show help for all commands: `.`, `<path>`, `--port`, `list`, `stop`, `stop --all`, `help`.
- **Specific changes:**
  - Add `list`, `stop`, `stop --all` to Commands section
  - Add `--port <number>` to Options section
  - Update examples to include new commands
  - Remove "Image Selection" section (implementation detail, not user-facing help)
  - Add "Container Lifecycle" brief explanation

#### `validate_docker()` (lines 44–53) — UPDATE to primitive

- **Current behavior:** Calls `error()` (which exits) on failure.
- **Target behavior:** Return non-zero on failure, do not exit. Caller decides action.
- **Specific changes:**
  - Line 47: Replace `error "..."` with `log_error "Docker is not installed or not in PATH"; return 1`
  - Line 51: Replace `error "..."` with `log_error "Docker daemon is not running"; return 1`
  - Caller (`cmd_start`, etc.) must check return value: `validate_docker || die "Docker is not available. Install Docker and try again."`

#### `get_image_name()` (lines 55–67) — UPDATE

- **Current behavior:** Returns `devenv-project-<basename>:latest` or `devenv:latest`. Uses `echo`.
- **Target behavior:** Returns `devenv-project-<parent>-<basename>:latest` or `devenv:latest`. Uses `printf '%s'`.
- **Specific changes:**
  - Line 62: Extract parent basename: `local parent_name; parent_name="${project_path%/*}"; parent_name="${parent_name##*/}"`
  - Line 63: `echo "${IMAGE_PREFIX}-project-${project_name}:latest"` → `printf '%s' "${IMAGE_PREFIX}-project-${parent_name}-${project_name}:latest"`
  - Line 65: `echo "${IMAGE_PREFIX}:latest"` → `printf '%s' "${IMAGE_PREFIX}:latest"`
  - Line 62: Replace `basename "$(cd ...)"` with parameter expansion `"${project_path##*/}"`

#### `ensure_project_image()` (lines 69–92) — UPDATE

- **Current behavior:** Builds `devenv-project-<basename>:latest`.
- **Target behavior:** Builds `devenv-project-<parent>-<basename>:latest`.
- **Specific changes:**
  - Line 76: Extract parent basename same as `get_image_name()`
  - Line 77: Update image name to include parent: `"${IMAGE_PREFIX}-project-${parent_name}-${project_name}:latest"`
  - Line 80: Replace `log` with `log_info`
  - Line 84: Replace `log` with `log_warning`
  - Replace `basename` with parameter expansion

#### `run_devenv()` (lines 94–187) — REMOVE, replaced by decomposed functions

- **Current behavior:** Monolithic function that builds mounts, env vars, ports, and runs `docker run -it --rm`.
- **Target:** Remove entirely. Replace with composition of primitives and a `cmd_start()` command function.

**Decomposition into new functions:**

##### NEW: `resolve_project_path()` — Primitive

- **Purpose:** Convert a path argument (`.`, relative, absolute) to a canonical absolute path.
- **Extracted from:** `main()` lines 202–220.
- **Behavior:**
  - Input: raw path string
  - If `.`, use `$PWD`
  - If relative, prepend `$PWD/`
  - Resolve via `cd ... && pwd`
  - Return via `printf '%s'`
  - Return 1 if path does not exist (no exit)

##### NEW: `derive_container_name()` — Primitive

- **Purpose:** Derive deterministic container name from project path.
- **Behavior:**
  - Input: canonical project path
  - Extract parent basename: `"${path%/*}"` then `"${parent##*/}"`
  - Extract project basename: `"${path##*/}"`
  - Output: `printf '%s' "devenv-${parent_name}-${project_name}"`
  - Sanitize: replace characters invalid in Docker container names (only `[a-zA-Z0-9_.-]` allowed)

##### NEW: `derive_project_label()` — Primitive

- **Purpose:** Derive project label value from project path.
- **Behavior:**
  - Input: canonical project path
  - Output: `printf '%s' "${parent_name}/${project_name}"`

##### NEW: `allocate_port()` — Primitive

- **Purpose:** Pre-allocate a free TCP port bound to `127.0.0.1`.
- **Behavior:**
  - Use `python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'`
  - Return port number via `printf '%s'`
  - Return 1 if `python3` unavailable

##### NEW: `is_container_running()` — Primitive

- **Purpose:** Check if a named Docker container is currently running.
- **Behavior:**
  - Input: container name
  - `docker ps --filter "name=^/${name}$" --format '{{.Names}}' | grep -q .`
  - Return 0 if running, 1 if not

##### NEW: `build_mounts()` — Primitive

- **Purpose:** Build the array of `-v` mount flags for `docker run`.
- **Extracted from:** `run_devenv()` lines 114–157.
- **Behavior:**
  - Input: project path, project name
  - Construct mounts array with project dir, config mounts (conditional), SSH agent, authorized_keys
  - Output array via a nameref or global associative approach
  - Note: Since bash cannot return arrays from subshells, this must use a nameref parameter (`local -n`) or set a global array variable.

##### NEW: `build_env_vars()` — Primitive

- **Purpose:** Build the array of `-e` environment flags for `docker run`.
- **Extracted from:** `run_devenv()` lines 160–165.
- **Behavior:**
  - Construct env vars array with `SSH_AUTH_SOCK` (if available), `TERM`
  - Same array return strategy as `build_mounts()`

##### NEW: `start_container()` — Primitive

- **Purpose:** Start a new background container with `docker run -d --rm`.
- **Behavior:**
  - Input: project path, container name, image name, SSH port
  - Build mounts and env vars
  - Execute `docker run -d --rm --name ... --label ... -p 127.0.0.1:<port>:22 ... bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"`
  - SSH port and sshd are conditional on `~/.ssh/authorized_keys` existing
  - Return 0 on success, non-zero on failure

##### NEW: `attach_container()` — Primitive

- **Purpose:** Attach an interactive session to a running container.
- **Behavior:**
  - Input: container name, project name (for workdir)
  - Execute `docker exec -it --workdir "/workspaces/${project_name}" "${container_name}" bash --login`

##### NEW: `cmd_start()` — Command

- **Purpose:** Start or attach to a development environment (replaces `run_devenv()` + path resolution from `main()`).
- **Behavior:**
  1. Parse `--port` flag via `getopts` (or long-opt handling)
  2. Resolve project path via `resolve_project_path()`
  3. Derive container name via `derive_container_name()`
  4. If `is_container_running()`: log info "Attaching to ..."; `attach_container()`
  5. Else: determine SSH port (flag > env > allocate), ensure image exists, `start_container()`, log SSH port, `attach_container()`

##### NEW: `cmd_list()` — Command

- **Purpose:** List running devenv containers with name, SSH port, status, and start time.
- **Behavior:**
  - Query: `docker ps --filter label=devenv=true --format '...'`
  - Extract SSH port from port mappings
  - Format as table: `NAME  SSH  STATUS  STARTED`
  - Output to stdout (pipeable)

##### NEW: `cmd_stop()` — Command

- **Purpose:** Stop devenv containers by path, name, or `--all`.
- **Behavior:**
  - `--all` flag: `docker stop $(docker ps -q --filter label=devenv=true)`
  - Path argument (`.`, `<path>`): resolve to container name, then `docker stop <name>`
  - Name argument: `docker stop <name>` directly
  - Distinguish path vs name: if argument contains `/` or is `.`, treat as path; otherwise treat as container name
  - Graceful handling when no container is running

#### `main()` (lines 189–225) — UPDATE

- **Current behavior:** Checks for help, then resolves path and calls `run_devenv()`.
- **Target behavior:** Subcommand dispatch via `case` statement. Parse `--port` flag.
- **Specific changes:**
  - Replace if/elif chain with `case` dispatch:
    ```
    case "${command}" in
        list)            cmd_list "$@" ;;
        stop)            cmd_stop "$@" ;;
        help|--help|-h)  usage ;;
        *)               cmd_start "${command}" "$@" ;;
    esac
    ```
  - Move path resolution logic into `resolve_project_path()` and `cmd_start()`
  - Add `validate_docker` call at top of `main()`, not inside individual commands (or inside each command)
  - Remove direct `run_devenv` call

#### Line 227–228: `main "$@"` — UPDATE

- **Current:** `main "$@"` (bare call)
- **Target:** Source guard: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi`

---

### `build-devenv` Script Functions

#### `log()` (line 8) — REMOVE

- Same replacement as `devenv`: leveled logging framework.

#### `error()` (line 9) — REMOVE

- Same replacement as `devenv`: `die()`.

#### Constants (lines 12–13) — UPDATE

- Add `readonly` keyword to `DEVENV_HOME` and `IMAGE_PREFIX`.

#### `validate_docker()` (lines 40–53) — UPDATE to primitive

- Same refactoring as `devenv`: return non-zero instead of calling `error()`.

#### `build_project()` (lines 126–154) — UPDATE

- **Current behavior (line ~145):** Tags as `devenv-project-${project_name}:latest` where `project_name=$(basename ...)`.
- **Target behavior:** Tags as `devenv-project-${parent_name}-${project_name}:latest`.
- **Specific changes:**
  - After resolving `project_name`, also extract parent name: `local parent_name; parent_name=$(basename "$(dirname "$(cd "${project_path}" && pwd)")")` or use parameter expansion.
  - Update the tag on line ~148: `"${IMAGE_PREFIX}-project-${parent_name}-${project_name}:latest"`
  - Replace `basename` calls with parameter expansion where possible.
  - Replace `log` calls with `log_info`/`log_debug`.

#### `main()` (lines 156–219) — UPDATE

- Add source guard at end of file.
- Replace `log` calls with appropriate log level.
- Replace `error` calls with `die`.

---

### `install-devenv` Script Functions

#### `log()` (line 8) — REMOVE

- Same replacement: leveled logging framework.

#### `error()` (line 9) — REMOVE

- Same replacement: `die()`.

#### Constants (lines 12–13) — UPDATE

- Add `readonly`.

#### `main()` (lines 120–141) — UPDATE

- Add source guard at end of file.
- Replace `log`/`error` with framework equivalents.

---

## 2.4 Tradeoffs and Edge Cases to Handle

### Edge Case 1: Container died between `docker ps` check and `docker exec`

- **Scenario:** `is_container_running()` returns true, but container exits before `docker exec` runs (TOCTOU race).
- **Handling:** `docker exec` will fail with a non-zero exit code and error message. `cmd_start()` should catch this failure and either retry by starting a new container or report the error clearly.
- **Recommendation:** Let `docker exec` fail naturally; the error message from Docker is sufficient. The user can re-run `devenv .`.

### Edge Case 2: `python3` not available for port pre-allocation

- **Scenario:** Host system does not have `python3` installed.
- **Handling:** `allocate_port()` should detect this and fall back to `DEVENV_SSH_PORT` env var. If neither is available, `die` with an actionable message: "Install python3 or set DEVENV_SSH_PORT".
- **Fallback chain:** `--port` flag → `DEVENV_SSH_PORT` env var → `python3` auto-allocate → `die`.
- **Note:** The port flag and env var do not require `python3`, so `python3` is only needed when no explicit port is provided.

### Edge Case 3: Container name already in use by a non-devenv container

- **Scenario:** A container named `devenv-local-api` exists but was not created by devenv (no `devenv=true` label).
- **Handling:** `docker run --name` will fail with "name already in use". `cmd_start()` should check for this error and `die` with a clear message explaining the conflict.
- **Recommendation:** Before starting, check if ANY container (not just running) has the name: `docker ps -a --filter "name=^/${name}$" --format '{{.Names}}'`. If it exists without the devenv label, die with guidance.

### Edge Case 4: Project path with special characters in basename

- **Scenario:** Path like `/home/user/projects/my project` or `/home/user/projects/my.project@v2`.
- **Handling:** Docker container names only allow `[a-zA-Z0-9][a-zA-Z0-9_.-]`. `derive_container_name()` must sanitize the name by replacing disallowed characters (e.g., spaces, `@`, etc.) with hyphens or removing them.
- **Recommendation:** `tr -cd 'a-zA-Z0-9_.-'` or `sed 's/[^a-zA-Z0-9_.-]/-/g'` on the basename components. Ensure the result is non-empty and starts with an alphanumeric character.

### Edge Case 5: `docker exec` session exits but container stays running

- **By design.** The spec explicitly states: the container runs `sleep infinity` and persists until `devenv stop`. Multiple `docker exec` sessions can attach and detach independently. No special handling needed — this is the intended behavior.

### Edge Case 6: Multiple calls to `devenv .` racing to start the same container

- **Scenario:** Two terminals run `devenv .` simultaneously for the same project. Both see no running container and both try to `docker run --name devenv-local-api`.
- **Handling:** The second `docker run` will fail because the name is already in use. `cmd_start()` should catch this failure, re-check `is_container_running()`, and if the container is now running, proceed to `attach_container()`.
- **Recommendation:** Wrap the start logic in a retry: try start → if name conflict → re-check → attach if running → die if still failing.

### Edge Case 7: `devenv stop .` when no container is running

- **Scenario:** User runs `devenv stop .` but no container exists for the project.
- **Handling:** `docker stop` on a non-existent container will fail. `cmd_stop()` should check `is_container_running()` first and print a warning: "No running container for <project>".
- **Recommendation:** `log_warning "No running container: ${container_name}"` and exit 0 (not an error).

### Edge Case 8: `devenv stop --all` when no containers are running

- **Scenario:** User runs `devenv stop --all` but no devenv containers exist.
- **Handling:** `docker ps -q --filter label=devenv=true` returns empty. `docker stop` with no arguments fails.
- **Recommendation:** Check if the container list is empty first. If empty, `log_info "No devenv containers running"` and exit 0.

### Edge Case 9: `devenv list` when no containers are running

- **Scenario:** User runs `devenv list` with no devenv containers running.
- **Handling:** Print the table header with no rows, or print a message "No devenv containers running".
- **Recommendation:** Print the header and no rows. This preserves parseable output for scripts.

### Edge Case 10: Distinguishing path arguments from container names in `devenv stop`

- **Scenario:** `devenv stop api` — is `api` a container name or a relative path?
- **Handling per spec:** If argument contains `/` or is `.`, treat as path and resolve. Otherwise, treat as container name.
- **Additional heuristic:** Check if the argument is an existing directory. If it is, resolve as path. If not, treat as container name.
- **Recommendation:** Use the directory-existence check: `if [[ -d "${arg}" ]] || [[ "${arg}" == "." ]] || [[ "${arg}" == */* ]]; then resolve_as_path; else treat_as_name; fi`.

### Edge Case 11: `devenv --port 3333 .` when container already running

- **Scenario:** Container is already running (possibly on a different port). User specifies `--port 3333`.
- **Handling:** Since the container is already running with its port binding set at start time, the `--port` flag is irrelevant for existing containers. `cmd_start()` should log a warning that port is ignored for existing containers, then attach.
- **Recommendation:** `log_warning "Container already running; --port flag ignored. SSH port was allocated at start time."`

### Edge Case 12: Root-level project path

- **Scenario:** `devenv /tmp/project` — parent is `/tmp`, parent basename is `tmp`.
- **Handling:** Works normally. Container name: `devenv-tmp-project`. Label: `tmp/project`.
- **No special handling needed.**

---

## 2.5 External Dependencies

### New Runtime Dependencies (host machine)

| Dependency | Purpose | Availability | Fallback |
|---|---|---|---|
| `python3` | SSH port pre-allocation via `socket.socket()` | Pre-installed on most Linux distros and macOS | `DEVENV_SSH_PORT` env var or `--port` flag bypass the need for `python3` |
| `docker` | Container management | Already required | None (hard dependency) |

### No New Container Dependencies

No new tools are required inside the container. The `sleep` command (used for `sleep infinity`) is part of GNU coreutils, which is already installed in the base image.

### No New Build Dependencies

No changes to the Dockerfile build pipeline are required.

---

## 2.6 Files That Don't Change

### `Dockerfile.base`

**Reason:** The spec carries forward the base image definition unchanged. User setup, SSH server installation, `/workspaces` directory creation, and build arguments are all preserved exactly as-is.

### `Dockerfile.devenv`

**Reason:** The multi-stage composition strategy is unchanged. Tool aggregation via `COPY --from` instructions remains the same.

### `tools/Dockerfile.*` (all 14 tool Dockerfiles)

**Reason:** All tool installation methods are carried forward verbatim from the archived spec. No tool-specific changes are required. The complete list:

- `tools/Dockerfile.cargo`
- `tools/Dockerfile.copilot-cli`
- `tools/Dockerfile.fnm`
- `tools/Dockerfile.fzf`
- `tools/Dockerfile.gh`
- `tools/Dockerfile.go`
- `tools/Dockerfile.jq`
- `tools/Dockerfile.node`
- `tools/Dockerfile.nvim`
- `tools/Dockerfile.opencode`
- `tools/Dockerfile.ripgrep`
- `tools/Dockerfile.starship`
- `tools/Dockerfile.uv`
- `tools/Dockerfile.yq`

### `templates/Dockerfile.project`

**Reason:** The generic project template extends `devenv:latest` and is unchanged by the runtime interface changes.

### `templates/Dockerfile.python-uv`

**Reason:** The Python/uv template extends `devenv:latest` and is unchanged.

### `templates/README.md`

**Reason:** Template documentation is unchanged.

### `specs/coding-standard.md`

**Reason:** This is the authoritative coding standard. It defines the rules; it is not modified by implementation.

### `plans/summary.md`

**Reason:** This is a historical conversation summary. It is a reference document, not modified by implementation.

### `plans/plan.md`

**Reason:** This is the execution plan. It guides work but is not modified by implementation.

---

## Appendix A: Logging Framework (shared across all scripts)

Every script (`devenv`, `build-devenv`, `install-devenv`) must include this identical logging block in the `# --- Logging ---` section:

```bash
# --- Logging ---
declare -A _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
readonly DEVENV_LOG_LEVEL="${DEVENV_LOG_LEVEL:-WARNING}"

_log() {
    local level="$1"; shift
    if (( _LOG_LEVELS[${level}] >= _LOG_LEVELS[${DEVENV_LOG_LEVEL}] )); then
        printf '[%s] [%-7s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "${level}" "$*" >&2
    fi
}

log_debug()   { _log "DEBUG" "$@"; }
log_info()    { _log "INFO" "$@"; }
log_warning() { _log "WARNING" "$@"; }
log_error()   { _log "ERROR" "$@"; }

# Log error and exit. Only place exit 1 is permitted outside main.
die() { _log "ERROR" "$@"; exit 1; }
```

## Appendix B: New `devenv` Script Structure Outline

The refactored `devenv` script should follow this order:

```bash
#!/bin/bash
set -euo pipefail

# devenv - Runtime environment launcher for containerized development

# --- Constants ---
readonly DEVENV_HOME="${HOME}/.config/devenv"
readonly IMAGE_PREFIX="devenv"

# --- Logging ---
# (logging framework from Appendix A)

# --- Primitives ---
# resolve_project_path()      — path arg → canonical absolute path
# derive_container_name()     — path → "devenv-parent-basename"
# derive_project_label()      — path → "parent/basename"
# get_image_name()            — path → image tag string
# allocate_port()             — → free port number
# is_container_running()      — name → return 0/1
# validate_docker()           — → return 0/1
# build_mounts()              — path, name → populates mounts array
# build_env_vars()            — → populates env_vars array
# ensure_project_image()      — path → build if needed
# start_container()           — path, name, image, port → docker run -d
# attach_container()          — name, project_name → docker exec -it

# --- Commands ---
# usage()                     — print help text
# cmd_start()                 — start/attach to environment
# cmd_list()                  — list running environments
# cmd_stop()                  — stop environment(s)

# --- Entrypoint ---
# main()                      — dispatch subcommands

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

## Appendix C: Summary of All Changes by Category

### NEW (must be created from scratch)

1. Logging framework (in all 3 scripts)
2. `resolve_project_path()` in `devenv`
3. `derive_container_name()` in `devenv`
4. `derive_project_label()` in `devenv`
5. `allocate_port()` in `devenv`
6. `is_container_running()` in `devenv`
7. `build_mounts()` in `devenv`
8. `build_env_vars()` in `devenv`
9. `start_container()` in `devenv`
10. `attach_container()` in `devenv`
11. `cmd_start()` in `devenv`
12. `cmd_list()` in `devenv`
13. `cmd_stop()` in `devenv`
14. Source guard in all 3 scripts

### UPDATE (existing code, modified)

1. Constants → `readonly` (all 3 scripts)
2. `usage()` in `devenv` — new commands/flags
3. `validate_docker()` in `devenv` and `build-devenv` — primitive refactor
4. `get_image_name()` in `devenv` — parent-basename naming, printf
5. `ensure_project_image()` in `devenv` — parent-basename naming
6. `build_project()` in `build-devenv` — parent-basename naming
7. `main()` in `devenv` — case dispatch, getopts
8. `main()` in `build-devenv` — logging, source guard
9. `main()` in `install-devenv` — logging, source guard
10. `README.md` — new commands, lifecycle, SSH behavior

### REMOVE (existing code, deleted)

1. `log()` function (all 3 scripts)
2. `error()` function (all 3 scripts)
3. `run_devenv()` in `devenv` (replaced by cmd_start + primitives)
4. Bare `main "$@"` at end of scripts (replaced by source guard)

# Research: Multi-Environment Architecture Gap Analysis

**Source spec:** `specs/multi-environment-architecture.md` (480 lines)

**Files analyzed:**

| File | Lines |
|------|-------|
| `docker/devenv/Dockerfile.base` | 62 |
| `docker/devenv/Dockerfile.devenv` | 230 |
| `docker/devenv/templates/Dockerfile.project` | 21 |
| `docker/devenv/templates/Dockerfile.python-uv` | 32 |
| `docker/devenv/templates/README.md` | 44 |
| `bin/build-devenv` | 270 |
| `bin/devenv` | 631 |
| `scripts/install-devenv` | 158 |
| `shared/bash/log.sh` | 37 |
| `shared/tools/Dockerfile.cargo` | 23 |
| `shared/tools/Dockerfile.common-utils` | 28 |
| `shared/tools/Dockerfile.copilot-cli` | 14 |
| `shared/tools/Dockerfile.fnm` | 21 |
| `shared/tools/Dockerfile.fzf` | 11 |
| `shared/tools/Dockerfile.gh` | 23 |
| `shared/tools/Dockerfile.go` | 21 |
| `shared/tools/Dockerfile.jq` | 20 |
| `shared/tools/Dockerfile.node` | 46 |
| `shared/tools/Dockerfile.nvim` | 24 |
| `shared/tools/Dockerfile.opencode` | 14 |
| `shared/tools/Dockerfile.ripgrep` | 23 |
| `shared/tools/Dockerfile.starship` | 17 |
| `shared/tools/Dockerfile.tree-sitter` | 25 |
| `shared/tools/Dockerfile.uv` | 20 |
| `shared/tools/Dockerfile.yq` | 16 |
| `AGENTS.md` | 9 |
| `specs/coding-standard.md` | 472 |

---

## Current State Snapshot

The codebase implements a single-environment (devenv) containerized development setup:

- **One Dockerfile.base** at `docker/devenv/Dockerfile.base` builds directly `FROM ubuntu:24.04`. It installs both core packages AND SSH (openssh-client, openssh-server) in a single image. There is no separate `repo-base` layer.
- **One Dockerfile.devenv** at `docker/devenv/Dockerfile.devenv` uses `devenv-base:latest` as the FROM for all inline tool stages and the `common_utils` stage. The final stage composes tools via `COPY --from=tool_*`.
- **16 shared tool Dockerfiles** in `shared/tools/` all use `FROM devenv-base:latest` as their build base.
- **One build script** `bin/build-devenv` supports `--stage base|devenv`, `--tool <name>`, and `--project <path>`. It knows only two stages and one environment type.
- **One runtime script** `bin/devenv` manages interactive devenv containers with SSH, volumes (`devenv-data`, `devenv-cache`, `devenv-state`), and config mounts.
- **One install script** `scripts/install-devenv` creates symlinks for `build-devenv` and `devenv` only.
- **No `docker/base/` directory** exists. No `docker/ralph/` directory exists. No `bin/ralph` script exists.
- **No `repo-base` image** concept exists; the current `devenv-base` serves as both the shared foundation and the SSH/interactive base.

---

## Gap Analysis Matrix

| Spec Requirement | Current State | Gap Type | Required Action |
|---|---|---|---|
| **`docker/base/Dockerfile.base`** for `repo-base:latest` (Ubuntu + user + core packages, no SSH) | Does not exist. `docker/base/` directory absent. | NEW | Create `docker/base/Dockerfile.base` with Ubuntu 24.04, core packages (ca-certificates, curl, git, sudo, wget), user creation, sudo setup. No SSH. |
| **`docker/devenv/Dockerfile.base`** builds `FROM repo-base:latest`, adds SSH only | Current `docker/devenv/Dockerfile.base` builds `FROM ubuntu:24.04` and includes both core packages AND SSH in one layer. | UPDATE | Refactor to `FROM repo-base:latest`, remove duplicated core package installation and user creation, keep only SSH-specific additions (openssh-client, openssh-server, ssh-keygen -A, /run/sshd, .ssh directory). |
| **`docker/devenv/Dockerfile.devenv`** tool stages `FROM repo-base:latest` instead of `devenv-base:latest` | All 15 inline tool stages use `FROM devenv-base:latest`. | UPDATE | Change all inline tool stage FROM lines from `devenv-base:latest` to `repo-base:latest`. The `common_utils` stage and final `devenv` stage remain `FROM devenv-base:latest`. |
| **`docker/ralph/Dockerfile.base`** for `ralph-base:latest` | Does not exist. `docker/ralph/` directory absent. | NEW | Create `docker/ralph/Dockerfile.base` FROM `repo-base:latest` with headless config, git non-interactive setup, working directory structure. |
| **`docker/ralph/Dockerfile.ralph`** for `ralph:latest` | Does not exist. | NEW | Create multi-stage build with tool subset: jq, yq, gh, opencode, ripgrep, uv, node, fnm. Aggregate via `COPY --from=tool_*`. |
| **`docker/ralph/templates/Dockerfile.project`** | Does not exist. | NEW | Create ralph project template `FROM ralph:latest`. |
| **`docker/ralph/templates/README.md`** | Does not exist. | NEW | Create ralph templates README. |
| **All 16 `shared/tools/Dockerfile.*`** change FROM `devenv-base:latest` to `repo-base:latest` | All use `FROM devenv-base:latest`. | UPDATE | Replace `devenv-base:latest` with `repo-base:latest` in all 16 tool Dockerfiles. |
| `shared/tools/Dockerfile.ripgrep` references `devenv-tool-jq:latest` | Line 7: `FROM devenv-tool-jq:latest AS jq_source` | NO CHANGE | Inter-stage dependency unchanged per spec. Tag convention (`devenv-tool-*`) is also unchanged. |
| `shared/tools/Dockerfile.tree-sitter` references `devenv-tool-node:latest` | Line 6: `FROM devenv-tool-node:latest AS tool_node` | NO CHANGE | Inter-stage dependency unchanged per spec. |
| **`bin/build-devenv`** extended CLI: `--stage base\|devenv-base\|devenv\|ralph-base\|ralph` | Supports only `base` and `devenv` stages. | UPDATE | Add `ralph-base` and `ralph` stages. Rename `base` stage to build `repo-base` from `docker/base/Dockerfile.base`. Add `devenv-base` as explicit stage building from `docker/devenv/Dockerfile.base`. |
| **`bin/build-devenv`** auto-dependency resolution for ralph chain | No ralph dependency chain. | UPDATE | Add dependency resolution: `ralph-base` requires `repo-base`, `ralph` requires `repo-base` + `ralph-base`. |
| **`bin/build-devenv`** `--project` auto-detects `.ralph/` | Only checks `.devenv/Dockerfile`. | UPDATE | Add `.ralph/Dockerfile` detection. Error if both exist. Build as `ralph-project-*` when `.ralph/` found. |
| **`bin/build-devenv`** image tagging: `repo-base:<timestamp>`, `ralph-base:<timestamp>`, `ralph:<timestamp>` | Tags only `devenv-base` and `devenv`. | UPDATE | Add timestamp + latest tagging for `repo-base`, `ralph-base`, `ralph`. |
| **`bin/ralph`** runtime launcher | Does not exist. | NEW | Create `bin/ralph` with commands: `<path>`, `list`, `stop <path>`, `stop --all`, `logs <path>`. Non-interactive container lifecycle with `--rm`, ralph-specific volumes, git/agent config mounts only. |
| **Ralph persistent volumes** (`ralph-data`, `ralph-cache`, `ralph-state`) | Do not exist. | NEW | Implemented within `bin/ralph` volume management. |
| **`scripts/install-devenv`** extended for `bin/ralph` symlink | Only creates symlinks for `build-devenv` and `devenv`. | UPDATE | Add `ralph` symlink creation/removal. |
| **Devenv runtime** (`bin/devenv`) unchanged | `bin/devenv` at 631 lines. | NO CHANGE | No changes to devenv runtime per spec non-goals. |
| **Devenv project templates** unchanged | `docker/devenv/templates/` with 3 files. | NO CHANGE | Templates remain as-is. |
| **`shared/bash/log.sh`** unchanged | 37 lines, compliant with coding standard. | NO CHANGE | No changes needed. |
| **`docker/devenv/Dockerfile.devenv`** `common_utils` stage stays `FROM devenv-base:latest` | Line 10: `FROM devenv-base:latest AS common_utils`. | NO CHANGE | Spec confirms common_utils continues from devenv-base. |
| **`docker/devenv/Dockerfile.devenv`** final stage stays `FROM common_utils` | Line 162: `FROM common_utils AS devenv`. | NO CHANGE | Spec confirms final stage from common_utils. |
| **Devenv project templates** (`docker/devenv/templates/`) | Exist with `FROM devenv:latest`. | NO CHANGE | Unchanged per spec. |

---

## File-Level Change Map

### Files to CREATE

| File | Nature | Dependencies |
|------|--------|-------------|
| `docker/base/Dockerfile.base` | NEW | None (builds from `ubuntu:24.04`) |
| `docker/ralph/Dockerfile.base` | NEW | Requires `repo-base:latest` to exist |
| `docker/ralph/Dockerfile.ralph` | NEW | Requires `ralph-base:latest` to exist |
| `docker/ralph/templates/Dockerfile.project` | NEW | None |
| `docker/ralph/templates/README.md` | NEW | None |
| `bin/ralph` | NEW | Depends on `shared/bash/log.sh` |

### Files to UPDATE

| File | Lines | Change Summary | Dependencies |
|------|-------|---------------|-------------|
| `docker/devenv/Dockerfile.base` (62 lines) | Lines 6, 19-27, 29-30, 34-46, 48-52 | Extract core logic to `docker/base/Dockerfile.base`; refactor to `FROM repo-base:latest`; keep only SSH setup | Requires `docker/base/Dockerfile.base` to exist first |
| `docker/devenv/Dockerfile.devenv` (230 lines) | Lines 10, 29, 35, 43, 51, 58, 63, 69, 88, 108, 121, 129, 139, 143, 147, 152 | Change all inline tool stage FROM from `devenv-base:latest` to `repo-base:latest` | Requires `repo-base:latest` image |
| `bin/build-devenv` (270 lines) | Lines 24-48, 102-121, 210-265 | Add `repo-base`/`ralph-base`/`ralph` stages; update dependency resolution; add ralph project detection; update usage text | Requires new Dockerfiles to exist |
| `scripts/install-devenv` (158 lines) | Lines 36-38, 54-82, 95-116 | Add `ralph` symlink creation/removal | Requires `bin/ralph` to exist |
| `shared/tools/Dockerfile.cargo` (23 lines) | Line 6 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.common-utils` (28 lines) | Line 6 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.copilot-cli` (14 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.fnm` (21 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.fzf` (11 lines) | Line 3 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.gh` (23 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.go` (21 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.jq` (20 lines) | Line 7 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.node` (46 lines) | Lines 6, 15 | `devenv-base:latest` -> `repo-base:latest` (both stages) | None |
| `shared/tools/Dockerfile.nvim` (24 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.opencode` (14 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.ripgrep` (23 lines) | Line 8 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.starship` (17 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.tree-sitter` (25 lines) | Line 9 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.uv` (20 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |
| `shared/tools/Dockerfile.yq` (16 lines) | Line 5 | `devenv-base:latest` -> `repo-base:latest` | None |

### Files that DO NOT change

| File | Reason |
|------|--------|
| `bin/devenv` (631 lines) | Spec non-goal: devenv runtime unchanged |
| `shared/bash/log.sh` (37 lines) | No spec requirements affect logging |
| `docker/devenv/templates/Dockerfile.project` (21 lines) | Devenv templates unchanged |
| `docker/devenv/templates/Dockerfile.python-uv` (32 lines) | Devenv templates unchanged |
| `docker/devenv/templates/README.md` (44 lines) | Devenv templates unchanged |
| `AGENTS.md` (9 lines) | Not affected by this spec |
| `specs/coding-standard.md` (472 lines) | Reference only, not modified |

---

## Function/Block-Level Detail

### `docker/devenv/Dockerfile.base` (62 lines) -> Split into two files

**Current behavior:** Single file builds `FROM ubuntu:24.04`, installs all core packages + SSH, creates user, sets up SSH directories.

**Target behavior:** Two files. `docker/base/Dockerfile.base` handles Ubuntu base + core packages + user. `docker/devenv/Dockerfile.base` builds `FROM repo-base:latest` and adds only SSH.

**Lines affected in current `docker/devenv/Dockerfile.base`:**
- Lines 6-16 (FROM, LABEL, ARGs, ENV): Move Ubuntu FROM + LABEL + ARGs + ENV to `docker/base/Dockerfile.base`. Devenv base changes FROM to `repo-base:latest`.
- Lines 19-27 (apt-get with core packages + SSH): Split. Core packages (ca-certificates, curl, git, sudo, wget) go to `docker/base/Dockerfile.base`. SSH packages (openssh-client, openssh-server) stay in `docker/devenv/Dockerfile.base`.
- Lines 29-30 (SSH setup: mkdir /run/sshd, ssh-keygen -A): Stay in `docker/devenv/Dockerfile.base`.
- Lines 34-46 (user creation + sudo): Move to `docker/base/Dockerfile.base`.
- Lines 48-52 (SSH directory .ssh): Stay in `docker/devenv/Dockerfile.base`.
- Lines 54-61 (WORKDIR, USER, CMD): Duplicated in both. `docker/base/Dockerfile.base` ends with USER + CMD. `docker/devenv/Dockerfile.base` inherits from repo-base and adds SSH-specific setup.

**New `docker/base/Dockerfile.base` content:**
- `FROM ubuntu:24.04 AS base`
- `LABEL devenv=true`
- ARGs: USERNAME, USER_UID, USER_GID
- `ENV DEBIAN_FRONTEND=noninteractive`
- RUN: apt-get install ca-certificates, curl, git, sudo, wget (no openssh)
- RUN: user/group creation + sudo setup (moved from lines 34-46)
- WORKDIR, USER, CMD

**New `docker/devenv/Dockerfile.base` content:**
- `FROM repo-base:latest AS base`
- `LABEL devenv=true`
- ARGs passed through
- USER root
- RUN: apt-get install openssh-client, openssh-server
- RUN: mkdir -p /run/sshd && ssh-keygen -A
- RUN: mkdir .ssh, chmod, chown
- USER devuser
- CMD

### `docker/devenv/Dockerfile.devenv` (230 lines) -> FROM changes for tool stages

**Current behavior:** All 15 inline tool stages use `FROM devenv-base:latest`. The `common_utils` stage uses `FROM devenv-base:latest`. Final `devenv` stage uses `FROM common_utils`.

**Target behavior:** All inline tool stages change to `FROM repo-base:latest`. The `common_utils` stage and final stage remain unchanged.

**Specific lines to change:**
- Line 10: `FROM devenv-base:latest AS common_utils` -> NO CHANGE
- Line 29: `FROM devenv-base:latest AS tool_cargo` -> `FROM repo-base:latest AS tool_cargo`
- Line 35: `FROM devenv-base:latest AS tool_go` -> `FROM repo-base:latest AS tool_go`
- Line 43: `FROM devenv-base:latest AS tool_fnm` -> `FROM repo-base:latest AS tool_fnm`
- Line 51: `FROM devenv-base:latest AS tool_uv` -> `FROM repo-base:latest AS tool_uv`
- Line 58: `FROM devenv-base:latest AS tool_fzf` -> `FROM repo-base:latest AS tool_fzf`
- Line 63: `FROM devenv-base:latest AS tool_jq` -> `FROM repo-base:latest AS tool_jq`
- Line 69: `FROM devenv-base:latest AS tool_node` -> `FROM repo-base:latest AS tool_node`
- Line 88: `FROM devenv-base:latest AS tool_ripgrep` -> `FROM repo-base:latest AS tool_ripgrep`
- Line 108: `FROM devenv-base:latest AS tool_gh` -> `FROM repo-base:latest AS tool_gh`
- Line 121: `FROM devenv-base:latest AS tool_nvim` -> `FROM repo-base:latest AS tool_nvim`
- Line 129: `FROM devenv-base:latest AS tool_opencode` -> `FROM repo-base:latest AS tool_opencode`
- Line 139: `FROM devenv-base:latest AS tool_copilot-cli` -> `FROM repo-base:latest AS tool_copilot-cli`
- Line 143: `FROM devenv-base:latest AS tool_starship` -> `FROM repo-base:latest AS tool_starship`
- Line 147: `FROM devenv-base:latest AS tool_yq` -> `FROM repo-base:latest AS tool_yq`
- Line 152: `FROM devenv-base:latest AS tool_tree_sitter` -> `FROM repo-base:latest AS tool_tree_sitter`
- Line 162: `FROM common_utils AS devenv` -> NO CHANGE

Note: Line 7 (`FROM devenv-base:latest AS devenv-base`) is a reference alias; it also stays unchanged since it references the environment base, not tool builds.

### `bin/build-devenv` (270 lines) -> Extended for multi-env

**Current `build_stage_base()` (lines 102-121):**
- Builds from `docker/devenv/Dockerfile.base` and tags as `devenv-base:latest`.

**Target `build_stage_base()`:**
- Rename to `build_stage_repo_base()` or keep as `build_stage_base()`.
- Build from `docker/base/Dockerfile.base` and tag as `repo-base:latest`.

**New function `build_stage_devenv_base()`:**
- Build from `docker/devenv/Dockerfile.base`, tag as `devenv-base:latest`.
- Auto-build `repo-base` if missing.

**Current `build_stage_devenv()` (lines 124-148):**
- Checks for `devenv-base:latest`, auto-builds it.

**Target `build_stage_devenv()`:**
- Check for `devenv-base:latest` (which transitively requires `repo-base`).
- Auto-build `repo-base` then `devenv-base` if either missing.

**New functions:**
- `build_stage_ralph_base()`: Build `docker/ralph/Dockerfile.base`, tag `ralph-base:latest`. Auto-build `repo-base` if missing.
- `build_stage_ralph()`: Build `docker/ralph/Dockerfile.ralph`, tag `ralph:latest`. Auto-build `repo-base` + `ralph-base` if missing.

**Current `build_project()` (lines 181-206):**
- Only checks for `.devenv/Dockerfile`.

**Target `build_project()`:**
- Check for `.devenv/Dockerfile` and `.ralph/Dockerfile`.
- If both exist, error with guidance.
- Build `.ralph/Dockerfile` as `ralph-project-<suffix>:latest`.

**Current `main()` case dispatch (lines 225-235):**
- `base` and `devenv` cases only.

**Target dispatch:**
- `base` -> `build_stage_repo_base`
- `devenv-base` -> `build_stage_devenv_base`
- `devenv` -> `build_stage_devenv`
- `ralph-base` -> `build_stage_ralph_base`
- `ralph` -> `build_stage_ralph`

**Current `usage()` (lines 24-48):**
- Lists only `base` and `devenv` stages.

**Target `usage()`:**
- List all 5 stages: `base`, `devenv-base`, `devenv`, `ralph-base`, `ralph`.

**Current `build_tool()` (lines 151-178):**
- Checks for `devenv-base:latest` before building tools.

**Target `build_tool()`:**
- Check for `repo-base:latest` instead (since tools now build from `repo-base`).

### `bin/ralph` -> NEW file (~300-400 lines estimated)

**Structure follows `bin/devenv` pattern per coding standard:**
- Constants: `VOLUME_DATA="ralph-data"`, `VOLUME_CACHE="ralph-cache"`, `VOLUME_STATE="ralph-state"`, `IMAGE_PREFIX="ralph"`.
- Logging: source `shared/bash/log.sh`.
- Primitives: `resolve_project_path()`, `resolve_container_project_path()`, `derive_container_name()` (prefix `ralph-`), `derive_project_label()`, `get_image_name()`, `build_mounts()` (git + agent config only), `build_env_vars()`.
- Commands: `cmd_start()`, `cmd_list()`, `cmd_stop()`, `cmd_logs()`.
- Entrypoint: `main()` with dispatch.

**Key differences from `bin/devenv`:**
- No SSH port allocation or binding.
- No interactive shell config mounts (.bashrc, .inputrc, nvim, starship, etc.).
- Mounts: ralph-specific volumes, project directory, git config, opencode config, SSH_AUTH_SOCK.
- Container command: `bash -lc "while :; do cat PROMPT.md | opencode ; done"` (configurable).
- Container started with `--rm` (auto-remove on exit).
- No `attach_container`; uses `docker logs` via `cmd_logs()`.
- Labels: `ralph=true`, `ralph.project=<parent>/<project>`.

### `scripts/install-devenv` (158 lines) -> Add ralph symlink

**Current `install_devenv()` (lines 45-92):**
- Creates symlinks for `build-devenv` and `devenv`.

**Target:**
- Add check for `bin/ralph` existence.
- Create symlink `~/.local/bin/ralph -> <source>/bin/ralph`.

**Current `uninstall_devenv()` (lines 95-116):**
- Removes `build-devenv` and `devenv` symlinks.

**Target:**
- Also remove `ralph` symlink.

**Current `usage()` (lines 24-41):**
- Lists only `build-devenv` and `devenv` symlinks.

**Target:**
- Add `ralph` to the symlink list.

---

## Edge Cases and Tradeoffs

| Scenario | Recommended Handling |
|----------|---------------------|
| **`--project` path has both `.devenv/` and `.ralph/`** | Error with message: "Both .devenv/ and .ralph/ found. Use --stage to build a specific environment." Per spec line 388-389. |
| **`repo-base:latest` missing when building devenv-base** | Auto-build `repo-base` first. Already patterned in current code for `devenv-base` -> `devenv`. |
| **`repo-base:latest` missing when building tools** | Auto-build `repo-base`. Current code checks for `devenv-base`; must change to `repo-base`. |
| **Ralph container exits (agent loop ends)** | `--rm` flag auto-removes container. `ralph list` shows only running containers. |
| **Ralph container with no PROMPT.md** | Agent loop fails. `cmd_logs` shows the error. Container exits and is removed. User must create PROMPT.md in project. |
| **SSH_AUTH_SOCK not set on host** | Ralph script should handle gracefully (skip mount). Pattern already exists in `bin/devenv` line 230-232. |
| **Git config files missing on host** | Skip mount. Same pattern as devenv mounts (conditional `-f` / `-d` checks). |
| **Ralph volume in use when attempting removal** | Not specified for ralph, but `bin/ralph` should support volume management similar to devenv. The spec does not explicitly require `ralph volume` commands, but it is implied by volume naming. |
| **Tool builds during transition** | If `repo-base` is not built but `devenv-base` exists, old tool Dockerfiles fail. Build `repo-base` first during migration. |
| **Concurrent ralph and devenv containers for same project** | Separate volume namespaces prevent conflicts. Container names have different prefixes (`devenv-` vs `ralph-`). Both can run simultaneously. |

---

## External Dependencies

| Dependency | Type | Status | Fallback |
|------------|------|--------|----------|
| `ubuntu:24.04` | Base image | Available (current) | Pin to specific digest if needed |
| `ghcr.io/jqlang/jq:latest` | Tool source image | Available (used by `Dockerfile.jq`) | Already in use, no change |
| `opencode` CLI | Agent tool for ralph | Available (already installed in devenv) | N/A - core requirement for ralph |
| `docker` runtime | Host dependency | Available (current) | N/A - required |

No new external runtime or build dependencies are introduced. All tools referenced in the ralph tool set already have Dockerfiles in `shared/tools/` or inline stages in `Dockerfile.devenv`.

---

## Open Decisions

### 1. Ralph volume management subcommand

**Question:** Should `bin/ralph` include `volume list` / `volume rm` commands like `bin/devenv`?

**Options:**
- **Include volume management (recommended):** Mirrors devenv interface, consistent UX. Ralph volumes (`ralph-data`, `ralph-cache`, `ralph-state`) need management. ~60 additional lines.
- **Omit for now:** Reduces initial scope. Users can manage volumes via `docker volume` directly. Can be added later.

### 2. Configurable agent command per project

**Question:** The spec mentions the agent command is "configurable per project (defined in the project's `.ralph/` directory)" (line 452-453). What is the configuration mechanism?

**Options:**
- **Convention file (e.g., `.ralph/config` or `.ralph/loop.sh`):** Simple, readable. `bin/ralph` reads command from file if present, falls back to default `while :; do cat PROMPT.md | opencode ; done`.
- **Defer to implementation plan:** The spec says "the agent loop configuration is project-specific" (line 476) and lists this as a non-goal for full orchestration. The default loop command in `docker run` is sufficient for initial implementation.

### 3. Build script naming

**Question:** The spec shows `build-devenv --stage base` building `repo-base`. The script name `build-devenv` is devenv-centric. Should it be renamed?

**Options:**
- **Keep `build-devenv` (recommended):** Spec explicitly states the repo is not being renamed (lines 477-479). The script manages all builds including ralph. Renaming would break existing installations.
- **Rename to `build-env` or similar:** Cleaner naming but contradicts spec non-goals.

---

## Suggested Implementation Order

1. **Create `docker/base/Dockerfile.base`** — New repo-base image. No dependencies. Can be validated independently with `docker build`.

2. **Refactor `docker/devenv/Dockerfile.base`** — Change FROM to `repo-base:latest`, remove duplicated core logic, keep SSH only. Requires step 1.

3. **Update all 16 `shared/tools/Dockerfile.*`** — Change FROM from `devenv-base:latest` to `repo-base:latest`. Mechanical change, no logic changes. Can be done in a single pass.

4. **Update `docker/devenv/Dockerfile.devenv`** — Change inline tool stage FROM lines from `devenv-base:latest` to `repo-base:latest`. Requires steps 1-2 for build, but file edit is independent.

5. **Create `docker/ralph/Dockerfile.base`** — New ralph-base image. Requires step 1 (repo-base).

6. **Create `docker/ralph/Dockerfile.ralph`** — New ralph image with tool subset. Requires step 5. Multi-stage build referencing tool stages from `repo-base:latest`.

7. **Create `docker/ralph/templates/`** — `Dockerfile.project` and `README.md`. No build dependencies.

8. **Update `bin/build-devenv`** — Add all new stages, update dependency resolution, add ralph project detection. Requires steps 1-6 for testing.

9. **Create `bin/ralph`** — New runtime launcher. Requires step 6 (ralph image) for testing.

10. **Update `scripts/install-devenv`** — Add ralph symlink. Requires step 9.

11. **Validate full build chain** — Build `repo-base` -> `devenv-base` -> `devenv` and `repo-base` -> `ralph-base` -> `ralph`. Verify existing devenv workflow is unbroken.

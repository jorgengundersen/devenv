# Implementation Plan: Multi-Environment Architecture

**Source research:** `plans/current/multi-environment-architecture/research.md`

**Required reading before implementation:**

- `specs/multi-environment-architecture.md` (authoritative spec)
- `specs/coding-standard.md` (all code must conform)
- `AGENTS.md` (agent rules)

---

## Execution Rules

1. Run `shellcheck` on any created or modified bash script (`AGENTS.md`).
2. Every Dockerfile must start with `# syntax=docker/dockerfile:1` (`coding-standard.md` 2.2).
3. Every `apt-get install` must use `--no-install-recommends` and clean caches in the same layer (`coding-standard.md` 2.2).
4. Final Dockerfile stages must end with `USER devuser` (`coding-standard.md` 2.2).
5. Bash scripts must use `set -euo pipefail`, `local` for all function variables, `printf` (not `echo`) for return values (`coding-standard.md` 1.2-1.8).
6. No backwards compatibility requirements (`AGENTS.md`).
7. One-line comment above every new function (`coding-standard.md` 1.3).

---

## Phase 1: New Repo-Base Image

### Task 1 — Create `docker/base/Dockerfile.base`

- **Files:** `docker/base/Dockerfile.base` (new file, new directory)
- **Description:** Create the repo-base Dockerfile — the shared foundation image for all environments. Provides Ubuntu 24.04, core packages, non-privileged user creation, and sudo. No SSH.
- **Before:** File and directory do not exist.
- **After:**
```dockerfile
# syntax=docker/dockerfile:1

# Repo Base Image
# Shared foundation for all environment types: Ubuntu LTS, core packages, devuser

FROM ubuntu:24.04 AS base

LABEL repo-base=true

ARG USERNAME=devuser
ARG USER_UID=1000
ARG USER_GID=1000

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
    sudo \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create group and user with matching host UID/GID.
RUN if ! getent group ${USER_GID} > /dev/null 2>&1; then \
        groupadd --gid ${USER_GID} ${USERNAME}; \
    else \
        groupmod -n ${USERNAME} $(getent group ${USER_GID} | cut -d: -f1); \
    fi \
    && if ! getent passwd ${USER_UID} > /dev/null 2>&1; then \
        useradd --uid ${USER_UID} --gid ${USER_GID} --shell /bin/bash --create-home ${USERNAME}; \
    else \
        usermod -l ${USERNAME} -d /home/${USERNAME} -m $(getent passwd ${USER_UID} | cut -d: -f1); \
        groupmod -n ${USERNAME} $(getent group ${USER_GID} | cut -d: -f1) 2>/dev/null || true; \
    fi \
    && echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

WORKDIR /home/${USERNAME}

USER ${USERNAME}

CMD ["/bin/bash"]
```
- **Verification:** `docker build -f docker/base/Dockerfile.base -t repo-base:latest .` succeeds. `docker run --rm repo-base:latest id` outputs `uid=1000(devuser)`.

---

## Phase 2: Update Devenv Base Image

### Task 2 — Rewrite `docker/devenv/Dockerfile.base`

- **Files:** `docker/devenv/Dockerfile.base:1-62`
- **Description:** Rewrite from a monolithic `FROM ubuntu:24.04` image to a slim SSH-only layer `FROM repo-base:latest`. Remove core packages, user creation, and sudo setup (now in repo-base). Hardcode `devuser` in paths (per research recommendation).
- **Before:** Full 62-line file starting with `FROM ubuntu:24.04 AS base`, including ARGs (lines 12-14), core package install (lines 19-27), user/group creation (lines 34-46), WORKDIR (line 55).
- **After:**
```dockerfile
# syntax=docker/dockerfile:1

# Devenv Base Image
# Adds SSH server to repo-base for interactive development

FROM repo-base:latest AS base

LABEL devenv=true

USER root

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/sshd \
    && ssh-keygen -A

RUN mkdir -p /home/devuser/.ssh \
    && chmod 700 /home/devuser/.ssh

RUN chown -R devuser:devuser /home/devuser/.ssh

USER devuser

CMD ["/bin/bash"]
```
- **Note:** `USER root` is required because `repo-base:latest` ends with `USER devuser`. The privileged commands (`apt-get`, `ssh-keygen -A`, `mkdir /run/sshd`) need root. ARGs are not redeclared — `devuser` is hardcoded in paths per research recommendation (Open Decision #1).
- **Verification:** Build requires `repo-base:latest`. `docker build -f docker/devenv/Dockerfile.base -t devenv-base:latest .` succeeds. `docker run --rm devenv-base:latest which sshd` returns a path.

---

## Phase 3: Update Build Script

### Task 3 — Add `build_stage_repo_base()` function to `bin/build-devenv`

- **Files:** `bin/build-devenv:102` (insert before current `build_stage_base`)
- **Description:** Add a new function that builds `docker/base/Dockerfile.base` into `repo-base:<timestamp>` and `repo-base:latest`. Place it immediately before the existing `build_stage_base()`.
- **Before:** New function — does not exist.
- **After:**
```bash
# Build the repo-base image (shared foundation).
build_stage_repo_base() {
    log_info "Building repo-base image..."

    local dockerfile="${DEVENV_HOME}/docker/base/Dockerfile.base"
    if [[ ! -f "${dockerfile}" ]]; then
        die "Repo-base Dockerfile not found: ${dockerfile}"
    fi

    local version
    version=$(date +%Y%m%d.%H%M%S)

    log_info "Building repo-base:${version}..."
    docker build \
        -f "${dockerfile}" \
        -t "repo-base:${version}" \
        -t "repo-base:latest" \
        "${DEVENV_HOME}"

    log_info "Repo-base image built successfully: repo-base:${version}"
}
```
- **Verification:** `shellcheck bin/build-devenv` passes. `build-devenv --stage base` invokes this function.

### Task 4 — Rename `build_stage_base()` to `build_stage_devenv_base()` and update it

- **Files:** `bin/build-devenv:101-121`
- **Description:** Rename the existing `build_stage_base()` to `build_stage_devenv_base()`. Add an auto-build check for `repo-base:latest` at the top. The function continues to build `docker/devenv/Dockerfile.base` producing `devenv-base:*` tags.
- **Before:**
```bash
# Build the base image.
build_stage_base() {
    log_info "Building base image..."

    local dockerfile="${DEVENV_HOME}/docker/devenv/Dockerfile.base"
    if [[ ! -f "${dockerfile}" ]]; then
        die "Base Dockerfile not found: ${dockerfile}"
    fi

    local version
    version=$(date +%Y%m%d.%H%M%S)

    log_info "Building ${IMAGE_PREFIX}-base:${version}..."
    docker build \
        -f "${dockerfile}" \
        -t "${IMAGE_PREFIX}-base:${version}" \
        -t "${IMAGE_PREFIX}-base:latest" \
        "${DEVENV_HOME}"

    log_info "Base image built successfully: ${IMAGE_PREFIX}-base:${version}"
}
```
- **After:**
```bash
# Build the devenv-base image (SSH layer on top of repo-base).
build_stage_devenv_base() {
    log_info "Building devenv-base image..."

    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^repo-base:latest$"; then
        log_info "Repo-base image not found, building first..."
        build_stage_repo_base
    fi

    local dockerfile="${DEVENV_HOME}/docker/devenv/Dockerfile.base"
    if [[ ! -f "${dockerfile}" ]]; then
        die "Devenv-base Dockerfile not found: ${dockerfile}"
    fi

    local version
    version=$(date +%Y%m%d.%H%M%S)

    log_info "Building ${IMAGE_PREFIX}-base:${version}..."
    docker build \
        -f "${dockerfile}" \
        -t "${IMAGE_PREFIX}-base:${version}" \
        -t "${IMAGE_PREFIX}-base:latest" \
        "${DEVENV_HOME}"

    log_info "Devenv-base image built successfully: ${IMAGE_PREFIX}-base:${version}"
}
```
- **Verification:** `shellcheck bin/build-devenv` passes. `build-devenv --stage devenv-base` builds the chain.

### Task 5 — Update `build_stage_devenv()` auto-dependency chain

- **Files:** `bin/build-devenv:127-130`
- **Description:** Add a `repo-base:latest` check before the existing `devenv-base:latest` check. Both must be present before building the devenv image.
- **Before:**
```bash
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_PREFIX}-base:latest$"; then
        log_info "Base image not found, building first..."
        build_stage_base
    fi
```
- **After:**
```bash
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^repo-base:latest$"; then
        log_info "Repo-base image not found, building first..."
        build_stage_repo_base
    fi

    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_PREFIX}-base:latest$"; then
        log_info "Devenv-base image not found, building first..."
        build_stage_devenv_base
    fi
```
- **Verification:** `build-devenv --stage devenv` with no pre-existing images builds all three layers.

### Task 6 — Update `build_tool()` base image check

- **Files:** `bin/build-devenv:159-162`
- **Description:** Change the prerequisite image check from `devenv-base:latest` to `repo-base:latest`, and call `build_stage_repo_base` instead of `build_stage_base`.
- **Before:**
```bash
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_PREFIX}-base:latest$"; then
        log_info "Base image not found, building first..."
        build_stage_base
    fi
```
- **After:**
```bash
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^repo-base:latest$"; then
        log_info "Repo-base image not found, building first..."
        build_stage_repo_base
    fi
```
- **Verification:** `build-devenv --tool jq` auto-builds `repo-base` if missing.

### Task 7 — Update `build_tool()` inter-tool dependency check

- **Files:** `bin/build-devenv:165`
- **Description:** Change the tree-sitter dependency check from `devenv-tool-node:latest` to `tools-node:latest`.
- **Before:**
```bash
        if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE_PREFIX}-tool-node:latest$"; then
```
- **After:**
```bash
        if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^tools-node:latest$"; then
```
- **Verification:** `build-devenv --tool tree-sitter` auto-builds `tools-node:latest` if missing.

### Task 7b — Add `ripgrep -> jq` auto-dependency in `build_tool()`

- **Files:** `bin/build-devenv:164` (insert after the tree-sitter block)
- **Description:** Add a `ripgrep -> jq` auto-dependency check alongside the existing `tree-sitter -> node` check. The spec documents both inter-tool dependencies (ripgrep depends on jq, tree-sitter depends on node). The current build script only auto-resolves tree-sitter -> node. Without this, `build-devenv --tool ripgrep` fails if `tools-jq:latest` is absent.
- **Before:** No ripgrep dependency check exists.
- **After (insert after the tree-sitter block, before `log_info "Building tool: ${tool}..."`):**
```bash
    if [[ "${tool}" == "ripgrep" ]]; then
        if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^tools-jq:latest$"; then
            log_info "jq tool image not found, building first..."
            build_tool "jq"
        fi
    fi
```
- **Verification:** `build-devenv --tool ripgrep` with no `tools-jq:latest` present auto-builds jq first. `shellcheck bin/build-devenv` passes.

### Task 8 — Update `build_tool()` image tag and log message

- **Files:** `bin/build-devenv:174`, `bin/build-devenv:177`
- **Description:** Change the tool image tag from `${IMAGE_PREFIX}-tool-${tool}:latest` to `tools-${tool}:latest`.
- **Before (line 174):**
```bash
        -t "${IMAGE_PREFIX}-tool-${tool}:latest" \
```
- **After (line 174):**
```bash
        -t "tools-${tool}:latest" \
```
- **Before (line 177):**
```bash
    log_info "Tool image built successfully: ${IMAGE_PREFIX}-tool-${tool}:latest"
```
- **After (line 177):**
```bash
    log_info "Tool image built successfully: tools-${tool}:latest"
```
- **Verification:** `build-devenv --tool jq` produces `tools-jq:latest` tag. `docker images tools-jq` shows the image.

### Task 9 — Update stage dispatcher and usage text

- **Files:** `bin/build-devenv:31-32`, `bin/build-devenv:225-235`
- **Description:** Add `devenv-base` to the valid stages list in usage text. Remap `base)` to call `build_stage_repo_base`, add `devenv-base)` case to call `build_stage_devenv_base`. Update error message.
- **Before (usage, lines 31-32):**
```bash
    --stage <stage>      Build base or devenv stage
                         Valid stages: base, devenv
```
- **After (usage):**
```bash
    --stage <stage>      Build a stage image
                         Valid stages: base, devenv-base, devenv
```
- **Before (dispatcher, lines 225-235):**
```bash
                case "$1" in
                    base)
                        build_stage_base
                        ;;
                    devenv)
                        build_stage_devenv
                        ;;
                    *)
                        die "Invalid stage: $1. Valid stages: base, devenv"
                        ;;
                esac
```
- **After (dispatcher):**
```bash
                case "$1" in
                    base)
                        build_stage_repo_base
                        ;;
                    devenv-base)
                        build_stage_devenv_base
                        ;;
                    devenv)
                        build_stage_devenv
                        ;;
                    *)
                        die "Invalid stage: $1. Valid stages: base, devenv-base, devenv"
                        ;;
                esac
```
- **Before (line 223):**
```bash
                    die "--stage requires an argument (base or devenv)"
```
- **After (line 223):**
```bash
                    die "--stage requires an argument (base, devenv-base, or devenv)"
```
- **Verification:** `build-devenv --stage base` builds `repo-base:latest`. `build-devenv --stage devenv-base` builds `devenv-base:latest`. `build-devenv --help` lists all three stages. `shellcheck bin/build-devenv` passes.

---

## Phase 4: Update Shared Tool Dockerfiles

### Task 10 — Update 11 standard tool Dockerfiles (FROM and LABEL)

- **Files (each gets two edits — FROM and LABEL):**
  - `shared/tools/Dockerfile.cargo:6` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.cargo:7` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.common-utils:6` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.common-utils:7` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.copilot-cli:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.copilot-cli:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.fnm:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.fnm:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.gh:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.gh:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.go:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.go:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.nvim:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.nvim:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.opencode:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.opencode:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.starship:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.starship:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.uv:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.uv:6` — `LABEL devenv=true` -> `LABEL tools=true`
  - `shared/tools/Dockerfile.yq:5` — `FROM devenv-base:latest` -> `FROM repo-base:latest`
  - `shared/tools/Dockerfile.yq:6` — `LABEL devenv=true` -> `LABEL tools=true`
- **Description:** Mechanical find-and-replace in each file. Change base FROM from `devenv-base:latest` to `repo-base:latest` and label from `LABEL devenv=true` to `LABEL tools=true`.
- **Before (example, Dockerfile.cargo):**
```dockerfile
FROM devenv-base:latest AS tool_cargo
LABEL devenv=true
```
- **After (example, Dockerfile.cargo):**
```dockerfile
FROM repo-base:latest AS tool_cargo
LABEL tools=true
```
- **Verification:** `grep -rn 'FROM devenv-base' shared/tools/` returns zero matches. `grep -rn 'LABEL devenv=true' shared/tools/` returns zero matches (except the jq_source stage on Dockerfile.jq line 6 which is an external image alias — see Task 11).

### Task 11 — Update `shared/tools/Dockerfile.fzf` (FROM, add LABEL, fix coding standard)

- **Files:** `shared/tools/Dockerfile.fzf:3`
- **Description:** This file has no LABEL line and is missing `USER devuser` at the end (coding standard violation). Change FROM, add `LABEL tools=true`, and add `USER devuser` as the final instruction.
- **Before:**
```dockerfile
FROM devenv-base:latest AS tool_fzf
```
- **After:**
```dockerfile
FROM repo-base:latest AS tool_fzf
LABEL tools=true
```
- **Additional fix (end of file):** Add `USER devuser` as the final instruction to comply with Execution Rule #4 (coding-standard.md 2.2). The current file ends with `ENV PATH=...` on line 10.
- **Verification:** `grep 'LABEL tools=true' shared/tools/Dockerfile.fzf` matches. File ends with `USER devuser`.

### Task 12 — Update `shared/tools/Dockerfile.jq` (FROM and LABEL)

- **Files:** `shared/tools/Dockerfile.jq:7-8`
- **Description:** Change the `tool_jq` stage FROM and LABEL. The `jq_source` stage (line 5-6) is unchanged — it references an external image. Note: line 6 has `LABEL devenv=true` on the jq_source stage; change it to `LABEL tools=true` as well since it's part of this standalone tool image.
- **Before:**
```dockerfile
FROM ghcr.io/jqlang/jq:latest AS jq_source
LABEL devenv=true
FROM devenv-base:latest AS tool_jq
LABEL devenv=true
```
- **After:**
```dockerfile
FROM ghcr.io/jqlang/jq:latest AS jq_source
LABEL tools=true
FROM repo-base:latest AS tool_jq
LABEL tools=true
```
- **Verification:** `build-devenv --tool jq` succeeds.

### Task 13 — Update `shared/tools/Dockerfile.node` (two FROM lines and LABEL)

- **Files:** `shared/tools/Dockerfile.node:6-7`, `shared/tools/Dockerfile.node:15-16`
- **Description:** Change both `FROM devenv-base:latest` lines and both `LABEL devenv=true` lines.
- **Before:**
```dockerfile
FROM devenv-base:latest AS tool_fnm_stage
LABEL devenv=true
...
FROM devenv-base:latest AS tool_node
LABEL devenv=true
```
- **After:**
```dockerfile
FROM repo-base:latest AS tool_fnm_stage
LABEL tools=true
...
FROM repo-base:latest AS tool_node
LABEL tools=true
```
- **Verification:** `build-devenv --tool node` succeeds.

### Task 14 — Update `shared/tools/Dockerfile.ripgrep` (inter-tool FROM, base FROM, LABEL)

- **Files:** `shared/tools/Dockerfile.ripgrep:7-9`
- **Description:** Change inter-tool FROM from `devenv-tool-jq:latest` to `tools-jq:latest`. Change base FROM from `devenv-base:latest` to `repo-base:latest`. Change LABEL.
- **Before:**
```dockerfile
FROM devenv-tool-jq:latest AS jq_source
FROM devenv-base:latest AS tool_ripgrep
LABEL devenv=true
```
- **After:**
```dockerfile
FROM tools-jq:latest AS jq_source
FROM repo-base:latest AS tool_ripgrep
LABEL tools=true
```
- **Verification:** `build-devenv --tool ripgrep` succeeds (requires `tools-jq:latest`).

### Task 15 — Update `shared/tools/Dockerfile.tree-sitter` (inter-tool FROM, base FROM, LABELs)

- **Files:** `shared/tools/Dockerfile.tree-sitter:6-10`
- **Description:** Change inter-tool FROM from `devenv-tool-node:latest` to `tools-node:latest`. Change base FROM from `devenv-base:latest` to `repo-base:latest`. Change both LABEL lines.
- **Before:**
```dockerfile
FROM devenv-tool-node:latest AS tool_node
LABEL devenv=true

FROM devenv-base:latest AS tool_tree_sitter
LABEL devenv=true
```
- **After:**
```dockerfile
FROM tools-node:latest AS tool_node
LABEL tools=true

FROM repo-base:latest AS tool_tree_sitter
LABEL tools=true
```
- **Verification:** `build-devenv --tool tree-sitter` succeeds (requires `tools-node:latest`).

---

## Phase 5: Update Devenv Multi-Stage Dockerfile

### Task 16 — Update 15 inline tool stage FROM lines in `docker/devenv/Dockerfile.devenv`

- **Files:** `docker/devenv/Dockerfile.devenv` at lines: 29, 35, 43, 51, 58, 63, 69, 88, 108, 121, 129, 139, 143, 147, 152
- **Description:** Change all 15 inline tool `FROM devenv-base:latest AS tool_*` lines to `FROM repo-base:latest AS tool_*`. Lines 7 and 10 (devenv-base and common_utils stages) are NOT changed. Line 162 (final stage) is NOT changed.
- **Before (each line):**
```dockerfile
FROM devenv-base:latest AS tool_<name>
```
- **After (each line):**
```dockerfile
FROM repo-base:latest AS tool_<name>
```
- **Full list of changes:**
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
- **Verification:** `grep -n 'FROM devenv-base:latest AS tool_' docker/devenv/Dockerfile.devenv` returns zero matches. Lines 7 and 10 still reference `devenv-base:latest` (correct).

---

## Phase 6: Update Documentation

### Task 17 — Update `CONTRIBUTING.md` for new image hierarchy and naming

- **Files:** `CONTRIBUTING.md`
- **Description:** Update stale references to the old image naming and label conventions. The migration changes tool base images from `devenv-base:latest` to `repo-base:latest`, tool labels from `LABEL devenv=true` to `LABEL tools=true`, standalone tool tags from `devenv-tool-<name>:latest` to `tools-<name>:latest`, and introduces the three-layer build chain.
- **Changes:**
  1. **Architecture overview (line 16):** Update the tree to show the new `docker/base/Dockerfile.base` layer above `docker/devenv/Dockerfile.base`.
  2. **Step 1 tool Dockerfile template (lines 45-46):** Change `FROM devenv-base:latest AS tool_<toolname>` to `FROM repo-base:latest AS tool_<toolname>`. Change `LABEL devenv=true` to `LABEL tools=true`.
  3. **Rules (line 62):** Change "`LABEL devenv=true` is required" to "`LABEL tools=true` is required" (for tool Dockerfiles).
  4. **Reference examples table (line 79):** Change `devenv-tool-jq:latest` to `tools-jq:latest`.
  5. **Step 2 inline stage template (line 89):** Change `FROM devenv-base:latest AS tool_<toolname>` to `FROM repo-base:latest AS tool_<toolname>`.
  6. **Section 5 procedure (lines 407-410):** Update `build-devenv --stage base` description to note it builds `repo-base:latest`. Add `build-devenv --stage devenv-base` step.
  7. **Checklist (line 426):** Change "All images have `LABEL devenv=true`" to "Tool images have `LABEL tools=true`, environment images have `LABEL devenv=true`, repo-base has `LABEL repo-base=true`".
  8. **Checklist (line 440):** Update full rebuild command to `build-devenv --stage base && build-devenv --stage devenv-base && build-devenv --stage devenv`.
- **Verification:** `grep -n 'devenv-tool-' CONTRIBUTING.md` returns zero matches. `grep -n 'FROM devenv-base:latest AS tool_' CONTRIBUTING.md` returns zero matches.

### Task 18 — Update `specs/devenv-architecture.md` for new tool naming

- **Files:** `specs/devenv-architecture.md`
- **Description:** Update stale references to old standalone tool image naming convention.
- **Changes:**
  1. **Line 137:** Change `FROM devenv-base:latest AS tool_<name>` to `FROM repo-base:latest AS tool_<name>`.
  2. **Line 172:** Change `COPY --from=devenv-tool-jq:latest` to `COPY --from=tools-jq:latest`.
  3. **Line 235:** Change `FROM devenv-base:latest AS tool_<name>` to `FROM repo-base:latest AS tool_<name>`.
  4. **Line 423:** Change "tag as `devenv-tool-<name>:latest`" to "tag as `tools-<name>:latest`".
  5. **Line 432:** Change `devenv-tool-cargo:latest` to `tools-cargo:latest`.
- **Note:** This spec predates the multi-environment architecture spec. These updates bring it into alignment with the current architecture. The authoritative spec for the multi-environment architecture is `specs/multi-environment-architecture.md`.
- **Verification:** `grep -n 'devenv-tool-' specs/devenv-architecture.md` returns zero matches. `grep -n 'FROM devenv-base:latest AS tool_' specs/devenv-architecture.md` returns zero matches.

### Task 19 — Update `specs/coding-standard.md` label taxonomy

- **Files:** `specs/coding-standard.md:352`
- **Description:** Update the label documentation to reflect the new three-label taxonomy.
- **Before (line 352):**
```
**Labels:** All devenv images carry `LABEL devenv=true`.
```
- **After:**
```
**Labels:** Images carry labels by type: `LABEL repo-base=true` for the shared foundation, `LABEL devenv=true` for devenv environment images, and `LABEL tools=true` for standalone tool images.
```
- **Verification:** `grep 'LABEL' specs/coding-standard.md` shows the updated taxonomy.

---

## Verification Plan

1. **Shellcheck:** `shellcheck bin/build-devenv` — zero warnings.
2. **Stage chain build:**
   - `build-devenv --stage base` — produces `repo-base:latest`
   - `build-devenv --stage devenv-base` — auto-builds `repo-base` if missing, produces `devenv-base:latest`
   - `build-devenv --stage devenv` — auto-builds full chain, produces `devenv:latest`
3. **Standalone tool build:** `build-devenv --tool jq` — produces `tools-jq:latest` (not `devenv-tool-jq:latest`).
4. **Inter-tool dependencies:**
   - `build-devenv --tool tree-sitter` — auto-builds `tools-node:latest` if missing.
   - `build-devenv --tool ripgrep` — auto-builds `tools-jq:latest` if missing.
5. **Project build:** `build-devenv --project <path>` — auto-builds full `repo-base` -> `devenv-base` -> `devenv` chain.
6. **Runtime:** `bin/devenv .` — unchanged behavior, container starts and attaches.
7. **Image labels:**
   - `docker inspect repo-base:latest` — has `repo-base=true`
   - `docker inspect devenv-base:latest` — has `devenv=true`
   - `docker inspect tools-jq:latest` — has `tools=true`
8. **No stale references in code:** `grep -rn 'devenv-tool-' shared/tools/ bin/build-devenv docker/` returns zero matches. `grep -rn 'FROM devenv-base:latest AS tool_' docker/devenv/Dockerfile.devenv shared/tools/` returns zero matches.
9. **No stale references in docs:** `grep -rn 'devenv-tool-' CONTRIBUTING.md specs/devenv-architecture.md specs/coding-standard.md` returns zero matches. `grep -rn 'FROM devenv-base:latest AS tool_' CONTRIBUTING.md specs/devenv-architecture.md` returns zero matches.
10. **Dockerfile.fzf coding standard:** `shared/tools/Dockerfile.fzf` ends with `USER devuser`.

---

## External References

- `specs/multi-environment-architecture.md` — authoritative specification
- `specs/coding-standard.md` — code quality rules
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) — bash baseline
- [Docker best practices](https://docs.docker.com/build/building/best-practices/) — Dockerfile baseline

---

## Completion Checklist

- [ ] `docker/base/Dockerfile.base` exists with `LABEL repo-base=true`
- [ ] `docker/devenv/Dockerfile.base` builds `FROM repo-base:latest`, includes `USER root` before privileged commands, SSH only
- [ ] `bin/build-devenv` has `build_stage_repo_base()` and `build_stage_devenv_base()` functions
- [ ] `bin/build-devenv --stage base` builds `repo-base:latest`
- [ ] `bin/build-devenv --stage devenv-base` builds `devenv-base:latest`
- [ ] Auto-dependency chain: `devenv` -> `devenv-base` -> `repo-base`
- [ ] All 16 `shared/tools/Dockerfile.*` use `FROM repo-base:latest` and `LABEL tools=true`
- [ ] `Dockerfile.fzf` ends with `USER devuser` (coding standard fix)
- [ ] `Dockerfile.ripgrep` references `tools-jq:latest` (not `devenv-tool-jq`)
- [ ] `Dockerfile.tree-sitter` references `tools-node:latest` (not `devenv-tool-node`)
- [ ] `build_tool()` auto-resolves both `ripgrep -> jq` and `tree-sitter -> node` dependencies
- [ ] Standalone tools tagged as `tools-<name>:latest` (not `devenv-tool-<name>`)
- [ ] All 15 inline tool stages in `Dockerfile.devenv` use `FROM repo-base:latest`
- [ ] `common_utils` and final `devenv` stage in `Dockerfile.devenv` unchanged
- [ ] `bin/devenv` unchanged
- [ ] `shellcheck bin/build-devenv` passes
- [ ] Full build chain succeeds: `--stage base` -> `--stage devenv-base` -> `--stage devenv`
- [ ] `CONTRIBUTING.md` updated: no `devenv-tool-*` or `FROM devenv-base:latest AS tool_` references
- [ ] `specs/devenv-architecture.md` updated: no `devenv-tool-*` or `FROM devenv-base:latest AS tool_` references
- [ ] `specs/coding-standard.md` updated: label taxonomy reflects `repo-base=true`, `devenv=true`, `tools=true`

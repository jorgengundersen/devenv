# Research: Multi-Environment Architecture Gap Analysis

**Spec:** `specs/multi-environment-architecture.md` (409 lines)

**Files analyzed:**

| File | Lines |
|------|------:|
| `docker/devenv/Dockerfile.base` | 62 |
| `docker/devenv/Dockerfile.devenv` | 230 |
| `docker/devenv/templates/Dockerfile.project` | 21 |
| `docker/devenv/templates/Dockerfile.python-uv` | 32 |
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
| `bin/build-devenv` | 270 |
| `bin/devenv` | 631 |
| `scripts/install-devenv` | 158 |
| `shared/bash/log.sh` | 37 |

---

## Current State Snapshot

The codebase is a single-environment (devenv) containerized development setup. There is no `docker/base/` directory and no `repo-base` image. The current image hierarchy is:

```
ubuntu:24.04
  └─ devenv-base:latest   (docker/devenv/Dockerfile.base)
       └─ devenv:latest   (docker/devenv/Dockerfile.devenv)
            └─ devenv-project-*:latest
```

`docker/devenv/Dockerfile.base` serves as the **only** base image. It builds directly `FROM ubuntu:24.04` and bundles **everything** the spec splits between `repo-base` and `devenv-base`: core packages, SSH server, user creation, and SSH directory setup.

All 16 tool Dockerfiles in `shared/tools/` use `FROM devenv-base:latest`. The two with inter-tool dependencies use `devenv-tool-<name>:latest` tag convention. The build script (`bin/build-devenv`) tags standalone tool images as `devenv-tool-<name>:latest` and has `--stage base` mapped to `docker/devenv/Dockerfile.base` producing `devenv-base:latest`.

---

## Gap Analysis Matrix

| # | Spec Requirement | Current State | Gap Type | Required Action |
|---|-----------------|---------------|----------|-----------------|
| 1 | `docker/base/Dockerfile.base` exists as repo-base (Ubuntu + user + core packages, no SSH) | Does not exist. `docker/base/` directory absent. | **NEW** | Create `docker/base/Dockerfile.base` with Ubuntu 24.04, core packages (ca-certificates, curl, git, sudo, wget), user creation, sudo setup. No SSH. Label `repo-base=true`. |
| 2 | `repo-base:latest` image name with timestamp tags | No such image. Only `devenv-base:latest` exists. | **NEW** | Build script must produce `repo-base:<timestamp>` and `repo-base:latest`. |
| 3 | `docker/devenv/Dockerfile.base` builds `FROM repo-base:latest` and adds SSH only | Builds `FROM ubuntu:24.04` and includes SSH + core packages + user creation (lines 6-61). | **UPDATE** | Rewrite to `FROM repo-base:latest`; keep only SSH-specific steps (install openssh-client/server, configure sshd, prepare .ssh dir). Remove core packages, user creation, and sudo setup (now in repo-base). |
| 4 | `devenv-base:latest` label is `devenv=true` | Already has `LABEL devenv=true` (line 9). | **NO CHANGE** | — |
| 5 | `docker/devenv/Dockerfile.devenv` tool stages use `FROM repo-base:latest` instead of `FROM devenv-base:latest` | All inline tool stages (lines 29, 35, 43, 51, 58, 63, 69, 88, 108, 121, 129, 139, 143, 147, 152) use `FROM devenv-base:latest`. | **UPDATE** | Change 15 inline `FROM devenv-base:latest AS tool_*` lines to `FROM repo-base:latest AS tool_*`. |
| 6 | `Dockerfile.devenv` `common_utils` stage stays `FROM devenv-base:latest` | `common_utils` at line 10: `FROM devenv-base:latest AS common_utils`. | **NO CHANGE** | — |
| 7 | `Dockerfile.devenv` final stage stays `FROM common_utils AS devenv` | Line 162: `FROM common_utils AS devenv`. | **NO CHANGE** | — |
| 8 | All 16 `shared/tools/Dockerfile.*` base FROM changes `devenv-base:latest` -> `repo-base:latest` | All use `FROM devenv-base:latest`. | **UPDATE** | Change base `FROM devenv-base:latest` to `FROM repo-base:latest` in all 16 files (18 FROM statements total that reference `devenv-base`). |
| 9 | `shared/tools/Dockerfile.ripgrep` inter-tool FROM: `devenv-tool-jq:latest` -> `tools-jq:latest` | Line 7: `FROM devenv-tool-jq:latest AS jq_source`. | **UPDATE** | Change to `FROM tools-jq:latest AS jq_source`. |
| 10 | `shared/tools/Dockerfile.tree-sitter` inter-tool FROM: `devenv-tool-node:latest` -> `tools-node:latest` | Line 6: `FROM devenv-tool-node:latest AS tool_node`. | **UPDATE** | Change to `FROM tools-node:latest AS tool_node`. |
| 11 | Standalone tool image tag: `tools-<name>:latest` (was `devenv-tool-<name>:latest`) | `bin/build-devenv` line 174: tags as `devenv-tool-${tool}:latest`. | **UPDATE** | Change tag from `${IMAGE_PREFIX}-tool-${tool}:latest` to `tools-${tool}:latest` at line 174. |
| 12 | Build script inter-tool dependency check uses `tools-node:latest` | Line 165: checks for `devenv-tool-node:latest`. | **UPDATE** | Change to `tools-node:latest`. |
| 13 | `--stage base` builds `docker/base/Dockerfile.base` -> `repo-base:latest` | `--stage base` currently builds `docker/devenv/Dockerfile.base` -> `devenv-base:latest` (line 105, 114-117). | **UPDATE** | Remap `--stage base` to build `docker/base/Dockerfile.base` producing `repo-base:latest`. |
| 14 | `--stage devenv-base` builds `docker/devenv/Dockerfile.base` -> `devenv-base:latest` | No `devenv-base` stage exists; `base` serves this role. | **NEW** | Add `devenv-base` case to the stage dispatcher. Wire to `docker/devenv/Dockerfile.base`. Auto-build `repo-base` if missing. |
| 15 | `--stage devenv` auto-builds `repo-base` and `devenv-base` if missing | Currently only auto-builds `devenv-base` (lines 127-130). | **UPDATE** | Add `repo-base` to the auto-dependency chain for `--stage devenv`. |
| 16 | `--tool <name>` auto-builds `repo-base` if missing | Currently auto-builds `devenv-base` (lines 159-162). | **UPDATE** | Change dependency check from `devenv-base:latest` to `repo-base:latest`. |
| 17 | `repo-base:latest` uses timestamp + latest tagging | `build_stage_base` produces `devenv-base:<timestamp>` and `devenv-base:latest`. | **UPDATE** | New `build_stage_base` produces `repo-base:<timestamp>` and `repo-base:latest`. Current base-building logic becomes `build_stage_devenv_base`. |
| 18 | Usage text in `build-devenv` lists stages: `base`, `devenv-base`, `devenv` | Usage (lines 31-32) lists: `base, devenv`. | **UPDATE** | Add `devenv-base` to valid stages in usage text. |
| 19 | `bin/devenv` runtime is unchanged | Runtime launcher in `bin/devenv` (631 lines). | **NO CHANGE** | — |
| 20 | `scripts/install-devenv` unchanged | 158 lines, symlinks `build-devenv` and `devenv`. | **NO CHANGE** | — |
| 21 | `shared/bash/log.sh` unchanged | 37 lines, logging library. | **NO CHANGE** | — |
| 22 | `docker/devenv/templates/` unchanged | `Dockerfile.project` and `Dockerfile.python-uv` extend `devenv:latest`. | **NO CHANGE** | — |
| 23 | Persistent volumes per-environment (devenv keeps its own) | Devenv volumes are `devenv-data`, `devenv-cache`, `devenv-state`. | **NO CHANGE** | — |
| 24 | Directory structure: `docker/base/` directory | Does not exist. | **NEW** | Create `docker/base/` directory. |
| 25 | Project auto-build: `--project <path>` resolves full chain for detected env type | Currently auto-builds `devenv:latest` chain only (lines 191-194). | **UPDATE** | Must auto-build `repo-base` -> `devenv-base` -> `devenv` chain. Currently missing `repo-base` step. |
| 26 | `repo-base` label: `repo-base=true` | N/A — image doesn't exist. | **NEW** | Include `LABEL repo-base=true` in `docker/base/Dockerfile.base`. |

---

## File-Level Change Map

### Files that change

#### 1. `docker/base/Dockerfile.base` — **NEW** (0 -> ~30 lines)

- Nature: **NEW** file.
- Content: `FROM ubuntu:24.04`, `LABEL repo-base=true`, ARGs for USERNAME/USER_UID/USER_GID, install ca-certificates/curl/git/sudo/wget, create user + sudo, WORKDIR, USER, CMD.
- Dependencies: None (root of the build chain).

#### 2. `docker/devenv/Dockerfile.base` — **UPDATE** (62 lines)

| Lines | Current | Target | Change |
|-------|---------|--------|--------|
| 6 | `FROM ubuntu:24.04 AS base` | `FROM repo-base:latest AS base` | UPDATE |
| 9 | `LABEL devenv=true` | Keep | NO CHANGE |
| 11-14 | ARG USERNAME, USER_UID, USER_GID | Remove (inherited from repo-base) | REMOVE |
| 16 | `ENV DEBIAN_FRONTEND=noninteractive` | Keep (needed for apt in this layer) | NO CHANGE |
| 19-27 | apt-get install of ca-certificates, curl, git, openssh-client, openssh-server, sudo, wget | Reduce to openssh-client + openssh-server only | UPDATE |
| 29-30 | `mkdir -p /run/sshd && ssh-keygen -A` | Keep | NO CHANGE |
| 34-46 | User/group creation + sudo setup | Remove entirely (in repo-base now) | REMOVE |
| 49-50 | SSH directory setup | Keep | NO CHANGE |
| 52 | `chown` SSH directory | Keep | NO CHANGE |
| 55 | `WORKDIR /home/${USERNAME}` | Remove or keep (inherited from repo-base) | REMOVE |
| 58 | `USER ${USERNAME}` | Keep | NO CHANGE |
| 61 | `CMD ["/bin/bash"]` | Keep | NO CHANGE |

- Dependencies: Requires `repo-base:latest` to exist.
- Estimated result: ~20 lines.

#### 3. `docker/devenv/Dockerfile.devenv` — **UPDATE** (230 lines)

| Lines | Current | Target | Change |
|-------|---------|--------|--------|
| 7 | `FROM devenv-base:latest AS devenv-base` | Keep (unused alias, harmless) or remove | NO CHANGE |
| 10 | `FROM devenv-base:latest AS common_utils` | Keep | NO CHANGE |
| 29 | `FROM devenv-base:latest AS tool_cargo` | `FROM repo-base:latest AS tool_cargo` | UPDATE |
| 35 | `FROM devenv-base:latest AS tool_go` | `FROM repo-base:latest AS tool_go` | UPDATE |
| 43 | `FROM devenv-base:latest AS tool_fnm` | `FROM repo-base:latest AS tool_fnm` | UPDATE |
| 51 | `FROM devenv-base:latest AS tool_uv` | `FROM repo-base:latest AS tool_uv` | UPDATE |
| 58 | `FROM devenv-base:latest AS tool_fzf` | `FROM repo-base:latest AS tool_fzf` | UPDATE |
| 63 | `FROM devenv-base:latest AS tool_jq` | `FROM repo-base:latest AS tool_jq` | UPDATE |
| 69 | `FROM devenv-base:latest AS tool_node` | `FROM repo-base:latest AS tool_node` | UPDATE |
| 88 | `FROM devenv-base:latest AS tool_ripgrep` | `FROM repo-base:latest AS tool_ripgrep` | UPDATE |
| 108 | `FROM devenv-base:latest AS tool_gh` | `FROM repo-base:latest AS tool_gh` | UPDATE |
| 121 | `FROM devenv-base:latest AS tool_nvim` | `FROM repo-base:latest AS tool_nvim` | UPDATE |
| 129 | `FROM devenv-base:latest AS tool_opencode` | `FROM repo-base:latest AS tool_opencode` | UPDATE |
| 139 | `FROM devenv-base:latest AS tool_copilot-cli` | `FROM repo-base:latest AS tool_copilot-cli` | UPDATE |
| 143 | `FROM devenv-base:latest AS tool_starship` | `FROM repo-base:latest AS tool_starship` | UPDATE |
| 147 | `FROM devenv-base:latest AS tool_yq` | `FROM repo-base:latest AS tool_yq` | UPDATE |
| 152 | `FROM devenv-base:latest AS tool_tree_sitter` | `FROM repo-base:latest AS tool_tree_sitter` | UPDATE |
| 162 | `FROM common_utils AS devenv` | Keep | NO CHANGE |

- 15 FROM lines change. All other lines remain unchanged.
- Dependencies: Requires both `repo-base:latest` and `devenv-base:latest`.

#### 4. `shared/tools/Dockerfile.cargo` — **UPDATE** (23 lines)

- Line 6: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 5. `shared/tools/Dockerfile.common-utils` — **UPDATE** (28 lines)

- Line 6: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 6. `shared/tools/Dockerfile.copilot-cli` — **UPDATE** (14 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 7. `shared/tools/Dockerfile.fnm` — **UPDATE** (21 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 8. `shared/tools/Dockerfile.fzf` — **UPDATE** (11 lines)

- Line 3: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 9. `shared/tools/Dockerfile.gh` — **UPDATE** (23 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 10. `shared/tools/Dockerfile.go` — **UPDATE** (21 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 11. `shared/tools/Dockerfile.jq` — **UPDATE** (20 lines)

- Line 7: `FROM devenv-base:latest` -> `FROM repo-base:latest`.
- Line 5 (`FROM ghcr.io/jqlang/jq:latest AS jq_source`): NO CHANGE (external image, not affected).

#### 12. `shared/tools/Dockerfile.node` — **UPDATE** (46 lines)

- Line 6: `FROM devenv-base:latest AS tool_fnm_stage` -> `FROM repo-base:latest AS tool_fnm_stage`.
- Line 15: `FROM devenv-base:latest AS tool_node` -> `FROM repo-base:latest AS tool_node`.

#### 13. `shared/tools/Dockerfile.nvim` — **UPDATE** (24 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 14. `shared/tools/Dockerfile.opencode` — **UPDATE** (14 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 15. `shared/tools/Dockerfile.ripgrep` — **UPDATE** (23 lines)

- Line 7: `FROM devenv-tool-jq:latest AS jq_source` -> `FROM tools-jq:latest AS jq_source`.
- Line 8: `FROM devenv-base:latest AS tool_ripgrep` -> `FROM repo-base:latest AS tool_ripgrep`.

#### 16. `shared/tools/Dockerfile.starship` — **UPDATE** (17 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 17. `shared/tools/Dockerfile.tree-sitter` — **UPDATE** (25 lines)

- Line 6: `FROM devenv-tool-node:latest AS tool_node` -> `FROM tools-node:latest AS tool_node`.
- Line 9: `FROM devenv-base:latest AS tool_tree_sitter` -> `FROM repo-base:latest AS tool_tree_sitter`.

#### 18. `shared/tools/Dockerfile.uv` — **UPDATE** (20 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 19. `shared/tools/Dockerfile.yq` — **UPDATE** (16 lines)

- Line 5: `FROM devenv-base:latest` -> `FROM repo-base:latest`.

#### 20. `bin/build-devenv` — **UPDATE** (270 lines)

| Lines | Current | Target | Change |
|-------|---------|--------|--------|
| 31-32 | Usage lists stages: `base, devenv` | Add `devenv-base` | UPDATE |
| 34 | Tool list in usage | Keep (unchanged) | NO CHANGE |
| 102-121 | `build_stage_base()` builds `docker/devenv/Dockerfile.base` -> `devenv-base:*` | Rename to `build_stage_devenv_base()`; builds `docker/devenv/Dockerfile.base` -> `devenv-base:*`. Auto-builds `repo-base` if missing. | UPDATE |
| N/A | No `build_stage_base()` for repo-base | New function: builds `docker/base/Dockerfile.base` -> `repo-base:*` | NEW |
| 124-148 | `build_stage_devenv()` auto-builds base (devenv-base) if missing | Auto-build both `repo-base` and `devenv-base` if missing | UPDATE |
| 159-162 | `build_tool()` checks for `devenv-base:latest` | Check for `repo-base:latest` instead | UPDATE |
| 164-168 | `build_tool()` checks `devenv-tool-node:latest` for tree-sitter dep | Check for `tools-node:latest` | UPDATE |
| 174 | Tags tool as `devenv-tool-${tool}:latest` | Tag as `tools-${tool}:latest` | UPDATE |
| 177 | Log message: `devenv-tool-${tool}:latest` | Update to `tools-${tool}:latest` | UPDATE |
| 191-194 | `build_project()` auto-builds `devenv:latest` only | Chain: auto-build `repo-base` -> `devenv-base` -> `devenv` | UPDATE |
| 225-235 | Stage dispatch: `base)` and `devenv)` cases | Add `devenv-base)` case; remap `base)` to repo-base | UPDATE |
| 233 | Error message for invalid stage | Add `devenv-base` to valid stages list | UPDATE |

### Files that do NOT change

| File | Reason |
|------|--------|
| `bin/devenv` (631 lines) | Spec explicitly states runtime is unchanged. |
| `scripts/install-devenv` (158 lines) | Only symlinks `build-devenv` and `devenv`; no structural changes needed for this spec. |
| `shared/bash/log.sh` (37 lines) | Logging library; no spec requirements affect it. |
| `docker/devenv/templates/Dockerfile.project` (21 lines) | Extends `devenv:latest`; unchanged. |
| `docker/devenv/templates/Dockerfile.python-uv` (32 lines) | Extends `devenv:latest`; unchanged. |
| `docker/devenv/templates/README.md` | Template documentation; unaffected. |

---

## Function/Block-Level Detail

### `bin/build-devenv` — `build_stage_base()` (lines 102-121)

**Current behavior:** Builds `docker/devenv/Dockerfile.base` into `devenv-base:<timestamp>` and `devenv-base:latest`.

**Target behavior:** This function is split into two:

1. **New `build_stage_repo_base()`** — builds `docker/base/Dockerfile.base` into `repo-base:<timestamp>` and `repo-base:latest`.
2. **Renamed `build_stage_devenv_base()`** — builds `docker/devenv/Dockerfile.base` into `devenv-base:<timestamp>` and `devenv-base:latest`. Auto-builds `repo-base` if `repo-base:latest` is not present.

**Lines affected:** 102-121 (full replacement of `build_stage_base`).

**New function to add:** `build_stage_repo_base()` (~20 lines), placed before `build_stage_devenv_base()`.

### `bin/build-devenv` — `build_stage_devenv()` (lines 124-148)

**Current behavior:** Auto-builds `devenv-base` if missing (lines 127-130), then builds `Dockerfile.devenv`.

**Target behavior:** Auto-build chain: check `repo-base:latest`, then `devenv-base:latest`, then build `Dockerfile.devenv`.

**Lines affected:** 127-130 (add `repo-base` check before `devenv-base` check).

### `bin/build-devenv` — `build_tool()` (lines 151-178)

**Current behavior:**
- Lines 159-162: Checks for `devenv-base:latest` before building any tool.
- Lines 164-168: Checks for `devenv-tool-node:latest` before building tree-sitter.
- Line 174: Tags as `devenv-tool-${tool}:latest`.

**Target behavior:**
- Check for `repo-base:latest` instead of `devenv-base:latest`.
- Check for `tools-node:latest` instead of `devenv-tool-node:latest`.
- Tag as `tools-${tool}:latest`.

**Lines affected:** 159, 161, 165, 174, 177.

### `bin/build-devenv` — `main()` stage dispatcher (lines 225-235)

**Current behavior:** Dispatches `base` -> `build_stage_base()`, `devenv` -> `build_stage_devenv()`.

**Target behavior:** Dispatches `base` -> `build_stage_repo_base()`, `devenv-base` -> `build_stage_devenv_base()`, `devenv` -> `build_stage_devenv()`.

**Lines affected:** 225-235 (add `devenv-base)` case, update `base)` case).

### `docker/devenv/Dockerfile.base` — full file (62 lines)

**Current behavior:** Monolithic base image from `ubuntu:24.04`. Installs core packages + SSH + user creation.

**Target behavior:** Slim SSH-only layer from `repo-base:latest`. The file shrinks to approximately:
```dockerfile
# syntax=docker/dockerfile:1
FROM repo-base:latest AS base
LABEL devenv=true
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-client \
    openssh-server \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/sshd && ssh-keygen -A
RUN mkdir -p /home/devuser/.ssh && chmod 700 /home/devuser/.ssh
RUN chown -R devuser:devuser /home/devuser/.ssh
USER devuser
CMD ["/bin/bash"]
```

**Lines removed:** 11-14 (ARGs), 19-27 (core packages — reduced), 34-46 (user creation).

---

## Edge Cases and Tradeoffs

| Scenario | Handling |
|----------|----------|
| **Build order violation:** Building `devenv-base` without `repo-base` present | `build_stage_devenv_base()` must auto-build `repo-base` first (same pattern as current `devenv` auto-building `base`). |
| **Stale `repo-base`:** User rebuilds `devenv-base` but `repo-base` is outdated | Not a new concern — same risk exists today with `devenv-base` vs `devenv`. No new mitigation needed. |
| **Existing `devenv-tool-*` images on user machines:** After migration, old tags are orphaned | Build script no longer produces `devenv-tool-*` tags. Users with old images have dangling tags. Recommendation: document in changelog. No automated cleanup needed. |
| **`docker/devenv/Dockerfile.base` ARG inheritance:** `repo-base` uses `ARG USERNAME=devuser` but child image needs the value | Dockerfile ARGs don't cross FROM boundaries. The child Dockerfile must either: (a) hardcode `devuser`, or (b) redeclare the ARG with the same default. Since the spec hardcodes `devuser` in SSH dir paths, hardcoding is acceptable and simpler. |
| **`repo-base` label vs `devenv` label:** `repo-base` uses `LABEL repo-base=true`, devenv images use `LABEL devenv=true` | These are distinct labels. `repo-base` is filtered separately from devenv images. No conflict. |
| **Tool Dockerfile `LABEL devenv=true`:** Some shared tools still carry `devenv=true` | Spec doesn't address tool labels. Tools are shared across environments, so `devenv=true` is inaccurate. Consider changing to a neutral label in the future, but this is outside scope of this spec. |
| **`Dockerfile.devenv` line 7 unused stage alias:** `FROM devenv-base:latest AS devenv-base` is referenced nowhere | Harmless but dead code. Spec doesn't require its removal. Leave as-is or clean up as minor housekeeping. |
| **`build_project()` auto-build chain:** Currently checks only `devenv:latest` | Must check entire chain: `repo-base` -> `devenv-base` -> `devenv`. Simplest: call `build_stage_devenv()` which cascades. Current implementation already does this (line 193 calls `build_stage_devenv`). The chain just needs to include `repo-base` in `build_stage_devenv`'s auto-check. |

---

## External Dependencies

No new runtime or build dependencies are introduced. The spec restructures existing Docker images and build scripts using the same tools (Docker, bash, standard Ubuntu packages).

---

## Open Decisions

### 1. ARG forwarding in `docker/devenv/Dockerfile.base`

**Question:** Should `docker/devenv/Dockerfile.base` redeclare `ARG USERNAME=devuser` (to reference `${USERNAME}` in SSH directory paths), or hardcode `devuser`?

**Options:**

| Option | Tradeoff |
|--------|----------|
| (A) Hardcode `devuser` | Simpler. Matches current practice in `Dockerfile.devenv` which hardcodes paths. Breaks if username changes, but that requires rebuilding all layers anyway. |
| (B) Redeclare ARG | More flexible but adds complexity. Must be kept in sync with `repo-base` ARG default. |

**Recommendation:** (A) Hardcode `devuser`. The username is a project-wide constant.

### 2. Standalone tool image label

**Question:** Should standalone tool images (`tools-<name>:latest`) carry `LABEL devenv=true`, `LABEL repo-base=true`, or a new label?

**Options:**

| Option | Tradeoff |
|--------|----------|
| (A) Keep `devenv=true` | Inaccurate for shared tools but maintains backward compatibility for any scripts filtering by this label. |
| (B) New label `devenv-tools=true` | Accurate but breaks any existing label-based filtering. |
| (C) No change (out of scope) | Spec doesn't address this. Defer to a future spec. |

**Recommendation:** (C) Out of scope. The spec doesn't change tool labels.

---

## Suggested Implementation Order

1. **Create `docker/base/Dockerfile.base`** — New repo-base Dockerfile. No dependencies. Can be verified independently with `docker build`.

2. **Update `docker/devenv/Dockerfile.base`** — Rewrite to `FROM repo-base:latest`. Requires step 1. Verify: build with `repo-base:latest` present, confirm SSH works.

3. **Update `bin/build-devenv`** — All build script changes:
   - Add `build_stage_repo_base()` function.
   - Rename current `build_stage_base()` to `build_stage_devenv_base()`.
   - Update `build_stage_devenv()` auto-dependency chain.
   - Update `build_tool()` image checks and tag format.
   - Update stage dispatcher and usage text.
   - Verify: `build-devenv --stage base`, `build-devenv --stage devenv-base`, `build-devenv --stage devenv`, `build-devenv --tool jq`.

4. **Update all 16 `shared/tools/Dockerfile.*`** — Change base FROM references. Mechanical find-and-replace. Requires step 1 (repo-base image must exist for standalone builds). Two files also get inter-tool FROM updates (ripgrep, tree-sitter).

5. **Update `docker/devenv/Dockerfile.devenv`** — Change 15 inline tool stage FROM lines. Requires step 1 (repo-base image). Verify: full `build-devenv --stage devenv`.

6. **End-to-end verification** — Build entire chain: `--stage base` -> `--stage devenv-base` -> `--stage devenv` -> `--tool <name>` -> `--project <path>`. Run `bin/devenv .` to confirm runtime is unaffected.

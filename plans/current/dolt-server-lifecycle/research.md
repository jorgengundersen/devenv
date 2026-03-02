# Research: Dolt Server Lifecycle Management Gap Analysis

**Source spec:** `specs/dolt-server-lifecycle.md` (261 lines)

**Files analyzed:**

| File | Lines |
|------|-------|
| `bin/devenv` | 667 |
| `docker/devenv/Dockerfile.base` | 29 |
| `docker/devenv/Dockerfile.devenv` | 287 |
| `shared/bash/log.sh` | 36 |
| `specs/coding-standard.md` | 471 |
| `.beads/config.yaml` | 55 |
| `.beads/dolt/config.yaml` | 96 |

---

## Current State Snapshot

The devenv container starts with an inline command passed to `bash -lc`. There are two code paths in `bin/devenv` `start_container()` (lines 325-387):

- **With SSH** (line 361): `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"`
- **Without SSH** (line 385): `bash -lc "exec sleep infinity"`

No init process (`tini`) is used. PID 1 is `bash`, which does not reap orphaned children. There is no entrypoint script. No `dolt sql-server` is started by the container; `bd` auto-starts its own server per-invocation, causing lock contention when multiple shells run concurrently.

The beads config (`.beads/config.yaml`) does not have a `dolt.auto-start` setting. The Dolt server config (`.beads/dolt/config.yaml`) shows the server listens on `127.0.0.1:14037`.

`tini` is not installed in any Dockerfile. The `shared/scripts/` directory does not exist.

---

## Gap Analysis Matrix

| # | Spec Requirement | Current State | Gap Type | Required Action |
|---|-----------------|---------------|----------|-----------------|
| 1 | Install `tini` in base image | Not installed | **NEW** | Add `apt-get install tini` to `Dockerfile.base` |
| 2 | Create `shared/scripts/entrypoint.sh` | Does not exist; directory does not exist | **NEW** | Create `shared/scripts/` directory and `entrypoint.sh` script |
| 3 | Copy entrypoint into image at `/usr/local/share/devenv/entrypoint.sh` | No COPY instruction exists | **NEW** | Add COPY + chmod to `Dockerfile.devenv` |
| 4 | `docker run` command uses `tini` + entrypoint instead of inline `bash -lc` | Inline `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"` | **UPDATE** | Change command in `start_container()` (3 locations) |
| 5 | Entrypoint starts `sshd` | `sshd` started inline in `docker run` command | **UPDATE** | Move `sshd` start into entrypoint script |
| 6 | Entrypoint resolves `repo_root` via `git rev-parse` or upward walk | No repo root resolution | **NEW** | Implement in entrypoint |
| 7 | Entrypoint detects `.beads/dolt/` and starts `dolt sql-server` | Not done; `bd` auto-starts per invocation | **NEW** | Implement in entrypoint |
| 8 | Read server port from `.beads/config.yaml` or Dolt config | Not applicable (no server startup) | **NEW** | Implement port reading in entrypoint |
| 9 | Health check: wait up to 30s for server TCP connection | Not applicable | **NEW** | Implement health check loop in entrypoint |
| 10 | Write PID/log under `$XDG_STATE_HOME/devenv/` | `bd` writes PID/log under `.beads/` | **NEW** | Implement state directory management in entrypoint |
| 11 | Exec `sleep infinity` to keep container alive | Already done (inline) | **UPDATE** | Move into entrypoint; same behavior |
| 12 | Handle all failure modes gracefully (no `.beads/dolt/`, port conflict, binary missing, etc.) | Not applicable | **NEW** | Implement in entrypoint |
| 13 | Set `dolt.auto-start: false` in `.beads/config.yaml` | Not set; setting does not exist in current config | **NEW** | Add setting to config (manual or post-init hook) |
| 14 | Container command structure: no-SSH path uses same entrypoint | No-SSH path uses bare `exec sleep infinity` | **UPDATE** | Unify both paths to use entrypoint |

---

## File-Level Change Map

### Files That Change

#### 1. `docker/devenv/Dockerfile.base` (29 lines)

- **Lines affected:** After line 17 (end of `apt-get install` block)
- **Nature:** **UPDATE** - Add `tini` to the existing `apt-get install` command
- **Change:** Add `tini` to the package list in the `RUN apt-get` on lines 14-17
- **Dependencies:** None. This is the foundation change.

#### 2. `docker/devenv/Dockerfile.devenv` (287 lines)

- **Lines affected:** After line 267 (XDG directory creation block) or near line 278 (ownership section)
- **Nature:** **NEW** - Add COPY instruction for entrypoint script
- **Change:** Add two lines: `COPY shared/scripts/entrypoint.sh /usr/local/share/devenv/entrypoint.sh` and `RUN chmod +x /usr/local/share/devenv/entrypoint.sh`
- **Dependencies:** Requires `shared/scripts/entrypoint.sh` to exist at build time.

#### 3. `bin/devenv` (667 lines)

- **Lines affected:**
  - Line 361: SSH `docker run` command - change `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"` to `bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"`
  - Line 364: SSH fallback `docker run` command - same change
  - Line 385: No-SSH `docker run` command - change `bash -lc "exec sleep infinity"` to `bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"`
- **Nature:** **UPDATE** - Replace inline startup command in `start_container()`
- **Dependencies:** Requires `tini` installed in image and entrypoint script copied in.
- **Note:** The SSH vs no-SSH distinction remains (port mapping is a docker-level concern), but the container command becomes identical in both paths. The entrypoint script detects and starts `sshd` internally.

#### 4. `shared/scripts/entrypoint.sh` (new file)

- **Nature:** **NEW** - Entire file
- **Dependencies:** Must source `log.sh` or implement standalone logging (since `DEVENV_HOME` is not available inside the container; `log.sh` is at a different path). The script runs inside the container where `log.sh` is not mounted. Need to either embed logging or use a simpler stderr-based approach.
- **Responsibilities:**
  1. Start `sshd` via `sudo /usr/sbin/sshd`
  2. Resolve `repo_root` (`git rev-parse --show-toplevel` or upward `.git/` walk)
  3. Check for `<repo_root>/.beads/dolt/`
  4. Read port from `<repo_root>/.beads/dolt/config.yaml` (listener.port field), default to `3306`
  5. Check if port is already in use; if Dolt is already responding, skip start
  6. Start `dolt sql-server` in background from `.beads/dolt/` directory
  7. Write PID to `$XDG_STATE_HOME/devenv/<project>/dolt-server.pid`
  8. Redirect server logs to `$XDG_STATE_HOME/devenv/<project>/dolt-server.log`
  9. Health-check loop (up to 30 seconds)
  10. `exec sleep infinity`

#### 5. `.beads/config.yaml` (55 lines)

- **Lines affected:** After line 55 (end of file) or in-place
- **Nature:** **NEW** - Add `dolt.auto-start: false`
- **Dependencies:** Must be set after `bd init`. This is a per-project runtime configuration, not a build-time change.
- **Note:** This is documented as a manual or post-init-hook step. The implementation agent should document this but does not need to automate it.

### Files That Do NOT Change

| File | Reason |
|------|--------|
| `shared/bash/log.sh` | No changes needed; runs on host only, not in container |
| `shared/config/**` | OpenCode configuration; unrelated to Dolt lifecycle |
| `shared/tools/**` | Tool installation scripts; unrelated |
| `.beads/dolt/config.yaml` | Existing Dolt server config; read-only by entrypoint, not modified |

---

## Function/Block-Level Detail

### `start_container()` in `bin/devenv` (lines 325-387)

**Current behavior:** Constructs docker run arguments and dispatches to one of two code paths based on whether SSH is enabled. Each path has a hardcoded inline bash command that starts the container process.

**Target behavior:** Both code paths use the same container command: `bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"`. The SSH/no-SSH distinction is retained only for the `-p` port mapping flag.

**Specific changes:**

- **Line 361:** Change the command argument from:
  ```
  bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
  ```
  To:
  ```
  bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"
  ```

- **Line 364:** Same change (this is the fallback retry path for Docker forwarder errors).

- **Line 385:** Change from:
  ```
  bash -lc "exec sleep infinity"
  ```
  To:
  ```
  bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"
  ```

**Impact:** The entrypoint script now handles `sshd` startup internally. The no-SSH case: the entrypoint must handle the case where `sshd` fails (no keys, no permissions) gracefully - it currently skips `sshd` entirely when there are no authorized_keys. The entrypoint should attempt `sshd` and tolerate failure, since the SSH port mapping is what actually enables SSH access.

### `Dockerfile.base` `apt-get` block (lines 14-17)

**Current behavior:** Installs `openssh-client` and `openssh-server`.

**Target behavior:** Also installs `tini`.

**Specific change:** Add `tini \` to the package list.

### `Dockerfile.devenv` final stage (lines 210-287)

**Current behavior:** Copies tool binaries, sets up symlinks, creates XDG directories, sets permissions.

**Target behavior:** Additionally copies entrypoint script to `/usr/local/share/devenv/entrypoint.sh` and makes it executable.

**New lines to add** (after existing COPY blocks, before the USER devuser line 284):

```dockerfile
COPY shared/scripts/entrypoint.sh /usr/local/share/devenv/entrypoint.sh
RUN chmod +x /usr/local/share/devenv/entrypoint.sh
```

### `shared/scripts/entrypoint.sh` (new file)

**New functions to add:**

| Function | Purpose |
|----------|---------|
| `start_sshd()` | Run `sudo /usr/sbin/sshd`; log warning on failure, do not exit |
| `resolve_repo_root()` | `git rev-parse --show-toplevel` with fallback to upward `.git/` walk from `$PWD` |
| `read_dolt_port()` | Parse port from `<repo_root>/.beads/dolt/config.yaml` via `yq` or grep; default to `3306` |
| `is_dolt_running()` | Check if a Dolt server responds on the given port via `dolt sql -q "SELECT 1"` |
| `start_dolt_server()` | Start `dolt sql-server` in background, redirect output to log file, write PID |
| `wait_for_dolt()` | Health-check loop: up to 30 iterations of 1-second sleeps, checking TCP connectivity |
| `ensure_state_dir()` | Create `$XDG_STATE_HOME/devenv/<project>/` directory |
| `main()` | Orchestrate: sshd, resolve root, detect beads, start dolt, health check, exec sleep |

---

## Edge Cases and Tradeoffs

| Scenario | Handling |
|----------|----------|
| No `.beads/dolt/` directory at startup | Skip Dolt server start silently. Container functions normally. |
| `.beads/dolt/` created after container start | Server is not auto-started. Container restart required (documented in spec). |
| Port already in use, Dolt responds | Treat as success. Log at debug level. Do not start a second server. |
| Port already in use, not Dolt | Log warning to stderr. Skip server start. Container continues. |
| `dolt` binary not in PATH | Log warning to stderr. Skip server start. Container continues. |
| `yq` not available for config parsing | Use `grep`/`sed` fallback to extract port from YAML. Or require `yq` (it is installed in the image). |
| Server fails to start within 30s | Log warning. Continue to `exec sleep infinity`. `bd` commands will report server unavailable. |
| Server crashes after start | Not restarted. Agents see connection errors. Container restart required. |
| `git` not available (unlikely in devenv) | Fall back to upward `.git/` directory walk. If that fails, use `$PWD` as repo root. |
| `sudo` not available for `sshd` | `sshd` start fails; log warning, continue. SSH will be unavailable. |
| Multiple repo roots (monorepo with nested repos) | `git rev-parse --show-toplevel` returns the innermost repo. This is correct behavior; the container's `--workdir` determines which project is active. |
| Container `--workdir` is not inside a git repo | Upward walk finds no `.git/`. Skip Dolt server start. |
| Race between entrypoint health check and first `docker exec` | Health check completes before `exec sleep infinity`, which is what `docker exec` waits for. If a shell attaches during health check, `bd` may see the server as not-yet-ready; this is acceptable (it retries or errors). |
| `$XDG_STATE_HOME` not set | Default to `$HOME/.local/state` per XDG spec. |
| State directory on a named volume | `devenv-state` is mounted at `/home/devuser/.local/state`; PID files written there persist across container restarts. Stale PIDs must not prevent new server starts (PID from previous container is irrelevant). Entrypoint should not check the PID file for "already running" - it should check the port. |

---

## External Dependencies

| Dependency | Status | Fallback |
|------------|--------|----------|
| `tini` | Available via `apt-get install tini` on Ubuntu | No fallback needed; it is a standard package in Ubuntu base images |
| `dolt` | Already installed in `Dockerfile.devenv` (line 208, copied at line 245) | Entrypoint checks `command -v dolt` and skips if missing |
| `yq` | Already installed in `Dockerfile.devenv` (line 150, copied at line 235) | Can use `grep`/`sed` as fallback for simple YAML parsing |
| `git` | Already installed in `repo-base` (foundational tool) | Upward `.git/` directory walk as fallback |

No new runtime or build dependencies beyond `tini`.

---

## Open Decisions

### 1. Logging inside the container entrypoint

**Question:** The entrypoint runs inside the container where `shared/bash/log.sh` is not available (it lives in the host repo, not in the image). How should the entrypoint handle logging?

**Options:**

| Option | Tradeoff |
|--------|----------|
| **A. Copy `log.sh` into the image and source it** | Consistent logging. Requires an additional COPY in Dockerfile and a well-known path inside the container (e.g., `/usr/local/share/devenv/log.sh`). Requires `DEVENV_HOME`-style resolution or a hardcoded path. |
| **B. Embed minimal logging directly in entrypoint** | Self-contained script. Duplicates a few lines from `log.sh`. Simpler build. |
| **C. Simple `printf` to stderr** | Minimal. No framework. Adequate for a script with ~5 log statements. |

**Recommendation:** Option A. The coding standard mandates sourcing `log.sh`. Copy it into the image alongside the entrypoint and source it with the container-side path.

### 2. SSH detection in entrypoint

**Question:** Currently, the no-SSH path in `bin/devenv` skips `sshd` entirely by using a different command. With a unified entrypoint, how does the entrypoint know whether to start `sshd`?

**Options:**

| Option | Tradeoff |
|--------|----------|
| **A. Always attempt `sshd`; tolerate failure** | Simple. If no keys are mounted, `sshd` starts but no one can connect (no authorized_keys = no login). Harmless. |
| **B. Check for `/home/devuser/.ssh/authorized_keys` before starting** | Matches current behavior. Slightly more logic in entrypoint. |
| **C. Pass an env var from `bin/devenv` to signal SSH mode** | Explicit. Adds `-e DEVENV_SSH=1` to docker run. More coupling. |

**Recommendation:** Option A. `sshd` is lightweight and safe to start unconditionally. If no authorized_keys exist, SSH connections simply fail (which is the desired behavior).

### 3. Dolt config port extraction method

**Question:** The Dolt server config is YAML (`.beads/dolt/config.yaml`). The beads project-level config (`.beads/config.yaml`) may also specify a port. Which takes precedence, and how to parse?

**Analysis:** The spec says "read from Beads' project configuration (`.beads/config.yaml`)". However, the current `.beads/config.yaml` has no port setting. The actual port is in `.beads/dolt/config.yaml` under `listener.port` (currently `14037`). The Dolt server is started against the Dolt config, so it uses `.beads/dolt/config.yaml`.

**Recommendation:** Read port from `.beads/dolt/config.yaml` (`listener.port` field) using `yq`. This is the authoritative source that `dolt sql-server` uses. If not found, default to `3306` (Dolt standard). Beads already knows this port because it reads the same config.

---

## Suggested Implementation Order

1. **Install `tini` in `Dockerfile.base`** - Single-line addition to the apt-get block. Rebuild base image. No downstream impact until entrypoint is used.

2. **Create `shared/scripts/entrypoint.sh`** - Write the full entrypoint script following coding standard. Include all functions: sshd, repo root resolution, Dolt detection, port reading, server start, health check, sleep. Run `shellcheck` on it.

3. **Copy `log.sh` and entrypoint into `Dockerfile.devenv`** - Add COPY instructions for both `shared/bash/log.sh` and `shared/scripts/entrypoint.sh` to `/usr/local/share/devenv/`. Ensure chmod +x.

4. **Update `bin/devenv` `start_container()`** - Replace the three inline `bash -lc` commands (lines 361, 364, 385) with the unified `bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"` command.

5. **Document `.beads/config.yaml` change** - Add `dolt.auto-start: false` to the project's beads config. This is a per-project manual step (or future post-init hook).

6. **Rebuild images and verify** - Rebuild base and devenv images. Start a container with an initialized beads database. Run the verification steps from the spec (multi-shell `bd` access, zombie check, no-beads project, server kill recovery).

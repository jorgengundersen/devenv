# Implementation Plan: Dolt Server Lifecycle Management

**Source research:** `plans/current/dolt-server-lifecycle/research.md`
**Source spec:** `specs/dolt-server-lifecycle.md`

## Required Reading

The implementer must read these files before starting:

1. `specs/coding-standard.md` -- All bash and Dockerfile rules.
2. `specs/dolt-server-lifecycle.md` -- Full spec for the feature.
3. `shared/bash/log.sh` -- Logging API to source inside the entrypoint.
4. `AGENTS.md` -- Project agent guidelines (shellcheck requirement, bd usage, landing-the-plane workflow).

---

## Execution Rules

- Every bash script must start with `set -euo pipefail`.
- Every bash script must pass `shellcheck` with zero warnings.
- All functions use `local` for every variable. No exceptions.
- Use `printf` for output, never `echo`.
- Log output goes to stderr; program data goes to stdout.
- `die()` is the only place `exit 1` is permitted outside `main()`.
- Source `log.sh` for logging; do not duplicate the logging framework inline.
- Dockerfiles must use `--no-install-recommends` on every `apt-get install`.
- `COPY` is preferred over `ADD`. Never use `COPY . .`.
- Run `shellcheck` on every new or modified bash script before finishing.
- Run `hadolint` on modified Dockerfiles if available.

---

## Task List

### Phase 1: Base Image -- Install tini

- [ ] **1. Add `tini` to `Dockerfile.base` apt-get block**

  - **Files:** `docker/devenv/Dockerfile.base:14`
  - **Description:** Add `tini` to the existing `apt-get install` package list so it is available in all downstream images.
  - **Before:**
    ```dockerfile
    RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server \
        && rm -rf /var/lib/apt/lists/*
    ```
  - **After:**
    ```dockerfile
    RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-client \
        openssh-server \
        tini \
        && rm -rf /var/lib/apt/lists/*
    ```
  - **Verification:** `hadolint docker/devenv/Dockerfile.base` passes (if available). Grep confirms `tini` in the package list.

---

### Phase 2: Entrypoint Script

- [ ] **2. Create `shared/scripts/entrypoint.sh`**

  - **Files:** `shared/scripts/entrypoint.sh` (new file; create `shared/scripts/` directory)
  - **Description:** Full entrypoint script following the coding standard skeleton. Sources `log.sh` from the container-side path `/usr/local/share/devenv/log.sh`. Implements all lifecycle functions per the spec. Uses `set -euo pipefail`, `main()` pattern, all variables `local`, `printf` not `echo`.
  - **Before:** File and directory do not exist.
  - **After:** Script with the following structure and functions:

    ```bash
    #!/bin/bash
    set -euo pipefail

    # entrypoint.sh - Container entrypoint: starts sshd, dolt sql-server, and keeps container alive

    # --- Constants ---
    readonly ENTRYPOINT_DIR="/usr/local/share/devenv"
    readonly DEFAULT_DOLT_PORT=3306
    readonly HEALTH_CHECK_TIMEOUT=30

    # --- Logging ---
    # shellcheck disable=SC1091  # Path resolved at image build time
    . "${ENTRYPOINT_DIR}/log.sh"

    # --- Primitives ---

    # Start sshd; tolerate failure (no authorized_keys = no SSH access).
    start_sshd() {
        if sudo /usr/sbin/sshd 2>/dev/null; then
            log_debug "sshd started"
        else
            log_warning "sshd failed to start; SSH will be unavailable"
        fi
    }

    # Resolve the repository root via git or upward .git/ walk.
    resolve_repo_root() {
        local root
        if command -v git >/dev/null 2>&1; then
            root=$(git rev-parse --show-toplevel 2>/dev/null) && { printf '%s' "${root}"; return 0; }
        fi
        local dir="${PWD}"
        while [[ "${dir}" != "/" ]]; do
            if [[ -d "${dir}/.git" ]]; then
                printf '%s' "${dir}"
                return 0
            fi
            dir="${dir%/*}"
            [[ -z "${dir}" ]] && dir="/"
        done
        return 1
    }

    # Read the Dolt listener port from config; default to 3306.
    read_dolt_port() {
        local repo_root="$1"
        local config="${repo_root}/.beads/dolt/config.yaml"
        local port
        if [[ -f "${config}" ]] && command -v yq >/dev/null 2>&1; then
            port=$(yq '.listener.port // ""' "${config}" 2>/dev/null)
            if [[ -n "${port}" && "${port}" != "null" ]]; then
                printf '%s' "${port}"
                return 0
            fi
        fi
        printf '%s' "${DEFAULT_DOLT_PORT}"
    }

    # Check if a Dolt server is already responding on the given port.
    is_dolt_running() {
        local port="$1"
        dolt sql -q "SELECT 1" --host 127.0.0.1 --port "${port}" --user root >/dev/null 2>&1
    }

    # Create the state directory for PID/log files.
    ensure_state_dir() {
        local project_name="$1"
        local state_home="${XDG_STATE_HOME:-${HOME}/.local/state}"
        local state_dir="${state_home}/devenv/${project_name}"
        mkdir -p "${state_dir}"
        printf '%s' "${state_dir}"
    }

    # Start dolt sql-server in background; write PID and redirect logs.
    start_dolt_server() {
        local dolt_dir="$1"
        local state_dir="$2"
        local config="${dolt_dir}/config.yaml"
        local log_file="${state_dir}/dolt-server.log"
        local pid_file="${state_dir}/dolt-server.pid"
        local -a server_args=("sql-server")
        if [[ -f "${config}" ]]; then
            server_args+=("--config" "${config}")
        fi
        dolt "${server_args[@]}" >> "${log_file}" 2>&1 &
        local pid=$!
        printf '%s' "${pid}" > "${pid_file}"
        log_info "dolt sql-server started (PID ${pid})"
    }

    # Wait up to HEALTH_CHECK_TIMEOUT seconds for Dolt to accept connections.
    wait_for_dolt() {
        local port="$1"
        local i
        for i in $(seq 1 "${HEALTH_CHECK_TIMEOUT}"); do
            if is_dolt_running "${port}"; then
                log_info "dolt sql-server ready on port ${port}"
                return 0
            fi
            sleep 1
        done
        log_warning "dolt sql-server did not become ready within ${HEALTH_CHECK_TIMEOUT}s"
        return 1
    }

    # --- Commands ---

    # Orchestrate container startup: sshd, dolt, sleep.
    main() {
        start_sshd

        local repo_root
        if ! repo_root=$(resolve_repo_root); then
            log_debug "No git repository found; skipping dolt server start"
            exec sleep infinity
        fi

        local dolt_dir="${repo_root}/.beads/dolt"
        if [[ ! -d "${dolt_dir}" ]]; then
            log_debug "No .beads/dolt/ directory; skipping dolt server start"
            exec sleep infinity
        fi

        if ! command -v dolt >/dev/null 2>&1; then
            log_warning "dolt binary not found; skipping dolt server start"
            exec sleep infinity
        fi

        local port
        port=$(read_dolt_port "${repo_root}")

        if is_dolt_running "${port}"; then
            log_debug "dolt sql-server already running on port ${port}"
            exec sleep infinity
        fi

        local project_name="${repo_root##*/}"
        local state_dir
        state_dir=$(ensure_state_dir "${project_name}")

        start_dolt_server "${dolt_dir}" "${state_dir}"

        wait_for_dolt "${port}" || true

        exec sleep infinity
    }

    # --- Entrypoint ---
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        main "$@"
    fi
    ```

  - **Verification:** `shellcheck shared/scripts/entrypoint.sh` passes with zero warnings. Script is executable.

---

### Phase 3: Dockerfile.devenv -- Copy log.sh and entrypoint into image

- [ ] **3. Add COPY instructions for `log.sh` and `entrypoint.sh` to `Dockerfile.devenv`**

  - **Files:** `docker/devenv/Dockerfile.devenv:277` (insert before the `USER devuser` line at 284)
  - **Description:** Copy both `shared/bash/log.sh` and `shared/scripts/entrypoint.sh` into `/usr/local/share/devenv/` inside the image. Make entrypoint executable. This must be in the final stage while still `USER root`.
  - **Before:** (lines 276-284)
    ```dockerfile
    RUN chown -R devuser:devuser /usr/local/bin \
        && chown devuser:devuser /usr/local/cargo /usr/local/rustup /usr/local/go /opt/nvim-linux-x86_64 /opt/node 2>/dev/null || true

    # Set up PATH for all tools
    ENV PATH="/usr/local/go/bin:/usr/local/cargo/bin:/usr/local/bin:${PATH}"
    ENV RUSTUP_HOME="/usr/local/rustup"
    ENV CARGO_HOME="/usr/local/cargo"

    USER devuser
    ```
  - **After:**
    ```dockerfile
    RUN chown -R devuser:devuser /usr/local/bin \
        && chown devuser:devuser /usr/local/cargo /usr/local/rustup /usr/local/go /opt/nvim-linux-x86_64 /opt/node 2>/dev/null || true

    # Copy entrypoint and logging library into the image
    COPY shared/bash/log.sh /usr/local/share/devenv/log.sh
    COPY shared/scripts/entrypoint.sh /usr/local/share/devenv/entrypoint.sh
    RUN chmod +x /usr/local/share/devenv/entrypoint.sh

    # Set up PATH for all tools
    ENV PATH="/usr/local/go/bin:/usr/local/cargo/bin:/usr/local/bin:${PATH}"
    ENV RUSTUP_HOME="/usr/local/rustup"
    ENV CARGO_HOME="/usr/local/cargo"

    USER devuser
    ```
  - **Verification:** `hadolint docker/devenv/Dockerfile.devenv` passes. Both files are present at the expected paths in the image after build.

---

### Phase 4: Update `bin/devenv` container commands

- [ ] **4a. Update SSH `docker run` command (line 361)**

  - **Files:** `bin/devenv:361`
  - **Description:** Replace the inline `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"` with the unified entrypoint command. The entrypoint handles sshd internally.
  - **Before:**
    ```bash
        if ! run_output=$(docker run "${common_args[@]}" -p "127.0.0.1:${ssh_port}:22" "${image_name}" bash -lc "sudo /usr/sbin/sshd; exec sleep infinity" 2>&1); then
    ```
  - **After:**
    ```bash
        if ! run_output=$(docker run "${common_args[@]}" -p "127.0.0.1:${ssh_port}:22" "${image_name}" bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh" 2>&1); then
    ```
  - **Verification:** `shellcheck bin/devenv` passes. Grep confirms no remaining `sudo /usr/sbin/sshd` in the file.

- [ ] **4b. Update SSH fallback `docker run` command (line 364)**

  - **Files:** `bin/devenv:364`
  - **Description:** Same change for the Docker forwarder fallback retry path.
  - **Before:**
    ```bash
                docker run "${common_args[@]}" -p "${ssh_port}:22" "${image_name}" bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
    ```
  - **After:**
    ```bash
                docker run "${common_args[@]}" -p "${ssh_port}:22" "${image_name}" bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"
    ```
  - **Verification:** `shellcheck bin/devenv` passes.

- [ ] **4c. Update no-SSH `docker run` command (line 385)**

  - **Files:** `bin/devenv:385`
  - **Description:** Replace the no-SSH inline command with the same unified entrypoint.
  - **Before:**
    ```bash
            bash -lc "exec sleep infinity"
    ```
  - **After:**
    ```bash
            bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"
    ```
  - **Verification:** `shellcheck bin/devenv` passes. All three `docker run` invocations in `start_container()` now use identical container commands.

---

### Phase 5: Beads Configuration

- [ ] **5. Document `dolt.auto-start: false` in `.beads/config.yaml`**

  - **Files:** `.beads/config.yaml:55` (append after end of file)
  - **Description:** Add the `dolt.auto-start: false` setting so beads does not attempt to auto-start its own Dolt server. This is a per-project manual step that must be applied after `bd init`.
  - **Before:** File ends at line 55 with `# - github.repo`
  - **After:** Append:
    ```yaml

    # Dolt server lifecycle: managed by container entrypoint, not by bd
    dolt:
      auto-start: false
    ```
  - **Verification:** `yq '.dolt.auto-start' .beads/config.yaml` returns `false`.

---

## Verification Plan

After all tasks are complete, run these checks:

1. **Shellcheck:** `shellcheck shared/scripts/entrypoint.sh` -- zero warnings.
2. **Shellcheck:** `shellcheck bin/devenv` -- zero warnings.
3. **Hadolint (if available):** `hadolint docker/devenv/Dockerfile.base docker/devenv/Dockerfile.devenv`.
4. **Grep sanity checks:**
   - `grep -n 'tini' docker/devenv/Dockerfile.base` -- confirms tini in package list.
   - `grep -n 'entrypoint.sh' docker/devenv/Dockerfile.devenv` -- confirms COPY instruction.
   - `grep -n 'exec tini' bin/devenv` -- shows exactly 3 matches (lines 361, 364, 385).
   - `grep -cn 'sudo /usr/sbin/sshd' bin/devenv` -- returns `0` (removed from bin/devenv; now only in entrypoint).
5. **Build verification (manual):** Rebuild base and devenv images. Start a container with an initialized beads database:
   - `ps aux | grep dolt` confirms `dolt sql-server` running.
   - `bd list` succeeds from first shell.
   - `bd list` succeeds from second shell (`docker exec`) without lock errors.
   - `bd create "test" -p 2 --json` succeeds from third shell.
   - `ps aux | grep defunct` returns empty (no zombies).
   - Start container for project without `.beads/` -- container starts normally, no dolt errors.
   - Kill dolt server (`kill <pid>`), verify `bd` commands report server unavailable.

---

## External References

- [tini - init for containers](https://github.com/krallin/tini)
- [Dolt sql-server configuration](https://docs.dolthub.com/sql-reference/server/configuration)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Docker best practices](https://docs.docker.com/build/building/best-practices/)

---

## Completion Checklist

- [ ] `tini` added to `Dockerfile.base` package list
- [ ] `shared/scripts/entrypoint.sh` created with all lifecycle functions
- [ ] `log.sh` and `entrypoint.sh` copied into devenv image at `/usr/local/share/devenv/`
- [ ] All three `docker run` commands in `bin/devenv` `start_container()` use `exec tini -- /usr/local/share/devenv/entrypoint.sh`
- [ ] No remaining `sudo /usr/sbin/sshd` in `bin/devenv`
- [ ] `dolt.auto-start: false` added to `.beads/config.yaml`
- [ ] `shellcheck` passes on `shared/scripts/entrypoint.sh` and `bin/devenv`
- [ ] All edge cases from research are handled in entrypoint (no `.beads/dolt/`, port in use, binary missing, git unavailable, `XDG_STATE_HOME` unset, stale PID files)

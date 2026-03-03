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

# Read the Dolt listener port.
# Resolution order:
#   1. Dolt server config: <repo_root>/.beads/dolt/config.yaml  (listener.port)
#   2. Beads project config: <repo_root>/.beads/config.yaml      (dolt.port)
#   3. Default: 3306
# The dolt server config is authoritative because bd uses it to start/connect.
read_dolt_port() {
    local repo_root="$1"
    local port

    if ! command -v yq >/dev/null 2>&1; then
        printf '%s' "${DEFAULT_DOLT_PORT}"
        return 0
    fi

    # 1. Dolt server config (authoritative — bd connects to this port)
    local dolt_config="${repo_root}/.beads/dolt/config.yaml"
    if [[ -f "${dolt_config}" ]]; then
        port=$(yq '.listener.port // ""' "${dolt_config}" 2>/dev/null)
        if [[ -n "${port}" && "${port}" != "null" ]]; then
            printf '%s' "${port}"
            return 0
        fi
    fi

    # 2. Beads project config (fallback)
    local beads_config="${repo_root}/.beads/config.yaml"
    if [[ -f "${beads_config}" ]]; then
        port=$(yq '(.dolt.listener.port // .dolt.port) // ""' "${beads_config}" 2>/dev/null)
        if [[ -n "${port}" && "${port}" != "null" ]]; then
            printf '%s' "${port}"
            return 0
        fi
    fi

    # 3. Default
    printf '%s' "${DEFAULT_DOLT_PORT}"
}

# Check if a Dolt server is already responding on the given port.
# Uses DOLT_CLI_PASSWORD to avoid interactive password prompt.
is_dolt_running() {
    local port="$1"
    DOLT_CLI_PASSWORD="" dolt --host 127.0.0.1 --port "${port}" --user root --no-tls \
        sql -q "SELECT 1" >/dev/null 2>&1
}

# Remove stale state files from a previous container session.
#
# When a container is destroyed without a clean shutdown, several files persist
# on the volume-mounted .beads/ directory:
#
#   .beads/dolt/.dolt/sql-server.info   — Dolt's own server lock (PID:PORT:UUID).
#                                         A new dolt sql-server refuses to start
#                                         if this file exists AND the PID is alive.
#                                         On a fresh container the PID is always
#                                         stale, but the file's mere presence can
#                                         confuse bd's server-detection heuristics.
#
#   .beads/dolt/devenv/.dolt/sql-server.info — Same, for the per-database copy.
#
#   .beads/dolt-server.pid              — PID recorded by bd's server manager.
#   .beads/dolt-server.port             — Port recorded by bd's server manager.
#   .beads/dolt-server.lock             — Lock file used by bd's server manager.
#   .beads/dolt-server.activity         — Activity tracker for bd auto-shutdown.
#   .beads/dolt-monitor.pid             — PID of bd's server health monitor.
#
# If any of these reference a PID that no longer exists (which is guaranteed
# on a fresh container), they are stale and must be removed before we start
# dolt.  Leaving them causes bd to mis-detect server state, attempt its own
# dolt sql-server start, and hit "database is locked" errors.
#
# IMPORTANT: We remove sql-server.info files UNCONDITIONALLY.  The PID check
# (kill -0) is unreliable across container restarts — PIDs can be reused by
# unrelated processes, causing kill -0 to succeed for a stale PID.  Since the
# entrypoint runs exactly once at container boot, before any dolt process is
# started by us, any existing sql-server.info is by definition stale.
#
# This function is idempotent and safe to call on every container boot.
clean_stale_state() {
    local repo_root="$1"
    local beads_dir="${repo_root}/.beads"
    local dolt_dir="${beads_dir}/dolt"

    # --- Dolt's own server info files ---
    # Remove unconditionally.  At entrypoint boot time, we have not started
    # dolt yet, so any sql-server.info is from a previous container session
    # (or a previous entrypoint run).  The old PID-liveness check was unsafe
    # because PIDs can be reused across container restarts.
    local info_file
    for info_file in \
        "${dolt_dir}/.dolt/sql-server.info" \
        "${dolt_dir}/devenv/.dolt/sql-server.info"; do
        if [[ -f "${info_file}" ]]; then
            rm -f "${info_file}"
            log_info "Removed stale dolt server info: ${info_file}"
        fi
    done

    # --- bd server management files ---
    # Remove unconditionally for the same reason: these are never valid across
    # container restarts regardless of whether the PID happens to be alive.
    local pid_file
    for pid_file in \
        "${beads_dir}/dolt-server.pid" \
        "${beads_dir}/dolt-monitor.pid"; do
        if [[ -f "${pid_file}" ]]; then
            rm -f "${pid_file}"
            log_info "Removed stale PID file: ${pid_file}"
        fi
    done

    # Remove lock, port, and activity files unconditionally on boot.
    # These are ephemeral runtime state — never valid across container restarts.
    local stale_file
    for stale_file in \
        "${beads_dir}/dolt-server.lock" \
        "${beads_dir}/dolt-server.port" \
        "${beads_dir}/dolt-server.activity"; do
        if [[ -f "${stale_file}" ]]; then
            rm -f "${stale_file}"
            log_info "Removed stale state file: ${stale_file}"
        fi
    done

    # Truncate the bd server log to prevent unbounded growth across restarts.
    # The entrypoint server log (in state_dir) is already container-scoped,
    # but bd's log in .beads/ persists on the volume.
    if [[ -f "${beads_dir}/dolt-server.log" ]]; then
        : > "${beads_dir}/dolt-server.log"
        log_debug "Truncated stale bd server log"
    fi
}

# Kill a single dolt process by PID, with graceful then forced shutdown.
_kill_dolt_pid() {
    local pid="$1"
    local reason="$2"
    if ! kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi
    log_info "Killing dolt sql-server (PID ${pid}): ${reason}"
    kill "${pid}" 2>/dev/null || true
    # Wait up to 5 seconds for graceful shutdown
    local _wait
    for _wait in $(seq 1 5); do
        kill -0 "${pid}" 2>/dev/null || return 0
        sleep 1
    done
    # Force kill if still alive
    if kill -0 "${pid}" 2>/dev/null; then
        log_warning "Force-killing dolt sql-server (PID ${pid})"
        kill -9 "${pid}" 2>/dev/null || true
        sleep 1
    fi
}

# Kill any dolt sql-server processes that would conflict with the server
# we are about to start.  This covers two scenarios:
#
#   1. A previous entrypoint invocation within the same container left a dolt
#      process running (e.g. container exec re-ran the entrypoint).
#
#   2. A dolt process is running on a DIFFERENT port from a previous session
#      where the config specified a different port.  This is critical: if we
#      only look for processes matching our data-dir, we miss dolt processes
#      started by bd on a mismatched port, which then lock the database.
#
# Strategy: kill ALL dolt sql-server processes.  At this point in the
# entrypoint we have already cleaned stale state and confirmed no valid
# server is running on our target port (is_dolt_running returned false).
# Any surviving dolt process is by definition orphaned or conflicting.
kill_stale_dolt_processes() {
    local dolt_dir="$1"
    local pid

    # First pass: processes referencing our data directory (most targeted)
    while IFS= read -r pid; do
        [[ -z "${pid}" ]] && continue
        _kill_dolt_pid "${pid}" "orphaned on data-dir ${dolt_dir}"
    done < <(pgrep -f "dolt sql-server.*--data-dir ${dolt_dir}" 2>/dev/null || true)

    # Second pass: ANY remaining dolt sql-server process.
    # This catches processes started with a relative data-dir path, different
    # path representation, or by bd with its own flags.  Since the entrypoint
    # is the sole authority for the dolt lifecycle, all other dolt servers
    # inside this container are illegitimate at boot time.
    while IFS= read -r pid; do
        [[ -z "${pid}" ]] && continue
        _kill_dolt_pid "${pid}" "unexpected dolt sql-server process"
    done < <(pgrep -f "dolt sql-server" 2>/dev/null || true)
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
    local port="$3"
    local log_file="${state_dir}/dolt-server.log"
    local pid_file="${state_dir}/dolt-server.pid"
    local -a server_args=(
        "sql-server"
        "--data-dir" "${dolt_dir}"
        "--host" "127.0.0.1"
        "--port" "${port}"
    )
    dolt "${server_args[@]}" >> "${log_file}" 2>&1 &
    local pid=$!
    printf '%s' "${pid}" > "${pid_file}"
    log_info "dolt sql-server started (PID ${pid})"
}

# Wait up to HEALTH_CHECK_TIMEOUT seconds for Dolt to accept connections.
wait_for_dolt() {
    local port="$1"
    local _
    for _ in $(seq 1 "${HEALTH_CHECK_TIMEOUT}"); do
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

    local config="${repo_root}/.beads/config.yaml"
    if [[ -f "${config}" ]] && command -v yq >/dev/null 2>&1; then
        local auto_start
        auto_start=$(yq '.dolt["auto-start"] // ""' "${config}" 2>/dev/null)
        if [[ -n "${auto_start}" && "${auto_start}" != "false" && "${auto_start}" != "null" ]]; then
            log_warning "beads config dolt.auto-start is not false; bd may try to start its own server"
        fi
    fi

    local port
    port=$(read_dolt_port "${repo_root}")

    # Clean up stale state from previous container sessions BEFORE checking
    # if dolt is already running or attempting to start it.  This prevents
    # bd from seeing leftover PID/lock files and trying to start its own
    # conflicting dolt server.
    clean_stale_state "${repo_root}"

    if is_dolt_running "${port}"; then
        log_debug "dolt sql-server already running on port ${port}"
        exec sleep infinity
    fi

    local project_name="${repo_root##*/}"
    local state_dir
    state_dir=$(ensure_state_dir "${project_name}")

    # Kill any orphaned dolt processes left from a previous entrypoint run
    # within the same container (e.g. if the entrypoint is re-invoked), or
    # from bd having started its own server despite auto-start: false.
    kill_stale_dolt_processes "${dolt_dir}"

    # Final safety: remove sql-server.info files one more time.  Between
    # clean_stale_state() and now, a killed dolt process may have left a
    # fresh info file, or bd may have created one.  We must clear it or
    # dolt sql-server will refuse to start with "database is locked".
    rm -f "${dolt_dir}/.dolt/sql-server.info" \
          "${dolt_dir}/devenv/.dolt/sql-server.info" 2>/dev/null || true

    start_dolt_server "${dolt_dir}" "${state_dir}" "${port}"

    wait_for_dolt "${port}" || true

    exec sleep infinity
}

# --- Entrypoint ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

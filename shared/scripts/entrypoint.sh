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
# This function is idempotent and safe to call on every container boot.
clean_stale_state() {
    local repo_root="$1"
    local beads_dir="${repo_root}/.beads"
    local dolt_dir="${beads_dir}/dolt"

    # --- Dolt's own server info files ---
    local info_file
    for info_file in \
        "${dolt_dir}/.dolt/sql-server.info" \
        "${dolt_dir}/devenv/.dolt/sql-server.info"; do
        if [[ -f "${info_file}" ]]; then
            local old_pid
            old_pid=$(cut -d: -f1 < "${info_file}" 2>/dev/null) || true
            if [[ -n "${old_pid}" ]] && ! kill -0 "${old_pid}" 2>/dev/null; then
                rm -f "${info_file}"
                log_info "Removed stale dolt server info: ${info_file} (dead PID ${old_pid})"
            fi
        fi
    done

    # --- bd server management files ---
    # These are all in .beads/ and reference PIDs or state from the old container.
    local pid_file
    for pid_file in \
        "${beads_dir}/dolt-server.pid" \
        "${beads_dir}/dolt-monitor.pid"; do
        if [[ -f "${pid_file}" ]]; then
            local old_pid
            old_pid=$(cat "${pid_file}" 2>/dev/null) || true
            if [[ -n "${old_pid}" ]] && ! kill -0 "${old_pid}" 2>/dev/null; then
                rm -f "${pid_file}"
                log_info "Removed stale PID file: ${pid_file} (dead PID ${old_pid})"
            fi
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

# Kill any dolt sql-server processes that are using our data directory
# but are NOT the server we are about to start.  This handles the case
# where a previous entrypoint invocation within the same container left
# a dolt process running (e.g. container exec re-ran the entrypoint).
kill_stale_dolt_processes() {
    local dolt_dir="$1"
    local pid
    # Find dolt sql-server processes whose command line references our data dir
    while IFS= read -r pid; do
        [[ -z "${pid}" ]] && continue
        if kill -0 "${pid}" 2>/dev/null; then
            log_info "Killing orphaned dolt sql-server (PID ${pid}) on data-dir ${dolt_dir}"
            kill "${pid}" 2>/dev/null || true
            # Give it a moment to release the lock
            local _wait
            for _wait in $(seq 1 5); do
                kill -0 "${pid}" 2>/dev/null || break
                sleep 1
            done
            # Force kill if still alive
            if kill -0 "${pid}" 2>/dev/null; then
                log_warning "Force-killing dolt sql-server (PID ${pid})"
                kill -9 "${pid}" 2>/dev/null || true
                sleep 1
            fi
        fi
    done < <(pgrep -f "dolt sql-server.*--data-dir ${dolt_dir}" 2>/dev/null || true)
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
    # within the same container (e.g. if the entrypoint is re-invoked).
    kill_stale_dolt_processes "${dolt_dir}"

    start_dolt_server "${dolt_dir}" "${state_dir}" "${port}"

    wait_for_dolt "${port}" || true

    exec sleep infinity
}

# --- Entrypoint ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

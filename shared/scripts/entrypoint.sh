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

    if is_dolt_running "${port}"; then
        log_debug "dolt sql-server already running on port ${port}"
        exec sleep infinity
    fi

    local project_name="${repo_root##*/}"
    local state_dir
    state_dir=$(ensure_state_dir "${project_name}")

    start_dolt_server "${dolt_dir}" "${state_dir}" "${port}"

    wait_for_dolt "${port}" || true

    exec sleep infinity
}

# --- Entrypoint ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

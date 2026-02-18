#!/bin/bash

# log.sh - Shared logging primitives for devenv Bash scripts

if [[ "${_DEVENV_LOG_SH_SOURCED:-0}" == "1" ]]; then
    return 0
fi
_DEVENV_LOG_SH_SOURCED=1
readonly _DEVENV_LOG_SH_SOURCED

# --- Logging ---

declare -A _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)

: "${DEVENV_LOG_LEVEL:=WARNING}"
readonly DEVENV_LOG_LEVEL

# Emit a structured log line if it meets the current log level.
_log() {
    local level="$1"; shift
    if (( _LOG_LEVELS[${level}] >= _LOG_LEVELS[${DEVENV_LOG_LEVEL}] )); then
        printf '[%s] [%-7s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "${level}" "$*" >&2
    fi
}

# Log a debug message.
log_debug() { _log "DEBUG" "$@"; }
# Log an info message.
log_info() { _log "INFO" "$@"; }
# Log a warning message.
log_warning() { _log "WARNING" "$@"; }
# Log an error message.
log_error() { _log "ERROR" "$@"; }

# Log error and exit.
die() { _log "ERROR" "$@"; exit 1; }

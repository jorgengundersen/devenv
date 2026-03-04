#!/usr/bin/env bats
# tests/bats/log_primitives.bats - Tests for shared/bash/log.sh primitives.
#
# IMPORTANT: DEVENV_LOG_LEVEL is declared `readonly` inside log.sh.
# Every test that needs a different log level MUST run in a fresh subshell
# that sources log.sh independently (before readonly takes effect).
# The _DEVENV_LOG_SH_SOURCED guard also means re-sourcing within the same
# shell is a no-op; subshells bypass both guards.

load '../helpers/test_env.bash'
load '../helpers/assert_output.bash'

# ---------------------------------------------------------------------------
# log_debug
# ---------------------------------------------------------------------------

@test "log_debug: emits message to stderr when DEVENV_LOG_LEVEL=DEBUG" {
    run bash -c '
        DEVENV_LOG_LEVEL=DEBUG
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_debug "hello debug"
    '
    assert_exit_code 0
    # stderr is in $output when not separated; run captures combined output.
    # log.sh writes to >&2; bats captures stderr into $output by default.
    [[ "${output}" =~ \[DEBUG ]] || {
        echo "output: ${output}"; return 1
    }
    [[ "${output}" =~ "hello debug" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "log_debug: suppressed when DEVENV_LOG_LEVEL=WARNING (default)" {
    run bash -c '
        # Unset any inherited value so log.sh default (WARNING) takes effect.
        unset DEVENV_LOG_LEVEL
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_debug "should not appear"
    '
    assert_exit_code 0
    [[ -z "${output}" ]] || {
        echo "Expected no output, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# log_info
# ---------------------------------------------------------------------------

@test "log_info: emits message to stderr when DEVENV_LOG_LEVEL=INFO" {
    run bash -c '
        DEVENV_LOG_LEVEL=INFO
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_info "hello info"
    '
    assert_exit_code 0
    [[ "${output}" =~ \[INFO ]] || {
        echo "output: ${output}"; return 1
    }
    [[ "${output}" =~ "hello info" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "log_info: suppressed when DEVENV_LOG_LEVEL=WARNING (default)" {
    run bash -c '
        # Unset any inherited value so log.sh default (WARNING) takes effect.
        unset DEVENV_LOG_LEVEL
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_info "should not appear"
    '
    assert_exit_code 0
    [[ -z "${output}" ]] || {
        echo "Expected no output, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# log_warning
# ---------------------------------------------------------------------------

@test "log_warning: emits message to stderr when DEVENV_LOG_LEVEL=WARNING" {
    run bash -c '
        DEVENV_LOG_LEVEL=WARNING
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_warning "hello warning"
    '
    assert_exit_code 0
    [[ "${output}" =~ \[WARNING ]] || {
        echo "output: ${output}"; return 1
    }
    [[ "${output}" =~ "hello warning" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "log_warning: emits message when DEVENV_LOG_LEVEL=INFO (WARNING>=INFO)" {
    run bash -c '
        DEVENV_LOG_LEVEL=INFO
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_warning "warning at info level"
    '
    assert_exit_code 0
    [[ "${output}" =~ "warning at info level" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "log_warning: suppressed when DEVENV_LOG_LEVEL=ERROR (WARNING<ERROR)" {
    run bash -c '
        DEVENV_LOG_LEVEL=ERROR
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_warning "should not appear"
    '
    assert_exit_code 0
    [[ -z "${output}" ]] || {
        echo "Expected no output, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# log_error
# ---------------------------------------------------------------------------

@test "log_error: always emits to stderr regardless of log level" {
    run bash -c '
        DEVENV_LOG_LEVEL=ERROR
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_error "critical error"
    '
    assert_exit_code 0
    [[ "${output}" =~ \[ERROR ]] || {
        echo "output: ${output}"; return 1
    }
    [[ "${output}" =~ "critical error" ]] || {
        echo "output: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# die
# ---------------------------------------------------------------------------

@test "die: exits with code 1" {
    run bash -c '
        DEVENV_LOG_LEVEL=ERROR
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        die "fatal failure"
    '
    assert_exit_code 1
}

@test "die: emits message on stderr in ERROR format" {
    run bash -c '
        DEVENV_LOG_LEVEL=ERROR
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        die "fatal failure"
    '
    [[ "${output}" =~ \[ERROR ]] || {
        echo "output: ${output}"; return 1
    }
    [[ "${output}" =~ "fatal failure" ]] || {
        echo "output: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# Log output format
# ---------------------------------------------------------------------------

@test "log output format matches [timestamp] [LEVEL  ] message pattern" {
    run bash -c '
        DEVENV_LOG_LEVEL=ERROR
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/shared/bash/log.sh"
        log_error "format check"
    '
    # Pattern: [YYYY-MM-DD HH:MM:SS] [LEVEL   ] message
    # Do NOT assert on timestamp value — match structural brackets only.
    [[ "${output}" =~ ^\[.*\]\ \[.*\]\ .*format\ check ]] || {
        echo "Output did not match expected log format: ${output}"; return 1
    }
}

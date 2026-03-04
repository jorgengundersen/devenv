#!/usr/bin/env bash
# tests/helpers/assert_output.bash - Assertion helpers for bats tests.
#
# Relies on bats variables: $status, $output, $stderr (bats sets these after `run`).
# For stderr capture use `run -2` (bats 1.5+) or redirect stderr explicitly.
# In this project tests use: run bash -c '... 2>stderr_file' patterns where needed,
# or bats' built-in stderr capture via the `--separate-stderr` run flag.

# Assert that the last `run` command exited with the given code.
assert_exit_code() {
    local expected="$1"
    # status and output are bats-injected globals; shellcheck doesn't know them.
    # shellcheck disable=SC2154
    if [[ "${status}" -ne "${expected}" ]]; then
        echo "Expected exit code ${expected}, got ${status}" >&2
        echo "stdout: ${output}" >&2
        return 1
    fi
}

# Assert that stdout contains the given substring.
assert_stdout_contains() {
    local substring="$1"
    if ! printf '%s' "${output}" | grep -qF "${substring}"; then
        echo "Expected stdout to contain: ${substring}" >&2
        echo "stdout: ${output}" >&2
        return 1
    fi
}

# Assert that stdout does NOT contain the given substring.
refute_stdout_contains() {
    local substring="$1"
    if printf '%s' "${output}" | grep -qF "${substring}"; then
        echo "Expected stdout NOT to contain: ${substring}" >&2
        echo "stdout: ${output}" >&2
        return 1
    fi
}

# Assert that stdout is empty.
assert_stdout_empty() {
    if [[ -n "${output}" ]]; then
        echo "Expected stdout to be empty, got: ${output}" >&2
        return 1
    fi
}

# Assert that the given file (captured stderr) contains the substring.
# Usage: assert_stderr_contains "substring" stderr_file
assert_stderr_contains() {
    local substring="$1"
    local stderr_file="${2:-}"
    local content
    if [[ -n "${stderr_file}" && -f "${stderr_file}" ]]; then
        content="$(cat "${stderr_file}")"
    elif [[ -n "${stderr:-}" ]]; then
        content="${stderr}"
    else
        echo "assert_stderr_contains: no stderr content available" >&2
        return 1
    fi
    if ! printf '%s' "${content}" | grep -qF "${substring}"; then
        echo "Expected stderr to contain: ${substring}" >&2
        echo "stderr: ${content}" >&2
        return 1
    fi
}

# Assert that the given file (captured stderr) is empty.
# Usage: assert_stderr_empty stderr_file
assert_stderr_empty() {
    local stderr_file="${1:-}"
    local content
    if [[ -n "${stderr_file}" && -f "${stderr_file}" ]]; then
        content="$(cat "${stderr_file}")"
    elif [[ -n "${stderr:-}" ]]; then
        content="${stderr}"
    else
        return 0
    fi
    if [[ -n "${content}" ]]; then
        echo "Expected stderr to be empty, got: ${content}" >&2
        return 1
    fi
}

#!/usr/bin/env bash
# tests/helpers/test_env.bash - Setup/teardown helpers for deterministic test runs.
#
# Per specs/testing-standard.md determinism rules:
#   - HOME is a fresh temp directory per test (no ~/.gitconfig or ~/.ssh leakage)
#   - PATH has tests/fixtures/bin first (fake docker intercepts real docker)
#   - LC_ALL=C for consistent text output
#   - DEVENV_HOME points to repo root

# Resolve repo root relative to this file's location (tests/helpers/ → repo root).
_TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

setup() {
    # Create isolated HOME for this test.
    _ORIG_HOME="${HOME}"
    HOME="$(mktemp -d)"
    export HOME

    # Deterministic locale.
    export LC_ALL=C

    # PATH: fake fixtures first, then real bin/scripts, then minimal system paths.
    export PATH="${_TEST_REPO_ROOT}/tests/fixtures/bin:${_TEST_REPO_ROOT}/bin:${_TEST_REPO_ROOT}/scripts:/usr/local/bin:/usr/bin:/bin"

    # DEVENV_HOME: repo root (scripts resolve shared/bash/log.sh from this).
    export DEVENV_HOME="${_TEST_REPO_ROOT}"
}

teardown() {
    # Remove temp HOME if it was set by setup.
    if [[ -n "${HOME:-}" && "${HOME}" != "${_ORIG_HOME:-}" && "${HOME}" == /tmp/* ]]; then
        rm -rf "${HOME}"
    fi
    HOME="${_ORIG_HOME:-}"
    export HOME
}

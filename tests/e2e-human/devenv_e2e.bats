#!/usr/bin/env bats
# tests/e2e-human/devenv_e2e.bats - Opt-in end-to-end smoke tests.
#
# REQUIRES: Docker daemon running and devenv:latest image built.
# DO NOT run in CI. Run manually: bats tests/e2e-human/devenv_e2e.bats

setup() {
    if ! docker info >/dev/null 2>&1; then
        skip "Docker daemon not running — skipping E2E test"
    fi
    if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^devenv:latest$"; then
        skip "devenv:latest image not found — run 'build-devenv --stage devenv' first"
    fi

    export DEVENV_HOME
    DEVENV_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    export PATH="${DEVENV_HOME}/bin:${DEVENV_HOME}/scripts:/usr/local/bin:/usr/bin:/bin"
    export LC_ALL=C

    _E2E_TMPDIR=$(mktemp -d)
    _ORIG_HOME="${HOME}"
    export HOME="${_E2E_TMPDIR}"
}

teardown() {
    HOME="${_ORIG_HOME:-}"
    export HOME
    if [[ -n "${_E2E_TMPDIR:-}" ]]; then
        rm -rf "${_E2E_TMPDIR}"
    fi
}

@test "e2e: devenv help exits 0" {
    run devenv help
    [[ "${status}" -eq 0 ]]
}

@test "e2e: devenv list exits 0 with Docker running" {
    run devenv list
    [[ "${status}" -eq 0 ]]
}

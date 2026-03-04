#!/usr/bin/env bats
# tests/bats/shared_primitives.bats - Unit tests for shared/bash/primitives.sh.
#
# Tests source the shared library directly. No Docker required.

load '../helpers/test_env.bash'
load '../helpers/assert_output.bash'

# ---------------------------------------------------------------------------
# Helper: source the shared primitives library.
# ---------------------------------------------------------------------------
_source_primitives() {
    # shellcheck disable=SC1091
    source "${DEVENV_HOME}/shared/bash/primitives.sh"
}

# ---------------------------------------------------------------------------
# resolve_project_path
# ---------------------------------------------------------------------------

@test "primitives: resolve_project_path dot resolves to PWD" {
    _source_primitives
    local expected="${PWD}"
    run resolve_project_path "."
    assert_exit_code 0
    [[ "${output}" == "${expected}" ]] || {
        echo "Expected: ${expected}, got: ${output}"; return 1
    }
}

@test "primitives: resolve_project_path absolute path passed through" {
    _source_primitives
    local tmpdir
    tmpdir=$(mktemp -d)
    run resolve_project_path "${tmpdir}"
    assert_exit_code 0
    [[ "${output}" == "${tmpdir}" ]] || {
        echo "Expected: ${tmpdir}, got: ${output}"; return 1
    }
    rm -rf "${tmpdir}"
}

@test "primitives: resolve_project_path nonexistent path returns 1" {
    _source_primitives
    run resolve_project_path "/nonexistent/path/xyz"
    assert_exit_code 1
}

@test "primitives: resolve_project_path relative path resolved against PWD" {
    _source_primitives
    local subdir="${HOME}/testsubdir"
    mkdir -p "${subdir}"
    local old_pwd="${PWD}"
    cd "${HOME}"
    run resolve_project_path "testsubdir"
    cd "${old_pwd}"
    assert_exit_code 0
    [[ "${output}" == "${subdir}" ]] || {
        echo "Expected: ${subdir}, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# derive_project_image_suffix
# ---------------------------------------------------------------------------

@test "primitives: derive_project_image_suffix produces parent-basename" {
    _source_primitives
    run derive_project_image_suffix "/home/user/projects/myapp"
    assert_exit_code 0
    [[ "${output}" == "projects-myapp" ]] || {
        echo "Expected: projects-myapp, got: ${output}"; return 1
    }
}

@test "primitives: derive_project_image_suffix replaces special chars with dashes" {
    _source_primitives
    run derive_project_image_suffix "/home/user/my projects/my app"
    assert_exit_code 0
    [[ ! "${output}" =~ " " ]] || {
        echo "Expected no spaces in output, got: ${output}"; return 1
    }
}

@test "primitives: derive_project_image_suffix output contains no leading non-alnum" {
    _source_primitives
    run derive_project_image_suffix "/home/user/projects/myapp"
    assert_exit_code 0
    [[ "${output}" =~ ^[a-zA-Z0-9] ]] || {
        echo "Expected output to start with alnum char, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# Guard: sourcing twice is idempotent (no duplicate function definitions)
# ---------------------------------------------------------------------------

@test "primitives: sourcing twice is idempotent" {
    _source_primitives
    _source_primitives
    run resolve_project_path "."
    assert_exit_code 0
}

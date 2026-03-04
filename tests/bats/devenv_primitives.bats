#!/usr/bin/env bats
# tests/bats/devenv_primitives.bats - Unit tests for pure helper functions in bin/devenv.
#
# Tests source bin/devenv (BASH_SOURCE guard prevents main() from running).
# No Docker required — all docker-calling functions are tested separately in devenv_cli.bats.

load '../helpers/test_env.bash'
load '../helpers/assert_output.bash'

# ---------------------------------------------------------------------------
# Helper: source devenv into the current shell (used by primitive tests that
# need to call functions directly without a subprocess).
# ---------------------------------------------------------------------------
_source_devenv() {
    # shellcheck disable=SC1091
    DEVENV_LOG_LEVEL=WARNING source "${DEVENV_HOME}/bin/devenv"
}

# ---------------------------------------------------------------------------
# is_valid_port
# ---------------------------------------------------------------------------

@test "is_valid_port: valid port 22" {
    _source_devenv
    is_valid_port 22
}

@test "is_valid_port: valid port 1 (minimum)" {
    _source_devenv
    is_valid_port 1
}

@test "is_valid_port: valid port 65535 (maximum)" {
    _source_devenv
    is_valid_port 65535
}

@test "is_valid_port: invalid port 0" {
    _source_devenv
    run is_valid_port 0
    assert_exit_code 1
}

@test "is_valid_port: invalid port 65536 (above max)" {
    _source_devenv
    run is_valid_port 65536
    assert_exit_code 1
}

@test "is_valid_port: invalid port abc (non-numeric)" {
    _source_devenv
    run is_valid_port "abc"
    assert_exit_code 1
}

@test "is_valid_port: invalid port empty string" {
    _source_devenv
    run is_valid_port ""
    assert_exit_code 1
}

@test "is_valid_port: invalid port negative number" {
    _source_devenv
    run is_valid_port "-1"
    assert_exit_code 1
}

# ---------------------------------------------------------------------------
# resolve_project_path
# ---------------------------------------------------------------------------

@test "resolve_project_path: dot resolves to PWD" {
    _source_devenv
    local expected="${PWD}"
    run resolve_project_path "."
    assert_exit_code 0
    [[ "${output}" == "${expected}" ]] || {
        echo "Expected: ${expected}, got: ${output}"; return 1
    }
}

@test "resolve_project_path: absolute path passed through" {
    _source_devenv
    local tmpdir
    tmpdir=$(mktemp -d)
    run resolve_project_path "${tmpdir}"
    assert_exit_code 0
    [[ "${output}" == "${tmpdir}" ]] || {
        echo "Expected: ${tmpdir}, got: ${output}"; return 1
    }
    rm -rf "${tmpdir}"
}

@test "resolve_project_path: nonexistent path returns 1" {
    _source_devenv
    run resolve_project_path "/nonexistent/path/xyz"
    assert_exit_code 1
}

@test "resolve_project_path: relative path resolved against PWD" {
    _source_devenv
    # Create a subdir of the temp HOME (which exists).
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
# resolve_container_project_path
# ---------------------------------------------------------------------------

@test "resolve_container_project_path: path under HOME maps to /home/devuser/..." {
    _source_devenv
    local project="${HOME}/projects/myapp"
    run resolve_container_project_path "${project}"
    assert_exit_code 0
    [[ "${output}" == "/home/devuser/projects/myapp" ]] || {
        echo "Expected: /home/devuser/projects/myapp, got: ${output}"; return 1
    }
}

@test "resolve_container_project_path: path outside HOME causes die (exit 1)" {
    # Must run in subshell — die calls exit.
    run bash -c '
        unset DEVENV_LOG_LEVEL
        # shellcheck disable=SC1091
        source "${DEVENV_HOME}/bin/devenv"
        resolve_container_project_path "/outside/home/path"
    '
    assert_exit_code 1
}

# ---------------------------------------------------------------------------
# derive_container_name
# ---------------------------------------------------------------------------

@test "derive_container_name: standard path produces devenv-parent-basename" {
    _source_devenv
    run derive_container_name "/home/user/projects/myapp"
    assert_exit_code 0
    [[ "${output}" == "devenv-projects-myapp" ]] || {
        echo "Expected: devenv-projects-myapp, got: ${output}"; return 1
    }
}

@test "derive_container_name: special chars are sanitized to dashes" {
    _source_devenv
    run derive_container_name "/home/user/my projects/my app"
    assert_exit_code 0
    # Spaces are replaced with dashes.
    [[ "${output}" =~ ^devenv- ]] || {
        echo "Expected output to start with devenv-, got: ${output}"; return 1
    }
    [[ ! "${output}" =~ " " ]] || {
        echo "Expected no spaces in output, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# derive_project_label
# ---------------------------------------------------------------------------

@test "derive_project_label: produces parent/basename" {
    _source_devenv
    run derive_project_label "/home/user/projects/myapp"
    assert_exit_code 0
    [[ "${output}" == "projects/myapp" ]] || {
        echo "Expected: projects/myapp, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# derive_project_image_suffix
# ---------------------------------------------------------------------------

@test "derive_project_image_suffix: produces sanitized parent-basename" {
    _source_devenv
    run derive_project_image_suffix "/home/user/projects/myapp"
    assert_exit_code 0
    [[ "${output}" == "projects-myapp" ]] || {
        echo "Expected: projects-myapp, got: ${output}"; return 1
    }
}

@test "derive_project_image_suffix: special chars replaced with dashes" {
    _source_devenv
    run derive_project_image_suffix "/home/user/my projects/my app"
    assert_exit_code 0
    [[ ! "${output}" =~ " " ]] || {
        echo "Expected no spaces in output, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# allocate_port
# ---------------------------------------------------------------------------

@test "allocate_port: returns a numeric port between 1 and 65535" {
    _source_devenv
    run allocate_port
    # uv is available in the devenv container.
    if [[ "${status}" -eq 0 ]]; then
        [[ "${output}" =~ ^[0-9]+$ ]] || {
            echo "Expected numeric output, got: ${output}"; return 1
        }
        local port="${output}"
        (( port >= 1 && port <= 65535 )) || {
            echo "Port out of range: ${port}"; return 1
        }
    else
        # If uv is not available, exit code 1 is acceptable.
        assert_exit_code 1
    fi
}

# ---------------------------------------------------------------------------
# get_image_name
# ---------------------------------------------------------------------------

@test "get_image_name: without .devenv/Dockerfile returns devenv:latest" {
    _source_devenv
    local project_path
    project_path=$(mktemp -d)
    run get_image_name "${project_path}"
    assert_exit_code 0
    [[ "${output}" == "devenv:latest" ]] || {
        echo "Expected: devenv:latest, got: ${output}"; return 1
    }
    rm -rf "${project_path}"
}

@test "get_image_name: with .devenv/Dockerfile returns devenv-project-<suffix>:latest" {
    _source_devenv
    # Build a project under HOME so resolve_container_project_path works.
    local project_path="${HOME}/myproject"
    mkdir -p "${project_path}/.devenv"
    touch "${project_path}/.devenv/Dockerfile"
    run get_image_name "${project_path}"
    assert_exit_code 0
    [[ "${output}" == devenv-project-* ]] || {
        echo "Expected output to start with devenv-project-, got: ${output}"; return 1
    }
    [[ "${output}" == *":latest" ]] || {
        echo "Expected output to end with :latest, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# build_mounts
# ---------------------------------------------------------------------------

@test "build_mounts: includes mandatory volume mounts" {
    _source_devenv
    local project_path="${HOME}/projects/myapp"
    mkdir -p "${project_path}"
    local -a mounts=()
    build_mounts "${project_path}" mounts
    # Mandatory named volumes must appear.
    local mounts_str="${mounts[*]}"
    [[ "${mounts_str}" == *"devenv-data"* ]] || {
        echo "Missing devenv-data mount. Mounts: ${mounts_str}"; return 1
    }
    [[ "${mounts_str}" == *"devenv-cache"* ]] || {
        echo "Missing devenv-cache mount. Mounts: ${mounts_str}"; return 1
    }
    [[ "${mounts_str}" == *"devenv-state"* ]] || {
        echo "Missing devenv-state mount. Mounts: ${mounts_str}"; return 1
    }
    # Project path mount must appear.
    [[ "${mounts_str}" == *"${project_path}"* ]] || {
        echo "Missing project path mount. Mounts: ${mounts_str}"; return 1
    }
}

@test "build_mounts: SSH_AUTH_SOCK mount included when set" {
    _source_devenv
    local project_path="${HOME}/projects/myapp"
    mkdir -p "${project_path}"
    local -a mounts=()
    SSH_AUTH_SOCK="/tmp/fake-ssh-agent.sock" build_mounts "${project_path}" mounts
    local mounts_str="${mounts[*]}"
    [[ "${mounts_str}" == *"/ssh-agent"* ]] || {
        echo "Missing SSH_AUTH_SOCK mount. Mounts: ${mounts_str}"; return 1
    }
}

@test "build_mounts: SSH_AUTH_SOCK mount absent when unset" {
    _source_devenv
    local project_path="${HOME}/projects/myapp"
    mkdir -p "${project_path}"
    local -a mounts=()
    unset SSH_AUTH_SOCK
    build_mounts "${project_path}" mounts
    local mounts_str="${mounts[*]}"
    [[ "${mounts_str}" != *"/ssh-agent"* ]] || {
        echo "SSH_AUTH_SOCK mount present but should be absent. Mounts: ${mounts_str}"; return 1
    }
}

@test "build_mounts: .gitconfig mount included when file exists" {
    _source_devenv
    local project_path="${HOME}/projects/myapp"
    mkdir -p "${project_path}"
    touch "${HOME}/.gitconfig"
    local -a mounts=()
    build_mounts "${project_path}" mounts
    local mounts_str="${mounts[*]}"
    [[ "${mounts_str}" == *".gitconfig"* ]] || {
        echo "Missing .gitconfig mount. Mounts: ${mounts_str}"; return 1
    }
}

# ---------------------------------------------------------------------------
# build_env_vars
# ---------------------------------------------------------------------------

@test "build_env_vars: includes TERM variable" {
    _source_devenv
    local -a env_vars=()
    TERM=xterm-256color build_env_vars env_vars
    local env_str="${env_vars[*]}"
    [[ "${env_str}" == *"TERM=xterm-256color"* ]] || {
        echo "Missing TERM env var. Env: ${env_str}"; return 1
    }
}

@test "build_env_vars: SSH_AUTH_SOCK env included when set" {
    _source_devenv
    local -a env_vars=()
    SSH_AUTH_SOCK="/tmp/fake-agent.sock" build_env_vars env_vars
    local env_str="${env_vars[*]}"
    [[ "${env_str}" == *"SSH_AUTH_SOCK=/ssh-agent"* ]] || {
        echo "Missing SSH_AUTH_SOCK env. Env: ${env_str}"; return 1
    }
}

@test "build_env_vars: SSH_AUTH_SOCK env absent when unset" {
    _source_devenv
    local -a env_vars=()
    unset SSH_AUTH_SOCK
    build_env_vars env_vars
    local env_str="${env_vars[*]}"
    [[ "${env_str}" != *"SSH_AUTH_SOCK"* ]] || {
        echo "SSH_AUTH_SOCK env present but should be absent. Env: ${env_str}"; return 1
    }
}

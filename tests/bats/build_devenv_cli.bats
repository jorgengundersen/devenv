#!/usr/bin/env bats
# tests/bats/build_devenv_cli.bats - CLI contract tests for bin/build-devenv.
#
# Also tests the duplicated primitives (resolve_project_path, derive_project_image_suffix)
# from bin/build-devenv independently, per spec section 4.

load '../helpers/test_env.bash'
load '../helpers/assert_output.bash'

# ---------------------------------------------------------------------------
# Helper: source build-devenv into current shell for primitive tests.
# ---------------------------------------------------------------------------
_source_build_devenv() {
    # shellcheck disable=SC1091
    DEVENV_LOG_LEVEL=WARNING source "${DEVENV_HOME}/bin/build-devenv"
}

# ---------------------------------------------------------------------------
# Duplicated primitives (tested independently per spec section 4)
# ---------------------------------------------------------------------------

@test "build-devenv: resolve_project_path dot resolves to PWD" {
    _source_build_devenv
    local expected="${PWD}"
    run resolve_project_path "."
    assert_exit_code 0
    [[ "${output}" == "${expected}" ]] || {
        echo "Expected: ${expected}, got: ${output}"; return 1
    }
}

@test "build-devenv: resolve_project_path nonexistent path returns 1" {
    _source_build_devenv
    run resolve_project_path "/nonexistent/xyz"
    assert_exit_code 1
}

@test "build-devenv: derive_project_image_suffix produces parent-basename" {
    _source_build_devenv
    run derive_project_image_suffix "/home/user/projects/myapp"
    assert_exit_code 0
    [[ "${output}" == "projects-myapp" ]] || {
        echo "Expected: projects-myapp, got: ${output}"; return 1
    }
}

@test "build-devenv: derive_project_image_suffix replaces special chars with dashes" {
    _source_build_devenv
    run derive_project_image_suffix "/home/user/my projects/my app"
    assert_exit_code 0
    [[ ! "${output}" =~ " " ]] || {
        echo "Expected no spaces in output, got: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# CLI: argument parsing
# ---------------------------------------------------------------------------

@test "build-devenv (no args): exits 1 and stdout contains Usage:" {
    run build-devenv
    assert_exit_code 1
    assert_stdout_contains "Usage:"
    [[ "${output}" =~ "No build options provided" ]] || {
        echo "Expected 'No build options provided' in output. Got: ${output}"; return 1
    }
}

@test "build-devenv --help: exits 0 and stdout contains Usage:" {
    run build-devenv --help
    assert_exit_code 0
    assert_stdout_contains "Usage:"
}

@test "build-devenv --stage (no value): exits 1 and stderr mentions requires an argument" {
    run build-devenv --stage
    assert_exit_code 1
    [[ "${output}" =~ "--stage requires an argument" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "build-devenv --stage invalid: exits 1 and stderr mentions Invalid stage" {
    run build-devenv --stage invalid
    assert_exit_code 1
    [[ "${output}" =~ "Invalid stage" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "build-devenv --stage base: exits 0 and fake docker received build call with base Dockerfile" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run build-devenv --stage base
    assert_exit_code 0
    [[ -f "${docker_log}" ]] || { echo "docker log not created"; return 1; }
    grep -q "build" "${docker_log}" || {
        echo "Expected 'build' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
    grep -q "Dockerfile.base" "${docker_log}" || {
        echo "Expected 'Dockerfile.base' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "build-devenv --tool nonexistent: exits 1 and stderr mentions Tool Dockerfile not found" {
    run build-devenv --tool nonexistent_tool_xyz
    assert_exit_code 1
    [[ "${output}" =~ "Tool Dockerfile not found" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "build-devenv --tool jq: exits 0 and fake docker log shows build with Dockerfile.jq" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run build-devenv --tool jq
    assert_exit_code 0
    [[ -f "${docker_log}" ]] || { echo "docker log not created"; return 1; }
    grep -q "Dockerfile.jq" "${docker_log}" || {
        echo "Expected 'Dockerfile.jq' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "build-devenv --tool bats: exits 0 and fake docker log shows build with Dockerfile.bats" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run build-devenv --tool bats
    assert_exit_code 0
    [[ -f "${docker_log}" ]] || { echo "docker log not created"; return 1; }
    grep -q "Dockerfile.bats" "${docker_log}" || {
        echo "Expected 'Dockerfile.bats' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "build-devenv --project /nonexistent: exits 1 and stderr mentions does not exist" {
    run build-devenv --project /nonexistent/path/xyz
    assert_exit_code 1
    [[ "${output}" =~ "does not exist" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "build-devenv --unknown: exits 1 and stderr mentions Unknown option" {
    run build-devenv --unknown
    assert_exit_code 1
    [[ "${output}" =~ "Unknown option" ]] || {
        echo "output: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# CLI: --force flag
# ---------------------------------------------------------------------------

@test "build-devenv --force --stage base: exits 0 without error" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run build-devenv --force --stage base
    assert_exit_code 0
}

@test "build-devenv --force: sets FORCE_BUILD=true" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    # Source build-devenv to inspect FORCE_BUILD after main() processes --force.
    # shellcheck disable=SC1091
    DEVENV_LOG_LEVEL=WARNING DOCKER_LOG="${docker_log}" source "${DEVENV_HOME}/bin/build-devenv"
    main --force --stage base
    [[ "${FORCE_BUILD}" == "true" ]] || {
        echo "Expected FORCE_BUILD=true, got: ${FORCE_BUILD}"; return 1
    }
}

@test "build-devenv --force --stage base: passes --no-cache to docker build" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run build-devenv --force --stage base
    assert_exit_code 0
    grep -q -- "--no-cache" "${docker_log}" || {
        echo "Expected '--no-cache' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "build-devenv --force --tool jq: passes --no-cache to docker build" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run build-devenv --force --tool jq
    assert_exit_code 0
    grep -q -- "--no-cache" "${docker_log}" || {
        echo "Expected '--no-cache' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "build-devenv --force --stage devenv: rebuilds all tool images even when they already exist" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    # Simulate all base and tool images already present so the normal (non-force)
    # path would skip them.  With --force every tool must still be rebuilt.
    local all_images
    all_images="$(printf 'repo-base:latest\ndevenv-base:latest\ndevenv:latest\n')"
    local tool
    for tool in cargo go fnm uv fzf jq lefthook node bun ripgrep \
                gh nvim opencode copilot-cli starship yq tree-sitter \
                make shellcheck hadolint mdformat beads dolt bats; do
        all_images+="tools-${tool}:latest"$'\n'
    done
    DOCKER_LOG="${docker_log}" FAKE_DOCKER_IMAGES_OUTPUT="${all_images}" \
        run build-devenv --force --stage devenv
    assert_exit_code 0
    # With --force every tool image must be rebuilt: expect at least one
    # Dockerfile.* build call per tool in the log.
    local rebuild_count
    rebuild_count=$(grep -c "Dockerfile\." "${docker_log}" || true)
    # There are 24 tools plus devenv-base, repo-base, devenv itself → >= 24 tool builds
    [[ "${rebuild_count}" -ge 24 ]] || {
        echo "Expected at least 24 Dockerfile.* build calls, got ${rebuild_count}."
        echo "docker log:"
        cat "${docker_log}"
        return 1
    }
}

#!/usr/bin/env bats
# tests/bats/devenv_cli.bats - CLI contract tests for bin/devenv.
#
# Runs bin/devenv as an executable with the fake docker on PATH.
# All tests require fake docker to handle `docker info` (validate_docker calls it).

load '../helpers/test_env.bash'
load '../helpers/assert_output.bash'

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------

@test "devenv help: exits 0 and stdout contains Usage:" {
    run devenv help
    assert_exit_code 0
    assert_stdout_contains "Usage:"
}

@test "devenv --help: exits 0 and stdout contains Usage:" {
    run devenv --help
    assert_exit_code 0
    assert_stdout_contains "Usage:"
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

@test "devenv list: exits 0 and stdout contains column headers" {
    run devenv list
    assert_exit_code 0
    assert_stdout_contains "NAME"
    assert_stdout_contains "SSH"
    assert_stdout_contains "STATUS"
    assert_stdout_contains "STARTED"
}

# ---------------------------------------------------------------------------
# stop
# ---------------------------------------------------------------------------

@test "devenv stop (no target): exits 1 and stderr contains error message" {
    run devenv stop
    assert_exit_code 1
    # die() emits to stderr which bats captures in $output.
    [[ "${output}" =~ "stop requires a path, name, or --all" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "devenv stop --all (no running containers): exits 0" {
    # Fake docker ps -q returns empty → no containers running.
    # DEVENV_LOG_LEVEL=INFO to allow log_info "No devenv containers running" to appear.
    FAKE_DOCKER_OUTPUT="" run env DEVENV_LOG_LEVEL=INFO devenv stop --all
    assert_exit_code 0
}

# ---------------------------------------------------------------------------
# volume
# ---------------------------------------------------------------------------

@test "devenv volume (no subcommand): exits 1 and stderr mentions Unknown volume command" {
    run devenv volume
    assert_exit_code 1
    [[ "${output}" =~ "Unknown volume command" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "devenv volume rm (no args): exits 1 and stderr contains Specify a volume name" {
    run devenv volume rm
    assert_exit_code 1
    [[ "${output}" =~ "Specify a volume name" ]] || {
        echo "output: ${output}"; return 1
    }
}

@test "devenv volume list: exits 0 and fake docker received volume ls call" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    DOCKER_LOG="${docker_log}" run devenv volume list
    assert_exit_code 0
    # Fake docker must have been called with volume ls.
    [[ -f "${docker_log}" ]] || { echo "docker log not created"; return 1; }
    grep -q "volume ls" "${docker_log}" || {
        echo "Expected 'volume ls' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "devenv volume rm <name> --force: exits 0 and fake docker called volume rm" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    # Need: docker ps -q --filter volume=... returns empty (not in use)
    #       docker volume inspect returns 0 (exists)
    #       docker volume rm returns 0
    # Fake docker returns 0 by default and empty output — so in-use check passes (empty = not in use).
    # volume inspect returning 0 is the default.
    DOCKER_LOG="${docker_log}" run devenv volume rm myvolume --force
    assert_exit_code 0
    grep -q "volume rm myvolume" "${docker_log}" || {
        echo "Expected 'volume rm myvolume' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "devenv volume rm --all --force: exits 0 and fake docker called volume rm" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    # Per-subcommand fake docker overrides:
    #   volume ls  → returns one volume name (so --all has something to remove)
    #   ps         → returns empty (volume not in use)
    #   volume inspect → exits 0, empty output (volume exists; default)
    #   volume rm  → exits 0 (default)
    FAKE_DOCKER_VOLUME_LS_OUTPUT="devenv-test-vol" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run devenv volume rm --all --force
    assert_exit_code 0
    grep -q "volume rm devenv-test-vol" "${docker_log}" || {
        echo "Expected 'volume rm devenv-test-vol' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

# ---------------------------------------------------------------------------
# start / attach (cmd_start)
# ---------------------------------------------------------------------------

@test "devenv <path>: exits 0 and fake docker received docker run call" {
    # Create a real project directory under the isolated HOME.
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    # FAKE_DOCKER_IMAGES_OUTPUT: make `docker images` appear to return devenv:latest
    # so the image-existence check in cmd_start passes.
    # FAKE_DOCKER_PS_OUTPUT: empty → container not running → start path.
    # No ~/.ssh/authorized_keys in isolated HOME → ssh_port is skipped.
    # docker run exits 0 (default), docker exec exits 0 (default, attach is no-op).
    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run devenv "${project_dir}"

    assert_exit_code 0
    [[ -f "${docker_log}" ]] || { echo "docker log not created"; return 1; }
    grep -q "^run " "${docker_log}" || {
        echo "Expected 'docker run' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
    grep -q "devenv:latest" "${docker_log}" || {
        echo "Expected image name 'devenv:latest' in docker run call. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "devenv --port 2222 <path>: docker run receives -p flag with port 2222" {
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    # Create an authorized_keys file so the SSH port code path is active.
    mkdir -p "${HOME}/.ssh"
    printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5 test\n' > "${HOME}/.ssh/authorized_keys"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run devenv --port 2222 "${project_dir}"

    assert_exit_code 0
    grep -q "2222" "${docker_log}" || {
        echo "Expected port 2222 in docker log. Got: $(cat "${docker_log}")"; return 1
    }
    grep -q "^run " "${docker_log}" || {
        echo "Expected 'docker run' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "devenv <path> (container already running): docker exec is called, docker run is not" {
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    # Derive the expected container name so we can return it from `docker ps`.
    # devenv-<parent>-<project> → devenv-projects-myapp
    local expected_container_name="devenv-projects-myapp"

    # FAKE_DOCKER_PS_OUTPUT: non-empty → is_container_running returns true.
    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="${expected_container_name}" \
    DOCKER_LOG="${docker_log}" \
        run devenv "${project_dir}"

    assert_exit_code 0
    grep -q "^exec " "${docker_log}" || {
        echo "Expected 'docker exec' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
    # Ensure docker run was NOT called (re-attach path skips starting a new container).
    if grep -q "^run " "${docker_log}"; then
        echo "Did not expect 'docker run' in re-attach path. Got: $(cat "${docker_log}")"; return 1
    fi
}

# ---------------------------------------------------------------------------
# Resource override env vars (DEVENV_MEMORY / DEVENV_MEMORY_SWAP / DEVENV_CPUS)
# ---------------------------------------------------------------------------

@test "DEVENV_MEMORY=4g: docker run receives --memory 4g" {
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    DEVENV_MEMORY="4g" \
    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run devenv "${project_dir}"

    assert_exit_code 0
    grep -q -- "--memory 4g" "${docker_log}" || {
        echo "Expected '--memory 4g' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "DEVENV_MEMORY_SWAP=6g: docker run receives --memory-swap 6g" {
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    DEVENV_MEMORY_SWAP="6g" \
    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run devenv "${project_dir}"

    assert_exit_code 0
    grep -q -- "--memory-swap 6g" "${docker_log}" || {
        echo "Expected '--memory-swap 6g' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "DEVENV_CPUS=2: docker run receives --cpus 2" {
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    DEVENV_CPUS="2" \
    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run devenv "${project_dir}"

    assert_exit_code 0
    grep -q -- "--cpus 2" "${docker_log}" || {
        echo "Expected '--cpus 2' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "default resources: docker run receives --memory 8g --memory-swap 12g --cpus 4" {
    local project_dir="${HOME}/projects/myapp"
    mkdir -p "${project_dir}"

    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"

    FAKE_DOCKER_IMAGES_OUTPUT="devenv:latest" \
    FAKE_DOCKER_PS_OUTPUT="" \
    DOCKER_LOG="${docker_log}" \
        run env -u DEVENV_MEMORY -u DEVENV_MEMORY_SWAP -u DEVENV_CPUS devenv "${project_dir}"

    assert_exit_code 0
    grep -q -- "--memory 8g" "${docker_log}" || {
        echo "Expected '--memory 8g' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
    grep -q -- "--memory-swap 12g" "${docker_log}" || {
        echo "Expected '--memory-swap 12g' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
    grep -q -- "--cpus 4" "${docker_log}" || {
        echo "Expected '--cpus 4' in docker log. Got: $(cat "${docker_log}")"; return 1
    }
}

@test "devenv volume rm --all with in-use volume: exits 1 and error mentions mounted by a running container" {
    local docker_log="${BATS_TMPDIR}/docker_calls.log"
    rm -f "${docker_log}"
    # Simulate an in-use volume using per-subcommand fake docker env vars:
    #   FAKE_DOCKER_VOLUME_LS_OUTPUT → volume ls returns "devenv-data"
    #   FAKE_DOCKER_PS_OUTPUT        → ps -q returns a non-empty container ID (in use)
    FAKE_DOCKER_VOLUME_LS_OUTPUT="devenv-data" \
    FAKE_DOCKER_PS_OUTPUT="abc123" \
    DOCKER_LOG="${docker_log}" \
        run devenv volume rm --all --force
    assert_exit_code 1
    [[ "${output}" =~ "mounted by a running container" ]] || {
        echo "output: ${output}"; return 1
    }
}

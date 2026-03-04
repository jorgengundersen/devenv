#!/usr/bin/env bats
# tests/bats/install_devenv_cli.bats - CLI contract tests for scripts/install-devenv.
#
# All tests run with DEVENV_HOME pointing to the real repo root (set by test_env.bash),
# so install-devenv can find bin/build-devenv and bin/devenv.
# HOME is isolated to a temp directory per test_env.bash setup.

load '../helpers/test_env.bash'
load '../helpers/assert_output.bash'

# ---------------------------------------------------------------------------
# help
# ---------------------------------------------------------------------------

@test "install-devenv --help: exits 0 and stdout contains Usage:" {
    run install-devenv --help
    assert_exit_code 0
    assert_stdout_contains "Usage:"
}

@test "install-devenv -h: exits 0 and stdout contains Usage:" {
    run install-devenv -h
    assert_exit_code 0
    assert_stdout_contains "Usage:"
}

# ---------------------------------------------------------------------------
# default install
# ---------------------------------------------------------------------------

@test "install-devenv (default install): exits 0 and creates symlinks in ~/.local/bin" {
    run install-devenv
    assert_exit_code 0
    [[ -L "${HOME}/.local/bin/devenv" ]] || {
        echo "devenv symlink not created at ${HOME}/.local/bin/devenv"; return 1
    }
    [[ -L "${HOME}/.local/bin/build-devenv" ]] || {
        echo "build-devenv symlink not created at ${HOME}/.local/bin/build-devenv"; return 1
    }
}

@test "install-devenv: symlink targets point to correct scripts" {
    run install-devenv
    assert_exit_code 0
    local devenv_target build_devenv_target
    devenv_target=$(readlink "${HOME}/.local/bin/devenv")
    build_devenv_target=$(readlink "${HOME}/.local/bin/build-devenv")
    [[ "${devenv_target}" == "${DEVENV_HOME}/bin/devenv" ]] || {
        echo "devenv symlink target wrong: ${devenv_target}"; return 1
    }
    [[ "${build_devenv_target}" == "${DEVENV_HOME}/bin/build-devenv" ]] || {
        echo "build-devenv symlink target wrong: ${build_devenv_target}"; return 1
    }
}

# ---------------------------------------------------------------------------
# idempotent install
# ---------------------------------------------------------------------------

@test "install-devenv (idempotent): running twice exits 0 and symlinks are recreated" {
    run install-devenv
    assert_exit_code 0
    # Run a second time — existing symlinks should be removed and recreated.
    run install-devenv
    assert_exit_code 0
    [[ -L "${HOME}/.local/bin/devenv" ]] || {
        echo "devenv symlink missing after second install"; return 1
    }
    [[ -L "${HOME}/.local/bin/build-devenv" ]] || {
        echo "build-devenv symlink missing after second install"; return 1
    }
}

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------

@test "install-devenv --uninstall (after install): exits 0 and removes symlinks" {
    # Install first.
    run install-devenv
    assert_exit_code 0
    # Then uninstall.
    run install-devenv --uninstall
    assert_exit_code 0
    [[ ! -L "${HOME}/.local/bin/devenv" ]] || {
        echo "devenv symlink still exists after uninstall"; return 1
    }
    [[ ! -L "${HOME}/.local/bin/build-devenv" ]] || {
        echo "build-devenv symlink still exists after uninstall"; return 1
    }
}

@test "install-devenv --uninstall (already uninstalled): exits 0" {
    # Nothing to uninstall — should still exit 0.
    DEVENV_LOG_LEVEL=INFO run install-devenv --uninstall
    assert_exit_code 0
}

# ---------------------------------------------------------------------------
# --source flag
# ---------------------------------------------------------------------------

@test "install-devenv --source <custom path>: creates symlinks targeting custom path" {
    run install-devenv --source "${DEVENV_HOME}"
    assert_exit_code 0
    [[ -L "${HOME}/.local/bin/devenv" ]] || {
        echo "devenv symlink not created"; return 1
    }
    local target
    target=$(readlink "${HOME}/.local/bin/devenv")
    [[ "${target}" == "${DEVENV_HOME}/bin/devenv" ]] || {
        echo "Expected target ${DEVENV_HOME}/bin/devenv, got: ${target}"; return 1
    }
}

@test "install-devenv --source (no value): exits 1 and stderr mentions requires a path" {
    run install-devenv --source
    assert_exit_code 1
    [[ "${output}" =~ "requires a path" ]] || {
        echo "output: ${output}"; return 1
    }
}

# ---------------------------------------------------------------------------
# unknown option
# ---------------------------------------------------------------------------

@test "install-devenv --unknown: exits 1 and stderr mentions Unknown option" {
    run install-devenv --unknown
    assert_exit_code 1
    [[ "${output}" =~ "Unknown option" ]] || {
        echo "output: ${output}"; return 1
    }
}

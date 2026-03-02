# Research: Testing Standard Gap Analysis

**Source spec:** `specs/testing-standard.md` (154 lines)

**Files analyzed:**

| File | Lines |
|---|---|
| `bin/devenv` | 667 |
| `bin/build-devenv` | 322 |
| `scripts/install-devenv` | 157 |
| `shared/bash/log.sh` | 36 |
| `specs/coding-standard.md` | 471 |
| `AGENTS.md` | 122 |

---

## Current State Snapshot

**No test infrastructure exists.** The `tests/` directory does not exist. There are no `.bats` files, no test helpers, no test fixtures, and no fake docker executable anywhere in the repository.

**bats-core is not installed** in the current devenv container environment.

**shellcheck is installed** (`v0.11.0` at `/usr/local/bin/shellcheck`), satisfying the static analysis tier.

All four scripts referenced by the spec exist and contain the primitive functions the spec requires testing. Each script has the `BASH_SOURCE` guard at the bottom (enabling source-for-testing), conforming to `specs/coding-standard.md` section 1.2.

---

## Gap Analysis Matrix

| # | Spec Requirement | Current State | Gap Type | Required Action |
|---|---|---|---|---|
| 1 | `tests/` directory structure (bats/, e2e-human/, helpers/, fixtures/) | Directory does not exist | `NEW` | Create full directory tree per spec layout |
| 2 | bats-core framework available | Not installed in environment | `NEW` | Install bats-core (runtime dependency) |
| 3 | Fake `docker` executable in `tests/fixtures/bin/docker` | Does not exist | `NEW` | Create fake docker that logs invocations |
| 4 | Test helper `tests/helpers/test_env.bash` | Does not exist | `NEW` | Create helper: set HOME, PATH, LC_ALL per determinism rules |
| 5 | Test helper `tests/helpers/assert_output.bash` | Does not exist | `NEW` | Create assertion helpers for stdout/stderr/exit code |
| 6 | `tests/bats/devenv_primitives.bats` — unit tests for 10 primitives | Does not exist | `NEW` | Write tests for all 10 primitives listed in spec |
| 7 | `tests/bats/devenv_cli.bats` — CLI contract tests for list/stop/volume | Does not exist | `NEW` | Write tests for list, stop, volume rm |
| 8 | `tests/bats/build_devenv_cli.bats` — argument parsing + docker intent | Does not exist | `NEW` | Write tests for --stage/--tool/--project/unknown |
| 9 | `tests/bats/install_devenv_cli.bats` — argument parsing + CLI contract | Does not exist | `NEW` | Write tests for install/uninstall/unknown |
| 10 | `shared/bash/log.sh` primitive tests (log_debug..die) | Does not exist | `NEW` | Write tests for log level filtering + die exit code (needs a bats file — spec doesn't name one explicitly) |
| 11 | `tests/e2e-human/README.md` | Does not exist | `NEW` | Create README explaining opt-in Docker E2E |
| 12 | `tests/e2e-human/devenv_e2e.bats` | Does not exist | `NEW` | Create placeholder/minimal E2E test file |
| 13 | Determinism: HOME=tmpdir per test | No tests exist | `NEW` | Implement in `test_env.bash` setup |
| 14 | Determinism: PATH with fixtures first | No tests exist | `NEW` | Implement in `test_env.bash` setup |
| 15 | Determinism: LC_ALL=C | No tests exist | `NEW` | Implement in `test_env.bash` setup |
| 16 | Default test run requires no Docker | No tests exist | `NEW` | Ensure all bats/ tests use fake docker |
| 17 | Static analysis: shellcheck on all scripts | shellcheck installed; no CI/runner | `NEW` | Create shellcheck runner or document run command |
| 18 | `BASH_SOURCE` guard on all scripts (sourceability) | Present in all 4 scripts | `NO CHANGE` | Already compliant |
| 19 | Duplicated primitives tested independently (`resolve_project_path` in devenv + build-devenv) | Both scripts have the function; no tests | `NEW` | Test each copy in its own test file |
| 20 | Duplicated primitive `derive_project_image_suffix` in devenv + build-devenv | Both scripts have the function; no tests | `NEW` | Test each copy in its own test file |

---

## File-Level Change Map

### Files to CREATE

| File | Nature | Dependencies |
|---|---|---|
| `tests/helpers/test_env.bash` | `NEW` — setup/teardown, PATH/HOME/LC_ALL isolation | None (first file to create) |
| `tests/helpers/assert_output.bash` | `NEW` — assertion helpers | None |
| `tests/fixtures/bin/docker` | `NEW` — fake docker executable | None |
| `tests/bats/devenv_primitives.bats` | `NEW` — 10+ tests for primitives | `test_env.bash`, `bin/devenv` |
| `tests/bats/devenv_cli.bats` | `NEW` — CLI contract tests | `test_env.bash`, `assert_output.bash`, `fixtures/bin/docker`, `bin/devenv` |
| `tests/bats/build_devenv_cli.bats` | `NEW` — argument parsing + docker intent | `test_env.bash`, `assert_output.bash`, `fixtures/bin/docker`, `bin/build-devenv` |
| `tests/bats/install_devenv_cli.bats` | `NEW` — install/uninstall contract tests | `test_env.bash`, `assert_output.bash`, `scripts/install-devenv` |
| `tests/bats/log_primitives.bats` | `NEW` — log level filtering + die | `test_env.bash`, `shared/bash/log.sh` |
| `tests/e2e-human/README.md` | `NEW` — human E2E instructions | None |
| `tests/e2e-human/devenv_e2e.bats` | `NEW` — opt-in Docker E2E smoke tests | All of the above |

### Files that do NOT change

| File | Reason |
|---|---|
| `bin/devenv` (667 lines) | Script structure already compliant; `BASH_SOURCE` guard present at line 665. Primitives and commands already separated. |
| `bin/build-devenv` (322 lines) | Same; `BASH_SOURCE` guard at line 320. |
| `scripts/install-devenv` (157 lines) | Same; `BASH_SOURCE` guard at line 155. |
| `shared/bash/log.sh` (36 lines) | Already compliant with spec; source guard at line 5. |
| `specs/testing-standard.md` | Authoritative spec; no changes. |
| `specs/coding-standard.md` | Reference only. |

---

## Function/Block-Level Detail

### `tests/helpers/test_env.bash` (NEW)

This file provides the `setup` and `teardown` functions used by every `.bats` file.

**Target behavior:**
- `setup`: Create temp HOME (`mktemp -d`), set `HOME`, set `LC_ALL=C`, set `PATH` to `tests/fixtures/bin:$DEVENV_HOME/bin:$DEVENV_HOME/scripts:/usr/bin:/bin`, export `DEVENV_HOME` pointing to repo root.
- `teardown`: Remove temp HOME directory.

### `tests/helpers/assert_output.bash` (NEW)

**Target behavior:**
- `assert_exit_code()` — compare `$status` against expected value.
- `assert_stdout_contains()` — grep `$output` for substring.
- `assert_stderr_contains()` — grep stderr capture for substring.
- `assert_stdout_empty()` / `assert_stderr_empty()`.
- `refute_stdout_contains()` — inverse.

### `tests/fixtures/bin/docker` (NEW)

**Target behavior:**
- Executable bash script that logs its arguments to a file (`$DOCKER_LOG` or `$BATS_TMPDIR/docker_calls.log`).
- Returns exit 0 by default.
- Supports overriding exit code via `FAKE_DOCKER_EXIT` environment variable.
- Supports providing canned stdout via `FAKE_DOCKER_OUTPUT` environment variable.
- Must handle subcommands: `ps`, `stop`, `run`, `exec`, `build`, `info`, `images`, `volume`, `system`.

### `tests/bats/devenv_primitives.bats` (NEW)

Tests for 10 primitives in `bin/devenv`. Sources the script (does not execute `main` due to guard).

| Primitive | Line in `bin/devenv` | Test scenarios |
|---|---|---|
| `resolve_project_path` | 87-105 | `.` resolves to PWD; absolute path passed through; relative path resolved; nonexistent path returns 1 |
| `resolve_container_project_path` | 108-119 | Path under HOME maps correctly; path outside HOME triggers die (must be handled via subshell) |
| `derive_container_name` | 122-136 | Standard path produces `devenv-parent-basename`; special chars sanitized; empty result returns 1 |
| `derive_project_label` | 139-147 | Produces `parent/basename` |
| `derive_project_image_suffix` | 150-164 | Produces sanitized `parent-basename`; special chars replaced; empty returns 1 |
| `is_valid_port` | 6-11 | Valid: 1, 22, 65535; Invalid: 0, 65536, "abc", "", negative |
| `allocate_port` | 167-172 | Returns a number between 1-65535 (requires python3; test can assert numeric output) |
| `get_image_name` | 288-299 | Without `.devenv/Dockerfile` returns `devenv:latest`; with it returns `devenv-project-<suffix>:latest` |
| `build_mounts` | 181-249 | Populates array with mandatory volume mounts; SSH_AUTH_SOCK conditional; config file conditionals |
| `build_env_vars` | 252-268 | Populates array with TERM; SSH_AUTH_SOCK conditional |

### `tests/bats/devenv_cli.bats` (NEW)

CLI contract tests. Runs `bin/devenv` as executable with fake docker on PATH.

| Scenario | Expected behavior |
|---|---|
| `devenv list` | Exits 0; prints header line with NAME/SSH/STATUS/STARTED columns |
| `devenv stop --all` with no running containers | Exits 0; logs "No devenv containers running" to stderr |
| `devenv stop` (no target) | Exits 1; stderr contains "stop requires a path, name, or --all" |
| `devenv volume rm` (no args) | Exits 1; stderr contains "Specify a volume name or use --all" |
| `devenv volume rm --all` with in-use volume | Exits 1; stderr contains "mounted by a running container" |
| `devenv help` | Exits 0; stdout contains "Usage:" |

### `tests/bats/build_devenv_cli.bats` (NEW)

| Scenario | Expected behavior |
|---|---|
| `build-devenv` (no args) | Exits 1; stderr contains "No build options provided" |
| `build-devenv --stage` (no value) | Exits 1; stderr contains "--stage requires an argument" |
| `build-devenv --stage invalid` | Exits 1; stderr contains "Invalid stage" |
| `build-devenv --stage base` | Exits 0; fake docker receives `build` command with correct `-f` and `-t` args |
| `build-devenv --tool jq` | Exits 0; fake docker receives `build` with `Dockerfile.jq` |
| `build-devenv --project /nonexistent` | Exits 1; stderr contains "does not exist" |
| `build-devenv --unknown` | Exits 1; stderr contains "Unknown option" |

### `tests/bats/install_devenv_cli.bats` (NEW)

| Scenario | Expected behavior |
|---|---|
| `install-devenv --help` | Exits 0; stdout contains "Usage:" |
| `install-devenv` (default install) | Creates symlinks in temp `$HOME/.local/bin/`; exits 0 |
| `install-devenv` (idempotent) | Running twice succeeds; symlinks updated |
| `install-devenv --uninstall` | Removes symlinks; exits 0 |
| `install-devenv --uninstall` (already uninstalled) | Exits 0; logs "Symlink not found" |
| `install-devenv --unknown` | Exits 1; stderr contains "Unknown option" |

### `tests/bats/log_primitives.bats` (NEW)

The spec names primitives for `shared/bash/log.sh` (line 136-138) but doesn't specify a bats file name. This file is the logical location.

| Scenario | Expected behavior |
|---|---|
| `log_debug` with `DEVENV_LOG_LEVEL=DEBUG` | Message appears on stderr |
| `log_debug` with `DEVENV_LOG_LEVEL=WARNING` (default) | No output on stderr |
| `log_info` with `DEVENV_LOG_LEVEL=INFO` | Message appears on stderr |
| `log_info` with `DEVENV_LOG_LEVEL=WARNING` | Suppressed |
| `log_warning` with `DEVENV_LOG_LEVEL=WARNING` | Message appears on stderr |
| `log_error` with any level | Message appears on stderr |
| `die` | Exits with code 1; message on stderr |

---

## Edge Cases and Tradeoffs

| Scenario | Recommended Handling |
|---|---|
| **`resolve_container_project_path` calls `die` on failure** | Test in a subshell; assert exit code 1 and stderr message. Cannot use bats `run` directly since `die` calls `exit` and the function is sourced. Wrap in `bash -c 'source ...; resolve_container_project_path /outside'`. |
| **`build_mounts` uses nameref (`local -n`)** | Requires bash 4.3+. bats-core runs under bash, so this works. Caller must pass a variable name. Test by declaring the array, calling the function, then asserting array contents. |
| **`allocate_port` depends on python3** | python3 is available in the devenv container. If testing in a minimal environment, provide a fallback test that asserts the function returns 1 when python3 is missing (by manipulating PATH). |
| **Fake docker must handle `docker info`** | `bin/devenv` calls `validate_docker` which runs `docker info`. Fake docker must handle `info` subcommand and return 0. |
| **Fake docker `docker ps` output format** | CLI tests for `list` and `stop --all` depend on docker ps output. Fake docker must return properly formatted output for `--format` flag. |
| **`build_mounts` probes many host files** | HOME is set to tmpdir, so `~/.gitconfig`, `~/.ssh/authorized_keys`, etc. won't exist — conditionals will skip them. To test the SSH mount path, create the file in the temp HOME. |
| **`install-devenv` creates real symlinks** | Test must use temp HOME so `$HOME/.local/bin/` is isolated. Verify symlink targets. Clean up in teardown. |
| **`log.sh` source guard (`_DEVENV_LOG_SH_SOURCED`)** | If sourcing `log.sh` multiple times in tests, the guard at line 5-8 will skip re-sourcing. Either unset `_DEVENV_LOG_SH_SOURCED` before each test or source it once in setup. Since `_DEVENV_LOG_SH_SOURCED` is `readonly`, unsetting fails — must source in a subshell per test or source `bin/devenv` (which sources log.sh) fresh each time. |
| **Timestamps in log output** | Spec says avoid asserting timestamps. Match log output with regex patterns that ignore the timestamp field. |
| **`cmd_volume_rm` reads from stdin (confirmation prompt)** | Test with `--force` to skip prompt; or pipe `echo "y"` for confirmation tests. |

---

## External Dependencies

| Dependency | Purpose | Availability | Fallback |
|---|---|---|---|
| `bats-core` | Test framework | Not installed; available via apt, npm, or git clone | Install via `apt-get install bats` or `npm install -g bats` or git clone from github.com/bats-core/bats-core |
| `python3` | Used by `allocate_port` primitive | Already installed in devenv container | Test can skip or mock when unavailable |
| `shellcheck` v0.11.0 | Static analysis tier | Already installed at `/usr/local/bin/shellcheck` | N/A |

---

## Open Decisions

### 1. bats-core installation method

**Options:**

| Option | Tradeoffs |
|---|---|
| `apt-get install bats` | Simple; may be an older version |
| `npm install -g bats` | Requires node; newer versions |
| Git submodule (`git clone bats-core`) | Version-pinned; no system dependency; adds repo files |
| Add to Dockerfile (devenv image) | Available in all containers; build-time cost |

**Recommendation:** Add to the devenv Dockerfile (via `shared/tools/` or directly in `docker/devenv/Dockerfile.devenv`) so it's always available. This aligns with the project pattern for tooling.

### 2. Unnamed log.sh test file

The spec lists primitives for `shared/bash/log.sh` (lines 136-138) but does not provide a bats filename in the test layout (lines 87-103). Need to decide the filename.

**Recommendation:** `tests/bats/log_primitives.bats` — follows the naming pattern of `devenv_primitives.bats`.

### 3. Duplicated primitives: test independently or extract first?

The spec (lines 60-62) says test each copy independently "until the duplication is resolved by extracting a shared library." `resolve_project_path` exists in both `bin/devenv` (line 87) and `bin/build-devenv` (line 64). `derive_project_image_suffix` exists in both `bin/devenv` (line 150) and `bin/build-devenv` (line 85).

**Recommendation:** Test independently in their respective test files (`devenv_primitives.bats` and `build_devenv_cli.bats`) as the spec directs. File a separate issue to extract shared primitives to a common library.

### 4. Scope of fake docker responses

The fake docker needs to handle different subcommands with different output formats. How sophisticated should it be?

**Recommendation:** Start minimal — log all calls, return 0, support `FAKE_DOCKER_OUTPUT` and `FAKE_DOCKER_EXIT` env vars. Add specific subcommand handling (e.g., `ps --format`) only as tests require it.

---

## Suggested Implementation Order

1. **Install bats-core** in the devenv environment (decide method per Open Decision #1).
2. **Create `tests/helpers/test_env.bash`** — setup/teardown with HOME/PATH/LC_ALL isolation.
3. **Create `tests/helpers/assert_output.bash`** — assertion helpers.
4. **Create `tests/fixtures/bin/docker`** — minimal fake docker.
5. **Create `tests/bats/log_primitives.bats`** — simplest tests; validates framework works.
6. **Create `tests/bats/devenv_primitives.bats`** — 10 primitives, no docker dependency.
7. **Create `tests/bats/devenv_cli.bats`** — CLI contract tests using fake docker.
8. **Create `tests/bats/build_devenv_cli.bats`** — argument parsing + docker intent.
9. **Create `tests/bats/install_devenv_cli.bats`** — symlink creation/removal.
10. **Create `tests/e2e-human/README.md`** — document opt-in E2E process.
11. **Create `tests/e2e-human/devenv_e2e.bats`** — minimal placeholder.
12. **Verify all bats/ tests pass without Docker** — run full suite, confirm no real docker calls.
13. **Run shellcheck on all scripts** — confirm zero warnings (static analysis tier).

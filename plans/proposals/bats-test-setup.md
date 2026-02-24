# Proposal: Bats Test Setup

## Goal
Introduce a Bash-first test harness using Bats so core CLI behavior can be
validated in CI without Docker access.

## Scope
- Focus on `bin/devenv` and `bin/build-devenv` behavior.
- Use fake Docker to validate command construction and error handling.
- Keep tests fast, deterministic, and runnable in CI.

## Non-Goals
- Running real Docker in CI.
- End-to-end container execution tests.
- Porting code to another language.

## Recommended Approach

### 1) Test Framework
- Use `bats-core` for Bash-oriented unit and CLI tests.
- Vendor `bats` into `tests/vendor/bats/` or fetch in CI (prefer vendoring for
  stability).

### 2) Test Layout
```
tests/
  helpers/
    test_env.bash        # shared setup/teardown
    assert_output.bash   # common assertions
  fixtures/
    bin/
      docker            # fake docker executable
  bats/
    devenv_primitives.bats
    devenv_cli.bats
    build_devenv_cli.bats
```

### 3) Fake Docker Strategy
- Place a fake `docker` script in `tests/fixtures/bin/docker`.
- Prepend `tests/fixtures/bin` to `PATH` in test setup.
- The fake script records args to a temp log and returns controlled output per
  command (ex: `docker info`, `docker ps`, `docker volume ls`).

### 4) Test Types
- **Primitive tests**: `source bin/devenv` and call functions directly.
- **CLI contract tests**: run `bin/devenv` with fake docker and assert stdout,
  stderr, and exit codes.
- **Golden command tests**: verify docker command lines are assembled correctly
  for start/attach/stop/list/volume paths.

### 5) CI Integration
- Add a `tests` job that runs `shellcheck` and `bats`.
- Keep docker-disabled by default; do not require Docker service.

## Test Coverage Targets
- `resolve_project_path`, `derive_container_name`, `derive_project_label`.
- `build_mounts`, `build_env_vars` with/without optional files.
- `cmd_list` formatting and parsing of port output.
- `cmd_stop` behavior for path, name, and `--all`.
- `cmd_volume` list/rm safety checks.
- `build-devenv` argument parsing and stage/tool dispatch.

## Risks and Mitigations
- **Risk**: Fake docker diverges from real behavior.
  - Mitigation: Keep output fixtures minimal and add opt-in local tests with
    real Docker later.
- **Risk**: PATH-based mocking leaks into other tests.
  - Mitigation: Centralized setup/teardown in `tests/helpers/test_env.bash`.

## Checklist
- [ ] Add `tests/` directory structure and helpers
- [ ] Add fake `docker` fixture
- [ ] Add initial Bats tests for `bin/devenv`
- [ ] Add Bats tests for `bin/build-devenv`
- [ ] Add CI job: `shellcheck` + `bats`
- [ ] Document how to run tests locally in `README.md`

## Acceptance Criteria
- `bats` suite runs without Docker installed.
- `shellcheck` passes on all bash scripts.
- Tests validate command construction, stdout/stderr, and exit codes for the
  primary CLI paths.

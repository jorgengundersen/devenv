# Testing Standard

## Overview

This project uses a **testing trophy** approach: prioritize signal-per-cost by
focusing on small, fast, deterministic tests (static analysis, unit tests, CLI
contract tests) and minimize expensive end-to-end tests.

All tests are **black-box by default**: they validate observable behavior (exit
codes, stdout, stderr, external effects) rather than internal function names or
implementation details.

## Core Principles

### 1. Black-Box Testing (Default)

Validate the **public contract** of code:

- Exit codes and return values.
- Stdout (data/output).
- Stderr (diagnostics, logs).
- External side effects (e.g., docker invocations, files written).

**Avoid:**

- Tests that assert internal function names.
- Tests that lock down local variable names or control flow.
- Mocking or spying on private helpers.

### 2. Testing Trophy (Prioritize by Signal/Cost)

In order of importance:

1. **Static Analysis** (required): `shellcheck` and linters.
1. **Primitive/Unit Tests** (many): pure helper functions; no Docker/network.
1. **CLI Contract Tests** (some): run scripts as executables; fake `docker` and
   other external tools.
1. **Real Docker E2E** (few, optional): opt-in only; minimal coverage for smoke
   tests.

### 3. Red-Green-Refactor Discipline (Strict)

- Write ONE failing test for ONE behavior.
- Make ONE implementation change to pass it.
- Refactor after green only.
- Repeat.

If a test failure cannot point to a single broken behavior, **split the test**.

### 4. "Primitives as Stable API" Rule

Specialized primitives (pure helper functions) that are explicitly tested become
part of a stable API:

- Refactors that rename or remove a tested primitive must update tests
  deliberately.
- Prefer CLI contract tests for orchestration-heavy behavior (where the boundary
  is clearer).
- Only mark primitives as stable if they have clear, reusable contracts.
- When a primitive is duplicated across scripts (e.g., `resolve_project_path` in
  both `bin/devenv` and `bin/build-devenv`), each copy must be tested
  independently until the duplication is resolved by extracting a shared library.

## Recommended Test Framework

- **Framework**: `bats-core` (Bash Automated Testing System).
- **Fake Docker**: Provide a fake `docker` executable in test fixtures; prepend
  its path to `PATH` during test runs.
- **Helpers**: Use test helper functions to reduce boilerplate and improve
  readability.

## Determinism and Stability

To avoid flaky tests and "harmless-change failures":

- Set `HOME` to a temporary directory per test (e.g., `mktemp -d`; no
  ~/.gitconfig or ~/.ssh leakage).
- Set `PATH` explicitly, with test fixtures first (e.g., fake docker).
- Set `LC_ALL=C` to ensure consistent text output.
- Avoid asserting timestamps, docker status strings, or dynamic values unless
  fully controlled/faked.
- Normalize outputs before assertion (trim whitespace, sort lists if order
  doesn't matter).

## Test Layout (Recommended)

```
tests/
  bats/
    devenv_cli.bats
    devenv_primitives.bats
    build_devenv_cli.bats
    install_devenv_cli.bats
  e2e-human/
    README.md
    devenv_e2e.bats
  helpers/
    test_env.bash
    assert_output.bash
  fixtures/
    bin/
      docker
```

### Human-Only Docker E2E (Optional)

These tests require Docker and human oversight. They are opt-in and should not
run in CI by default.

## What To Test

### For `bin/devenv`:

- **Primitives**: `resolve_project_path`, `resolve_container_project_path`,
  `derive_container_name`, `derive_project_label`,
  `derive_project_image_suffix`, `is_valid_port`, `allocate_port`,
  `get_image_name`, `build_mounts`, `build_env_vars`.
- **CLI Contract**:
  - `list` output presence and SSH parsing behavior.
  - `stop` behavior for `--all`, path target, and name target.
  - `volume rm` safety checks (in-use volume refusal; confirmation behavior).

### For `bin/build-devenv`:

- **Argument parsing**: `--stage`, `--tool`, `--project`, unknown options.
- **Docker intent**: Correct `docker build` calls (dockerfile path, tags,
  context).

### For `scripts/install-devenv`:

- **Argument parsing**: `install`, `uninstall`, unknown commands.
- **CLI Contract**: Symlink creation, PATH detection, idempotent installs,
  uninstall cleanup.

### For `shared/bash/log.sh`:

- **Primitives**: `log_debug`, `log_info`, `log_warning`, `log_error`, `die`.
- **Behavior**: Log level filtering via `LOG_LEVEL`, `die` exits with code 1.

## Acceptance Criteria (for Test Implementation)

- Default test run does not require Docker installed or running.
- Tests are fast (seconds, not minutes) and deterministic.
- Tests encode the CLI contract (exit code/stdout/stderr) and docker intent.
- Primitive tests exist only for explicitly stable, reusable primitives.
- This spec is the authoritative source for testing rules.

## References

- [bats-core](https://github.com/bats-core/bats-core) — Bash testing framework.
- [Testing Trophy](https://kentcdodds.com/blog/common-mistakes-with-react-testing-library)
  — Prioritize signal over cost.
- [Red-Green-Refactor](https://en.wikipedia.org/wiki/Test-driven_development#Cycle)
  — TDD discipline.

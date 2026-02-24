# Proposal: Testing Standard + Practical Test Harness (Bash CLI)

## Goal

Expand test capabilities in a productive, high-signal way:

- Protect behavior and enable refactoring.
- Keep the default suite fast and deterministic.
- Avoid brittle tests that fail on harmless changes.

This proposal introduces a dedicated testing spec and a repo-appropriate approach for adding tests.

## Scope

- Create an authoritative spec: `specs/testing-standard.md`.
- Define testing principles for this repo (black-box first, testing trophy, red-green-refactor discipline).
- Recommend a practical harness for Bash CLI testing (Bats + fake docker), without requiring Docker in CI.

## Non-Goals

- Do not modify or delete any existing proposals.
- Do not implement tests in this proposal.
- Do not require Docker to run the default test suite.

## Context (What This Repo Is)

This project is primarily Bash CLIs (`bin/devenv`, `bin/build-devenv`) that orchestrate:

- Docker CLI invocations.
- Filesystem resolution and HOME-relative behavior.
- Environment variables and mounted configuration.

The scripts are already structured in a test-friendly way:

- “Primitives” (input -> output helpers) plus command orchestration functions.
- `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main "$@"; fi` guard supports sourcing for tests.

Because much of the value is in command construction and UX contract, tests should focus on observable behavior rather than internal structure.

## Principles (Project Policy)

### 1) Black-box Testing (Default)

Default tests validate the public contract:

- Exit codes.
- Stdout (data output).
- Stderr (diagnostics and logs).
- External effects as observed at the boundaries (e.g., docker invocations).

Avoid tests that lock down internal function names, local variables, or control flow.

### 2) Testing Trophy (Repo-Specific)

Prioritize by signal/cost:

1. Static analysis (required): `shellcheck`.
2. Primitive/unit tests (many): pure helpers; no Docker/network.
3. CLI contract tests with fakes (some): run scripts as executables; fake `docker` on `PATH`.
4. Real Docker E2E (few, optional): opt-in only; minimal coverage.

### 3) Red-Green-Refactor (Strict)

Iteration discipline:

- ONE failing test for ONE behavior.
- ONE implementation change to make it pass.
- Refactor after green only.
- Repeat.

If a test failure cannot point to a single broken behavior, split the test.

### 4) “Primitives as Stable API” Rule

This repo values specialized, composable primitives. To keep tests stable:

- If tests call a primitive directly (by sourcing `bin/*`), that primitive is treated as a stable API.
- Refactors that rename/remove a tested primitive must update tests deliberately.
- Prefer CLI contract tests for orchestration-heavy behavior.

## Recommended Test Harness (Default: No Docker Required)

### Framework

- Use `bats-core` for Bash tests.

### Layout

```
tests/
  bats/
    devenv_cli.bats
    devenv_primitives.bats
    build_devenv_cli.bats
  helpers/
    test_env.bash
    assert.bash
  fixtures/
    bin/
      docker
```

### Fake Docker Strategy

Put a fake `docker` at `tests/fixtures/bin/docker` and ensure tests prepend it to `PATH`.

Requirements for the fake:

- Logs every invocation (argv) to a per-test temp log.
- Provides minimal, test-controlled outputs for subcommands used in the scripts.
- Never attempts to fully emulate Docker; it only supports what tests need.

This enables CLI contract tests that verify:

- The intent of docker commands (args and ordering that matter).
- Correct routing of stdout vs stderr.
- Correct exit code behavior.

### Determinism Rules

To avoid flakes and “harmless-change failures”, tests must:

- Set `HOME` to a temp dir.
- Set `PATH` explicitly (fixtures first).
- Set `LC_ALL=C`.
- Avoid reading real dotfiles (`~/.gitconfig`, `~/.ssh`, etc.).
- Avoid asserting timestamps or docker status strings unless fully faked.

## What To Test First (High-Value Targets)

For `bin/devenv`:

- Path/name derivation primitives: `resolve_project_path`, `derive_container_name`, `derive_project_label`, `derive_project_image_suffix`.
- Contract behaviors:
  - `list` output presence and SSH parsing behavior.
  - `stop` behavior for `--all`, path target, and name target.
  - `volume rm` safety checks (in-use volume refusal; confirmation behavior).

For `bin/build-devenv`:

- Argument parsing (`--stage`, `--tool`, `--project`, unknown options).
- Correct `docker build` calls (dockerfile path, tags, context).

## Acceptance Criteria

- A default test run does not require Docker installed or running.
- Tests are fast (seconds, not minutes) and deterministic.
- Tests encode the CLI contract (exit code/stdout/stderr) and docker intent.
- Primitive tests exist only for explicitly stable, reusable primitives.
- The spec `specs/testing-standard.md` becomes the authoritative source for testing rules.

## Follow-ups (Out of Scope for This Proposal)

- Implement `tests/` harness and first tests.
- Add CI job(s) for `shellcheck` + tests.
- Add a small opt-in “real docker” suite for smoke coverage.

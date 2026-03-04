# E2E Human Tests

These tests require a **running Docker daemon** and **human oversight**.
They are **opt-in only** and must not run in CI by default.

## When to Run

Run these tests when you want to validate real Docker integration end-to-end:

- After major changes to `bin/devenv` container lifecycle logic
- Before a release to verify the full container start/attach/stop cycle
- When debugging issues that only appear with a real Docker daemon

## How to Run

```bash
bats tests/e2e-human/devenv_e2e.bats
```

## Requirements

- Docker daemon running (`docker info` succeeds)
- `devenv:latest` image built (`build-devenv --stage devenv`)
- SSH authorized keys at `~/.ssh/authorized_keys` (for SSH port tests)

## What These Tests Cover

- Full container start (`devenv <path>`)
- Container attach (re-attach to running container)
- Container stop (`devenv stop <name>`)
- Volume creation and cleanup

## What These Tests Do NOT Cover

These are smoke tests only. Detailed behavior testing belongs in `tests/bats/`
using the fake docker fixture.

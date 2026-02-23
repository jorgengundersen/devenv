# Headless Exec Specification

## Goal
Provide a headless command execution path that runs a command inside a devenv
container and returns stdout/stderr to the host without attaching a TTY.

## Motivation
Troubleshooting and automation workflows often need to run one-off commands in a
running environment and capture output programmatically. The existing `devenv`
runtime only supports interactive attachment (`docker exec -it`), which is not
appropriate for headless execution or scripting.

This spec adds a simple, deterministic exec flow that aligns with the current
container lifecycle model (background container + exec sessions) while keeping
output clean and script-friendly.

## Scope
- Add a new `exec` subcommand to `bin/devenv`.
- Use existing container naming and path resolution rules.
- Provide headless execution with proper exit codes and output forwarding.

## Non-Goals
- Changing interactive `devenv .` behavior.
- Adding a new environment type.
- Introducing remote execution or SSH-based command dispatch.
- Changing image contents or mount configuration.

## Command Interface

```
devenv exec <path> -- <command...>
devenv exec . -- <command...>
devenv exec <name> -- <command...>
```

### Parsing Rules
- `exec` is a top-level subcommand.
- `--` is required to separate the target from the command.
- The `<path>` argument follows the same rules as `devenv .` and `devenv <path>`.
- If `<name>` matches an existing container name, it is used as-is.

### Exit Codes
- Exit code is the command exit status from inside the container.
- `devenv exec` returns non-zero on any internal validation error.

## Execution Model

### Container Resolution
1. Resolve the target into a container name using the existing naming rules.
2. If the container is not running, start it using the same start logic as
   `devenv .` (background + sshd + sleep infinity), then proceed.

### Headless Execution
Run a non-interactive `docker exec` without `-it`:

```
docker exec \
  --workdir /home/devuser/<relative_project_path> \
  --user devuser:devuser \
  devenv-<parent>-<project> \
  bash -lc "<command>"
```

### Output Handling
- Stdout and stderr are passed through to the host unchanged.
- No logging is printed to stdout.
- Logging continues to use stderr per the coding standard.

### Environment
- The command runs as `devuser`.
- `bash -lc` is used to load the same shell environment as interactive sessions.
- The working directory mirrors the project mount path.

## Validation Rules
- Ensure Docker daemon is available before running.
- Ensure `--` is present; if missing, print usage and exit non-zero.
- Ensure a command is provided after `--`.
- If the target path is invalid and does not match a container name, fail fast.

## Security
The exec flow must respect the same security rules as the interactive runtime:

- Containers run as `devuser` only.
- No Docker socket mount.
- No new writable host mounts beyond the project directory.

## Logging
- Use the shared logging helpers (`shared/bash/log.sh`).
- Errors and progress messages go to stderr only.
- Command output must not be wrapped or altered.

## Implementation Notes

### New Command
- Add `cmd_exec()` to `bin/devenv`.
- Add subcommand dispatch: `exec) cmd_exec "$@" ;;`.

### Recommended Primitives
- `resolve_exec_target()` for `<path>` or `<name>` handling.
- `exec_in_container()` to encapsulate `docker exec`.

## Verification

```
devenv exec . -- pwd
devenv exec . -- whoami
devenv exec . -- ls -la
```

Expected:
- Output appears on host stdout.
- Exit codes match the in-container command.

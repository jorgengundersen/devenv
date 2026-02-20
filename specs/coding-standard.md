# Coding Standard

This document is the authoritative reference for code quality, style, and safety in the devenv project. All code — scripts, Dockerfiles, configuration — must conform to these standards. No exceptions.

Agents and contributors must read this document in full before writing or modifying any code. Violations are rejected.

---

## 1. Bash

### 1.1 Baseline

Follow the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with the project-specific rules below taking precedence where they conflict.

### 1.2 Script Structure

Every script follows this skeleton:

```bash
#!/bin/bash
set -euo pipefail

# <script-name> - <one-line description>

# --- Constants ---
DEVENV_HOME="${DEVENV_HOME:-$(
    script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
    cd "${script_dir}/.." && pwd
)}"
readonly DEVENV_HOME
readonly IMAGE_PREFIX="devenv"

# --- Logging ---
# (see §1.5)
. "${DEVENV_HOME}/shared/bash/log.sh"

# --- Primitives ---
# Pure functions. One job each. No side effects beyond their purpose.
# Never call exit. Return non-zero on failure.

# --- Commands ---
# Business logic. Compose primitives. These may call die() on fatal errors.

# --- Entrypoint ---
main() {
    # Subcommand dispatch and top-level orchestration only.
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

The `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard allows sourcing the script for testing without triggering `main`.

### 1.3 Functions

**Naming:** `lowercase_with_underscores`. Verb-first: `resolve_path`, `build_mounts`, `is_container_running`.

**Scope:** Every function does one thing. If you need a comment block explaining a section within a function, that section is a new function.

**Variables:** All variables inside functions use `local`. No exceptions.

```bash
# Good
resolve_project_path() {
    local raw_path="$1"
    local resolved
    resolved=$(cd "${raw_path}" && pwd)
    printf '%s' "${resolved}"
}

# Bad — mutates global, does two things, no local
resolve_project_path() {
    PROJECT_PATH=$(cd "$1" && pwd)
    PROJECT_NAME=$(basename "$PROJECT_PATH")
}
```

**Return values:** Use `printf` to stdout. Never `echo` (it interprets flags like `-n`, `-e`). The caller captures with `$()`.

**Error signaling:** Return non-zero. Never call `exit` from a primitive. Only top-level command functions and `die()` may exit.

```bash
is_container_running() {
    local name="$1"
    docker ps --filter "name=^/${name}$" --format '{{.Names}}' | grep -q .
}

# Caller decides what to do on failure:
if ! is_container_running "${container_name}"; then
    start_container "${container_name}"
fi
```

**Documentation:** One comment line above every function. Describe *what*, not *how*.

```bash
# Resolve a path argument to a canonical absolute path.
resolve_project_path() { ... }
```

### 1.4 Architecture: Primitives and Composition

Functions are classified into two tiers:

**Primitives** — low-level, single-purpose, no side effects beyond their stated job. They never call `die()`. They return data via stdout and status via return code.

```
resolve_project_path()      # path arg → canonical absolute path
derive_container_name()     # path → "devenv-parent-basename"
derive_project_label()      # path → "parent/basename"
get_image_name()            # path → image tag string
allocate_port()             # → free port number
is_container_running()      # name → return 0/1
build_mounts()              # path → array of -v flags
build_env_vars()            # → array of -e flags
```

**Commands** — orchestrate primitives into user-facing operations. These are the only functions that may call `die()`.

```
cmd_start()                 # resolve → name → image → mounts → run/exec
cmd_list()                  # query docker, format table, print to stdout
cmd_stop()                  # resolve target, docker stop
```

A command function reads like a recipe:

```bash
# Start or attach to a development environment.
cmd_start() {
    local project_path
    project_path=$(resolve_project_path "${1:-.}")

    local container_name
    container_name=$(derive_container_name "${project_path}")

    if is_container_running "${container_name}"; then
        log_info "Attaching to ${container_name}"
        attach_container "${container_name}"
    else
        log_info "Starting ${container_name}"
        start_container "${project_path}" "${container_name}"
        attach_container "${container_name}"
    fi
}
```

### 1.5 Logging

All scripts use the same logging framework.

To prevent copy/paste drift, scripts should source the shared library:

```bash
. "${DEVENV_HOME}/shared/bash/log.sh"
```

The shared library must provide the following behavior and API:

```bash
declare -A _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
: "${DEVENV_LOG_LEVEL:=WARNING}"
readonly DEVENV_LOG_LEVEL

_log() {
    local level="$1"; shift
    if (( _LOG_LEVELS[${level}] >= _LOG_LEVELS[${DEVENV_LOG_LEVEL}] )); then
        printf '[%s] [%-7s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "${level}" "$*" >&2
    fi
}

log_debug()   { _log "DEBUG" "$@"; }
log_info()    { _log "INFO" "$@"; }
log_warning() { _log "WARNING" "$@"; }
log_error()   { _log "ERROR" "$@"; }

# Log error and exit. Only place exit 1 is permitted outside main.
die() { _log "ERROR" "$@"; exit 1; }
```

**Rules:**

| Level   | Purpose                                  | Example                                      |
|---------|------------------------------------------|----------------------------------------------|
| DEBUG   | Internal state, variable values          | `log_debug "Resolved path: ${path}"`         |
| INFO    | Normal operations the user should see    | `log_info "Starting container ${name}"`      |
| WARNING | Recoverable problems                     | `log_warning "SSH agent not available"`       |
| ERROR   | Fatal conditions (via `die()`)           | `die "Docker daemon is not running"`         |

- Default level: `WARNING`. Override with `DEVENV_LOG_LEVEL=DEBUG` on the host.
- All log output goes to **stderr**.
- `die()` always exits with code 1.
- `log_error()` logs but does NOT exit. Use it for non-fatal error conditions where the function returns non-zero instead.

### 1.6 stdout vs stderr

**stderr:** All logging, diagnostics, progress messages. Everything produced by `_log`.

**stdout:** Program output only. Data that a downstream command might consume.

- `devenv list` table → stdout
- SSH port announcement → stdout
- `printf '%s' "${result}"` from primitives → stdout

This allows: `devenv list | grep api`, `ssh_port=$(devenv list | awk '/myproject/ {print $2}')`.

### 1.7 Command-Line Parsing

Top-level dispatch uses `case` on the first positional argument (subcommand pattern):

```bash
main() {
    local command="${1:-help}"
    shift || true

    case "${command}" in
        list)          cmd_list "$@" ;;
        stop)          cmd_stop "$@" ;;
        help|--help|-h) usage ;;
        *)             cmd_start "${command}" "$@" ;;
    esac
}
```

Within subcommands, use `getopts` for flag parsing:

```bash
cmd_start() {
    local port=""
    local OPTIND=1

    while getopts ":p:" opt; do
        case "${opt}" in
            p) port="${OPTARG}" ;;
            :) die "Option -p requires a port number" ;;
            ?) die "Unknown option: -${OPTARG}" ;;
        esac
    done
    shift $((OPTIND - 1))

    local target="${1:-.}"
    # ...
}
```

Long options (`--port`, `--all`) are handled as aliases in the `case` block before `getopts` runs, or in the top-level dispatcher. Do not depend on GNU `getopt`.

### 1.8 Variables and Constants

- **Constants:** `readonly` at the top of the script. `UPPER_SNAKE_CASE`.
- **Local variables:** `local` keyword. `lower_snake_case`.
- **Quote everything:** `"${var}"`, never bare `$var`.
- **Parameter expansion over external commands:** `"${path##*/}"` instead of `$(basename "${path}")`. `"${var:-default}"` instead of conditional assignment.
- **Arrays:** Use bash arrays for building command arguments. Never string-concatenate flags.

```bash
# Good
local mounts=()
mounts+=("-v" "${path}:/home/devuser/${relative_path}:rw")
docker run "${mounts[@]}" ...

# Bad
local mounts="-v ${path}:/home/devuser/${relative_path}:rw"
docker run $mounts ...
```

### 1.9 Error Handling

- `set -euo pipefail` at the top of every script. No exceptions.
- Validate inputs at function entry. Fail fast with actionable messages.
- `die()` messages must tell the user what went wrong AND what to do about it.

```bash
# Good
die "Docker daemon is not running. Start Docker and try again."

# Bad
die "Error"
```

- Use trap handlers for cleanup during container startup:

```bash
cleanup_on_interrupt() {
    log_warning "Interrupted during startup"
    # Clean up partially-started resources if needed
}
trap cleanup_on_interrupt INT TERM
```

### 1.10 ShellCheck

All bash scripts must pass `shellcheck` with zero warnings. This is not optional. Run it before every commit. Disable specific checks only with an inline comment explaining why:

```bash
# shellcheck disable=SC2034  # Variable used by sourcing script
readonly MY_VAR="value"
```

**Sourcing shared libraries:** ShellCheck may emit `SC1091` for `source`/`.` lines when the sourced path is dynamic (for example, `. "${DEVENV_HOME}/shared/bash/log.sh"`). In this repo we allow disabling `SC1091` for that specific line:

```bash
# shellcheck disable=SC1091  # Path resolved at runtime via DEVENV_HOME
. "${DEVENV_HOME}/shared/bash/log.sh"
```

If you want ShellCheck to follow and analyze sourced files too, run it with `-x` and include the entrypoint scripts (and any libraries as needed).

---

## 2. Dockerfiles

### 2.1 Baseline

Follow [Docker best practices](https://docs.docker.com/build/building/best-practices/) and [Hadolint](https://github.com/hadolint/hadolint) conventions.

### 2.2 Required Patterns

**Syntax directive:** Every Dockerfile starts with:

```dockerfile
# syntax=docker/dockerfile:1
```

**Stage naming:** Multi-stage builds use descriptive `AS` names: `tool_cargo`, `tool_go`, `devenv`. Never use numeric stage references.

**Layer minimization:** Chain related `RUN` commands with `&&`. One logical operation per `RUN` block. Always clean up package caches in the same layer:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*
```

**No `latest` in FROM for external images.** Pin base images to a specific version tag or digest. Exception: internal devenv images (`devenv-base:latest`) use `latest` because they are locally-built and versioned by the build script.

```dockerfile
# Good
FROM ubuntu:24.04 AS base

# Bad
FROM ubuntu:latest AS base
```

**`--no-install-recommends`** on every `apt-get install`. No exceptions.

**Non-root user:** The final stage must end with `USER devuser`. Root is used only during installation steps.

**Labels:** Images carry labels by type: `LABEL repo-base=true` for the shared foundation, `LABEL devenv=true` for devenv environment images, and `LABEL tools=true` for standalone tool images.

### 2.3 Forbidden Patterns

- `ADD` when `COPY` suffices. Use `ADD` only for URL downloads or tar extraction.
- `COPY . .` — always be explicit about what is copied.
- `chmod 777` — use the minimum necessary permissions.
- `curl | bash` without `-f` (fail on HTTP errors): always `curl -fsSL`.
- Secrets in build args or `ENV`. Use build secrets or mount them at runtime.
- Running services as root in the final image.

### 2.4 COPY --from

When copying from build stages, copy only the artifacts needed. Never copy entire filesystems:

```dockerfile
# Good — specific binary
COPY --from=tool_jq /usr/local/bin/jq /usr/local/bin/jq

# Bad — copying everything
COPY --from=tool_jq / /
```

---

## 3. Security

These are non-negotiable. They apply to all code in the project.

### 3.1 Rules

| Rule                              | Rationale                                                    |
|-----------------------------------|--------------------------------------------------------------|
| SSH binds to `127.0.0.1` only     | Prevent network exposure. Override explicitly if needed.     |
| No Docker socket mounting         | Docker socket = root on the host. Never mount it.            |
| Containers run as `devuser`       | Minimum privilege. Root only during image build.             |
| Config mounts are `:ro`           | Containers must not modify host configuration.               |
| Project mounts are `:rw`          | The project directory is the only writable mount.            |
| `--rm` on all `docker run`        | No orphaned containers. Clean up is automatic.               |
| No hardcoded secrets              | No passwords, tokens, or keys in scripts or Dockerfiles.     |
| `authorized_keys` enables SSH     | SSH access requires explicit opt-in via key presence.        |
| Volumes use `devenv-` prefix and `devenv=true` label | Enables discovery and prevents accidental removal |

### 3.2 Port Binding

Always bind to `127.0.0.1`:

```bash
# Good
-p "127.0.0.1:${port}:22"

# Forbidden
-p "${port}:22"        # Binds to 0.0.0.0
-p "0.0.0.0:${port}:22"
```

---

## 4. General Principles

### 4.1 No Slop

Every line of code must be intentional. The following are not permitted:

- Commented-out code
- `TODO`, `FIXME`, `HACK` markers
- Dead code or unreachable branches
- Placeholder implementations
- "Fix later" shortcuts

If something is not ready, it does not go in. Ship complete or don't ship.

### 4.2 Idempotency

`devenv .` is safe to run any number of times. First call starts, subsequent calls attach. No partial states, no duplicated containers, no port conflicts.

The same principle applies to `build-devenv` and `install-devenv`. Running them twice produces the same result as running them once.

### 4.3 Fail Fast

Validate preconditions at the earliest possible point. Do not proceed with partial state and fail later with a confusing error.

```bash
# Good — check before use
validate_docker
project_path=$(resolve_project_path "${target}") || die "Invalid path: ${target}"

# Bad — let it fail wherever it fails
docker run ... # "Cannot connect to the Docker daemon"
```

### 4.4 Naming

| Element              | Convention                    | Example                    |
|----------------------|-------------------------------|----------------------------|
| Constants            | `UPPER_SNAKE_CASE`, `readonly`| `readonly IMAGE_PREFIX="devenv"` |
| Local variables      | `lower_snake_case`, `local`   | `local container_name`     |
| Functions            | `lower_snake_case`, verb-first| `derive_container_name`    |
| Container names      | `devenv-<parent>-<basename>`  | `devenv-local-api`         |
| Image tags           | `devenv-project-<parent>-<basename>:latest` | `devenv-project-local-api:latest` |
| Dockerfile stages    | `tool_<name>`                 | `tool_cargo`               |

### 4.5 Documentation

- Scripts: one-line file description in the header comment.
- Functions: one-line comment above the function.
- Complex logic: brief inline comment explaining *why*, not *what*.
- Never describe what the code obviously does.

```bash
# Good — explains why
# Pre-allocate to avoid TOCTOU race with docker port assignment.
local port
port=$(allocate_port)

# Bad — describes obvious code
# Set port to the allocated port
local port
port=$(allocate_port)
```

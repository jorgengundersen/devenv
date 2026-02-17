# Implementation Plan: Persistent devenv Runtime

This plan is based on the research document and is intended for a delegated implementation agent. Follow it exactly. All file references are linked for quick access.

## Required Resources (Read First)

- [specs/coding-standard.md](specs/coding-standard.md)
- [specs/spec.md](specs/spec.md)
- [plans/research.md](plans/research.md)
- [plans/summary.md](plans/summary.md)
- [devenv](devenv)
- [build-devenv](build-devenv)
- [install-devenv](install-devenv)
- [README.md](README.md)

## Execution Rules

- Follow the script structure and logging framework in [specs/coding-standard.md](specs/coding-standard.md).
- Use `printf` for return values from primitives, never `echo`.
- Primitives must not call `exit`; only `die()` may exit.
- Keep all edits ASCII-only unless a file already contains non-ASCII (none do).
- Use `getopts` and `case`-based dispatch in `main()`.

---

## Step-by-Step Tasks (with Checkmarks)

### ✅ Task 1: Add shared logging framework to all scripts

- [ ] Update [devenv](devenv) to replace `log()`/`error()` with the standard logging block and `die()`.
- [ ] Update [build-devenv](build-devenv) to replace `log()`/`error()` with the standard logging block and `die()`.
- [ ] Update [install-devenv](install-devenv) to replace `log()`/`error()` with the standard logging block and `die()`.
- [ ] Ensure `DEVENV_LOG_LEVEL` default is `WARNING` and all logs go to stderr.

Pseudocode (shared logging block):

```bash
# --- Logging ---
declare -A _LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
readonly DEVENV_LOG_LEVEL="${DEVENV_LOG_LEVEL:-WARNING}"

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

die() { _log "ERROR" "$@"; exit 1; }
```

Verification:
- [ ] Each script has the same logging block and no old `log()`/`error()` functions remain.

---

### ✅ Task 2: Enforce required script structure and source guard

- [ ] Reorder each script to follow the exact structure: Constants → Logging → Primitives → Commands → Entrypoint.
- [ ] Add source guard to [devenv](devenv), [build-devenv](build-devenv), and [install-devenv](install-devenv).

Pseudocode (source guard):

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

Verification:
- [ ] Each script ends with the source guard and no bare `main "$@"` call.

---

### ✅ Task 3: Update constants to readonly

- [ ] In [devenv](devenv), declare `DEVENV_HOME` and `IMAGE_PREFIX` as `readonly`.
- [ ] In [build-devenv](build-devenv), declare `DEVENV_HOME` and `IMAGE_PREFIX` as `readonly`.
- [ ] In [install-devenv](install-devenv), declare `DEVENV_HOME` as `readonly`.

Verification:
- [ ] All constants match the coding standard and use `readonly`.

---

### ✅ Task 4: Refactor `validate_docker()` to a primitive

- [ ] In [devenv](devenv), make `validate_docker()` return non-zero on failure and log via `log_error` (no `die`).
- [ ] In [build-devenv](build-devenv), do the same.
- [ ] Update all callers to `validate_docker || die "..."` at the command level.

Pseudocode:

```bash
# Validate Docker availability and daemon state.
validate_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        return 1
    fi
}
```

Verification:
- [ ] No primitive calls `die()`.
- [ ] Commands check and fail fast with a clear message.

---

### ✅ Task 5: Implement new primitives in `devenv`

Add each new primitive with one-line comments above each function.

- [ ] `resolve_project_path()`
- [ ] `derive_container_name()` with sanitization and deterministic naming
- [ ] `derive_project_label()`
- [ ] `allocate_port()`
- [ ] `is_container_running()`
- [ ] `build_mounts()` using nameref or global array
- [ ] `build_env_vars()` using nameref or global array
- [ ] `get_image_name()` updated to parent-basename tag and `printf`
- [ ] `ensure_project_image()` updated to parent-basename tag

Pseudocode (key functions):

```bash
# Resolve a path argument to a canonical absolute path.
resolve_project_path() {
    local raw_path="$1"
    local path
    if [[ "${raw_path}" == "." ]]; then
        path="${PWD}"
    elif [[ "${raw_path}" == /* ]]; then
        path="${raw_path}"
    else
        path="${PWD}/${raw_path}"
    fi
    if [[ ! -d "${path}" ]]; then
        return 1
    fi
    path=$(cd "${path}" && pwd)
    printf '%s' "${path}"
}

# Derive a container name from project path (sanitize for Docker names).
derive_container_name() {
    local project_path="$1"
    local parent_name project_name raw_name safe_name
    parent_name="${project_path%/*}"
    parent_name="${parent_name##*/}"
    project_name="${project_path##*/}"
    raw_name="devenv-${parent_name}-${project_name}"
    safe_name=$(printf '%s' "${raw_name}" | sed 's/[^a-zA-Z0-9_.-]/-/g')
    safe_name=$(printf '%s' "${safe_name}" | sed 's/^[^a-zA-Z0-9]//')
    if [[ -z "${safe_name}" ]]; then
        return 1
    fi
    printf '%s' "${safe_name}"
}

# Derive the project label for container metadata.
derive_project_label() {
    local project_path="$1"
    local parent_name project_name
    parent_name="${project_path%/*}"
    parent_name="${parent_name##*/}"
    project_name="${project_path##*/}"
    printf '%s' "${parent_name}/${project_name}"
}

# Allocate a free port on localhost using python3.
allocate_port() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 1
    fi
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
}

# Check if a container is running.
is_container_running() {
    local name="$1"
    docker ps --filter "name=^/${name}$" --format '{{.Names}}' | grep -q .
}

# Build docker mount flags into an array (nameref).
build_mounts() {
    local project_path="$1"
    local project_name="$2"
    local -n mounts_ref="$3"
    mounts_ref=()
    mounts_ref+=("-v" "${project_path}:/workspaces/${project_name}:rw")
    # Add config mounts exactly as current logic, including conditional checks.
}

# Build docker env flags into an array (nameref).
build_env_vars() {
    local -n env_ref="$1"
    env_ref=()
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
        env_ref+=("-e" "SSH_AUTH_SOCK=/ssh-agent")
    fi
    env_ref+=("-e" "TERM")
}
```

Verification:
- [ ] Each primitive uses `local` variables, uses `printf`, and never calls `die()`.
- [ ] Sanitization in `derive_container_name()` ensures Docker-safe names.

---

### ✅ Task 6: Implement container lifecycle primitives in `devenv`

- [ ] Add `start_container()` to run detached with labels and localhost-only SSH binding.
- [ ] Add `attach_container()` to exec a login shell in the running container.

Pseudocode:

```bash
# Start a new persistent container in the background.
start_container() {
    local project_path="$1"
    local container_name="$2"
    local image_name="$3"
    local ssh_port="$4"
    local project_name project_label
    local -a mounts env_vars

    project_name="${project_path##*/}"
    project_label=$(derive_project_label "${project_path}")

    build_mounts "${project_path}" "${project_name}" mounts
    build_env_vars env_vars

    if [[ -n "${ssh_port}" ]]; then
        docker run -d --rm \
            --name "${container_name}" \
            --label devenv=true \
            --label "devenv.project=${project_label}" \
            --user devuser:devuser \
            --workdir "/workspaces/${project_name}" \
            -p "127.0.0.1:${ssh_port}:22" \
            "${mounts[@]}" \
            "${env_vars[@]}" \
            --network bridge \
            "${image_name}" \
            bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
    else
        docker run -d --rm \
            --name "${container_name}" \
            --label devenv=true \
            --label "devenv.project=${project_label}" \
            --user devuser:devuser \
            --workdir "/workspaces/${project_name}" \
            "${mounts[@]}" \
            "${env_vars[@]}" \
            --network bridge \
            "${image_name}" \
            bash -lc "exec sleep infinity"
    fi
}

# Attach to a running container with a login shell.
attach_container() {
    local container_name="$1"
    local project_name="$2"
    docker exec -it --workdir "/workspaces/${project_name}" "${container_name}" bash --login
}
```

Verification:
- [ ] `docker run` includes `-d --rm`, `--name`, `--label`, and localhost-only `-p` binding.
- [ ] The main process is `sleep infinity`.

---

### ✅ Task 7: Implement command functions in `devenv`

Add the command-level functions that orchestrate primitives.

- [ ] `cmd_start()` implements start-or-attach flow and SSH port resolution.
- [ ] `cmd_list()` lists running containers with name, SSH, status, started.
- [ ] `cmd_stop()` stops containers by path, name, or `--all`.

Pseudocode (port resolution and start flow):

```bash
# Start or attach to a development environment.
cmd_start() {
    local port_override=""

    while getopts ":-:" opt; do
        case "${opt}" in
            -)
                case "${OPTARG}" in
                    port)
                        port_override="${!OPTIND}"
                        OPTIND=$((OPTIND + 1))
                        ;;
                    *)
                        die "Unknown option --${OPTARG}"
                        ;;
                esac
                ;;
            ?)
                die "Unknown option"
                ;;
        esac
    done
    shift $((OPTIND - 1))

    local path_arg="${1:-.}"
    local project_path container_name project_name image_name ssh_port

    project_path=$(resolve_project_path "${path_arg}") || die "Project path does not exist: ${path_arg}"
    container_name=$(derive_container_name "${project_path}") || die "Unable to derive container name"
    project_name="${project_path##*/}"

    if is_container_running "${container_name}"; then
        if [[ -n "${port_override}" ]]; then
            log_warning "Container already running; --port flag ignored"
        fi
        log_info "Attaching to ${container_name}"
        attach_container "${container_name}" "${project_name}"
        return
    fi

    image_name=$(get_image_name "${project_path}")
    ensure_project_image "${project_path}"

    if [[ -n "${port_override}" ]]; then
        ssh_port="${port_override}"
    elif [[ -n "${DEVENV_SSH_PORT:-}" ]]; then
        ssh_port="${DEVENV_SSH_PORT}"
    else
        ssh_port=$(allocate_port) || die "Install python3 or set DEVENV_SSH_PORT"
    fi

    start_container "${project_path}" "${container_name}" "${image_name}" "${ssh_port}"
    if [[ -n "${ssh_port}" ]]; then
        printf '%s\n' "SSH: 127.0.0.1:${ssh_port}"
    fi
    attach_container "${container_name}" "${project_name}"
}
```

Pseudocode (`cmd_list`):

```bash
# List running devenv containers.
cmd_list() {
    printf '%-24s %-20s %-10s %s\n' "NAME" "SSH" "STATUS" "STARTED"
    docker ps --filter label=devenv=true --format '{{.Names}}|{{.Ports}}|{{.Status}}|{{.RunningFor}}' \
        | while IFS='|' read -r name ports status started; do
            local ssh
            ssh=$(printf '%s' "${ports}" | sed -n 's/.*127.0.0.1:\([0-9]*\)->22\/tcp.*/127.0.0.1:\1/p')
            printf '%-24s %-20s %-10s %s\n' "${name}" "${ssh}" "${status}" "${started}"
        done
}
```

Pseudocode (`cmd_stop`):

```bash
# Stop containers by path, name, or --all.
cmd_stop() {
    local target="${1:-}"

    if [[ "${target}" == "--all" ]]; then
        local ids
        ids=$(docker ps -q --filter label=devenv=true)
        if [[ -z "${ids}" ]]; then
            log_info "No devenv containers running"
            return
        fi
        docker stop ${ids}
        return
    fi

    if [[ -z "${target}" ]]; then
        die "stop requires a path, name, or --all"
    fi

    if [[ "${target}" == "." || "${target}" == */* || -d "${target}" ]]; then
        local project_path container_name
        project_path=$(resolve_project_path "${target}") || die "Project path does not exist: ${target}"
        container_name=$(derive_container_name "${project_path}") || die "Unable to derive container name"
        if ! is_container_running "${container_name}"; then
            log_warning "No running container: ${container_name}"
            return
        fi
        docker stop "${container_name}"
        return
    fi

    docker stop "${target}"
}
```

Verification:
- [ ] `cmd_start` honors `--port` > `DEVENV_SSH_PORT` > `allocate_port` priority.
- [ ] `cmd_list` prints a header even when no containers exist.
- [ ] `cmd_stop --all` handles the empty case gracefully.

---

### ✅ Task 8: Update `usage()` in `devenv`

- [ ] Replace help text to reflect new commands and options per the spec.
- [ ] Include `list`, `stop`, `stop --all`, and `--port` with examples.
- [ ] Add a short note on the persistent container lifecycle.

Verification:
- [ ] Help output matches [specs/spec.md](specs/spec.md) runtime interface.

---

### ✅ Task 9: Update `main()` dispatch in `devenv`

- [ ] Implement `case`-based subcommand dispatch.
- [ ] Ensure `help`, `-h`, and `--help` call `usage()`.
- [ ] Default to `cmd_start` when the first arg is a path or `.`.

Pseudocode:

```bash
main() {
    validate_docker || die "Docker is not available. Install Docker and try again."

    local command="${1:-.}"
    case "${command}" in
        list)
            shift
            cmd_list "$@"
            ;;
        stop)
            shift
            cmd_stop "$@"
            ;;
        help|-h|--help)
            usage
            ;;
        *)
            cmd_start "$@"
            ;;
    esac
}
```

Verification:
- [ ] `devenv list` and `devenv stop` route correctly.
- [ ] `devenv .` still works.

---

### ✅ Task 10: Update image naming in `build-devenv`

- [ ] Update project image tag to `devenv-project-<parent>-<basename>:latest`.
- [ ] Replace any `basename` invocations with parameter expansion where possible.
- [ ] Replace logging calls with `log_info` or `log_debug`.

Verification:
- [ ] Project images use parent-basename naming and match `devenv`.

---

### ✅ Task 11: Update `install-devenv` for logging and source guard

- [ ] Replace `log`/`error` with the shared logging framework.
- [ ] Add source guard.

Verification:
- [ ] Script conforms to structure and logging standard.

---

### ✅ Task 12: Update documentation in `README.md`

- [ ] Update the commands section to include `list`, `stop`, and `--port`.
- [ ] Document the persistent container model and `docker exec` attachment.
- [ ] Document SSH port priority and localhost-only binding.

Verification:
- [ ] README matches the updated behavior and spec.

---

### ✅ Task 13: End-to-end verification

Run these checks after implementation:

```bash
# 1. Start and attach
mkdir -p /tmp/devenv-plan-test
cd /tmp/devenv-plan-test
mkdir -p project-a project-b

devenv project-a
# Verify: container starts, SSH port printed

# 2. Attach to existing container
# In another terminal:
devenv project-a
# Verify: attaches without starting a new container

# 3. List running containers
devenv list
# Verify: two columns include SSH port and started time

# 4. Start with explicit port
devenv --port 3333 project-b
# Verify: SSH binding is 127.0.0.1:3333

# 5. Stop by path and by name
devenv stop project-a
devenv stop devenv-<parent>-project-b

devenv stop --all
# Verify: no running devenv containers
```

---

## Completion Checklist

- [ ] All scripts follow the required structure.
- [ ] Logging framework is consistent across all scripts.
- [ ] `devenv` runtime implements persistent container model with labels.
- [ ] Image naming is consistent between `devenv` and `build-devenv`.
- [ ] Documentation updated and accurate.
- [ ] Manual verification steps pass.

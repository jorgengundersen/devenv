# Implementation Plan: Persistent Docker Volumes

This plan implements `specs/persistent-volumes.md` across the codebase. Each task references exact files, line numbers, and content so the implementing agent can execute without ambiguity.

**Source spec:** `specs/persistent-volumes.md`
**Research:** `plans/current/research.md`

---

## Phase 1: Runtime Script (`devenv`)

### Task 1.1: Add volume constants

- [ ] Add four `readonly` volume constants to `devenv` immediately after the existing `readonly IMAGE_PREFIX="devenv"` on line 7.

**File:** `devenv`
**Location:** After line 7 (`readonly IMAGE_PREFIX="devenv"`)
**Insert:**

```bash
readonly VOLUME_DATA="devenv-data"
readonly VOLUME_CACHE="devenv-cache"
readonly VOLUME_STATE="devenv-state"
readonly VOLUME_TVIM_LOCK="devenv-tvim-lock"
```

**Coding standard reference:** `specs/coding-standard.md` section 1.8 -- constants use `readonly`, `UPPER_SNAKE_CASE`, placed in the `# --- Constants ---` block.

---

### Task 1.2: Add volume provisioning primitive

- [ ] Add a new primitive function `ensure_volumes()` to the `# --- Primitives ---` section of `devenv`. Place it after the existing `build_env_vars()` function (which ends around line 215) and before the `get_image_name()` function (line 218).

**File:** `devenv`
**Location:** After `build_env_vars()`, before `get_image_name()`

**Content:**

```bash
# Create devenv-managed Docker volumes if they do not already exist.
ensure_volumes() {
    local vol
    for vol in "${VOLUME_DATA}" "${VOLUME_CACHE}" "${VOLUME_STATE}" "${VOLUME_TVIM_LOCK}"; do
        if ! docker volume inspect "${vol}" >/dev/null 2>&1; then
            docker volume create --label devenv=true "${vol}" >/dev/null
            log_info "Created volume: ${vol}"
        fi
    done
}
```

**Rationale:** Volumes are provisioned at startup (not lazily) to guarantee the `devenv=true` label is applied from first run. Docker does auto-create volumes on `docker run -v`, but those auto-created volumes do not carry custom labels.

**Coding standard reference:** Primitives never call `die()`. They return non-zero on failure. One function, one job. All variables use `local`.

---

### Task 1.3: Add named volume mounts to `build_mounts()`

- [ ] Insert three named volume mount lines at the beginning of `build_mounts()`, immediately after the `mounts_ref=()` initialization (line 161) and before the project bind mount (line 162).

**File:** `devenv`
**Location:** Inside `build_mounts()` (starts at line 156). Insert after `mounts_ref=()` (line 161) and before `mounts_ref+=("-v" "${project_path}:/workspaces/${project_name}:rw")` (line 162).

**Insert these lines between the two existing lines:**

```bash
    # Persistent named volumes (shared across all devenv containers).
    mounts_ref+=("-v" "${VOLUME_DATA}:/home/devuser/.local/share")
    mounts_ref+=("-v" "${VOLUME_CACHE}:/home/devuser/.cache")
    mounts_ref+=("-v" "${VOLUME_STATE}:/home/devuser/.local/state")
```

**Why before bind mounts:** Docker processes mounts in order. Named volumes must come first so that fine-grained file-level bind mounts (like `opencode/auth.json` at line 191-192) overlay correctly on top of the volume.

**Verify:** The existing `opencode/auth.json` read-only file bind at lines 191-192 remains unchanged. It overlays on top of the `devenv-data` volume at `/home/devuser/.local/share`.

---

### Task 1.4: Change tvim mount to `:ro` and add lockfile volume overlay

- [ ] Change the tvim config mount from `:rw` to `:ro` on line 177 of `devenv`.
- [ ] Add a named volume overlay for the lockfile path immediately after the tvim mount line.

**File:** `devenv`

**Step A -- Change line 177 from:**

```bash
        mounts_ref+=("-v" "${HOME}/.config/tvim:/home/devuser/.config/tvim:rw")
```

**To:**

```bash
        mounts_ref+=("-v" "${HOME}/.config/tvim:/home/devuser/.config/tvim:ro")
        mounts_ref+=("-v" "${VOLUME_TVIM_LOCK}:/home/devuser/.config/tvim/lazy-lock.json")
```

**Rationale:** The tvim config directory is host config and should be `:ro` per the security principle. The plugin manager (lazy.nvim) needs to write `lazy-lock.json` for version pins. A named volume overlaid on the lockfile path allows those writes to persist without granting write access to the entire config directory.

**Trade-off:** Lockfile changes inside the container do not automatically flow back to the host dotfiles repo. Manual extraction is needed if the user wants to commit updated pins.

---

### Task 1.5: Call `ensure_volumes()` in `cmd_start()`

- [ ] Add a call to `ensure_volumes` inside `cmd_start()`, after the Docker availability check has already passed (via `main()`) and before `start_container()` is called.

**File:** `devenv`
**Location:** Inside `cmd_start()`, place the call immediately before the `start_container` call (line 367). The call should only happen when a new container is being started (not when attaching to an existing one). Insert it in the "not running" branch, just before `start_container`.

**Insert before the `start_container` call (line 367):**

```bash
    ensure_volumes
```

**Context:** The code flow at this point is:
1. `project_path` is resolved
2. `container_name` is derived
3. If container is running, attach and return
4. Image is resolved and ensured
5. SSH port is determined
6. **<-- INSERT `ensure_volumes` HERE -->**
7. `start_container` is called

This guarantees volumes exist with labels before `docker run` references them.

---

### Task 1.6: Add `devenv volume` command family

This task adds four new functions and updates the `usage()` text and `main()` dispatcher. All new functions go in the `# --- Commands ---` section of `devenv`, after the existing `cmd_stop()` function (which ends around line 423).

#### 1.6a: Add usage text for volume commands

- [ ] Update the `usage()` function (lines 37-55) to include volume commands.

**File:** `devenv`
**Location:** Inside the `usage()` heredoc, after the `stop --all` line and before the `help` line.

**Add these lines in the Commands section:**

```
    volume list             List devenv volumes with size
    volume rm <name>        Remove a specific devenv volume
    volume rm --all         Remove all devenv volumes
```

**Add this line in the Options section (after `--port`):**

```
    --force                 Skip confirmation prompt (for volume rm)
```

#### 1.6b: Add `is_volume_in_use()` primitive

- [ ] Add a primitive to check if a volume is mounted by any running container. Place it near the other primitives (after `ensure_volumes()`).

**File:** `devenv`
**Location:** After `ensure_volumes()`, in the `# --- Primitives ---` section.

**Content:**

```bash
# Check if a Docker volume is mounted by any running container.
is_volume_in_use() {
    local volume_name="$1"
    docker ps -q --filter "volume=${volume_name}" | grep -q .
}
```

#### 1.6c: Add `cmd_volume()` command dispatcher

- [ ] Add `cmd_volume()` function in the `# --- Commands ---` section, after `cmd_stop()`.

**File:** `devenv`
**Location:** After `cmd_stop()` (ends around line 423), before `# --- Entrypoint ---`.

**Content:**

```bash
# Manage devenv persistent volumes.
cmd_volume() {
    local subcommand="${1:-}"
    shift || true

    case "${subcommand}" in
        list) cmd_volume_list ;;
        rm)   cmd_volume_rm "$@" ;;
        *)    die "Unknown volume command: ${subcommand:-<none>}. Use: list, rm" ;;
    esac
}

# List devenv-managed volumes with size.
cmd_volume_list() {
    local volumes
    volumes=$(docker volume ls --filter label=devenv=true --format '{{.Name}}')
    if [[ -z "${volumes}" ]]; then
        log_info "No devenv volumes found"
        return
    fi

    printf '%-24s %s\n' "NAME" "SIZE"

    local vol size
    while IFS= read -r vol; do
        size=$(docker system df -v --format '{{range .Volumes}}{{if eq .Name "'"${vol}"'"}}{{.Size}}{{end}}{{end}}' 2>/dev/null)
        printf '%-24s %s\n' "${vol}" "${size:-unknown}"
    done <<< "${volumes}"
}

# Remove devenv volumes with safety checks.
cmd_volume_rm() {
    local force=false
    local remove_all=false
    local targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            --all)   remove_all=true; shift ;;
            -*)      die "Unknown option: $1" ;;
            *)       targets+=("$1"); shift ;;
        esac
    done

    if "${remove_all}"; then
        if [[ ${#targets[@]} -gt 0 ]]; then
            die "Cannot specify volume names with --all"
        fi
        local all_volumes
        all_volumes=$(docker volume ls --filter label=devenv=true --format '{{.Name}}')
        if [[ -z "${all_volumes}" ]]; then
            log_info "No devenv volumes to remove"
            return
        fi
        local -a vol_array
        readarray -t vol_array <<< "${all_volumes}"
        targets=("${vol_array[@]}")
    fi

    if [[ ${#targets[@]} -eq 0 ]]; then
        die "Specify a volume name or use --all"
    fi

    # In-use check for all targets first.
    local vol
    for vol in "${targets[@]}"; do
        if is_volume_in_use "${vol}"; then
            die "Volume '${vol}' is mounted by a running container. Stop the container first."
        fi
        if ! docker volume inspect "${vol}" >/dev/null 2>&1; then
            die "Volume '${vol}' does not exist"
        fi
    done

    # Confirmation prompt unless --force.
    if ! "${force}"; then
        local prompt
        if "${remove_all}"; then
            prompt="Remove all devenv volumes ($(IFS=', '; printf '%s' "${targets[*]}"))? [y/N]: "
        else
            prompt="Remove volume '${targets[*]}'? [y/N]: "
        fi
        local answer
        printf '%s' "${prompt}" >&2
        read -r answer
        if [[ "${answer}" != [yY] ]]; then
            log_info "Cancelled"
            return
        fi
    fi

    for vol in "${targets[@]}"; do
        docker volume rm "${vol}" >/dev/null
        log_info "Removed volume: ${vol}"
    done
}
```

**Behavioral requirements (from spec):**
- `is_volume_in_use` check always applies, even with `--force`.
- `--force` only skips the interactive confirmation prompt.
- Default confirmation answer is `N` (no). Only `y` or `Y` proceeds.
- `volume list` uses `docker volume ls --filter label=devenv=true` for discovery, then `docker system df -v` with Go template for per-volume sizes.

#### 1.6d: Add `volume` branch to `main()` dispatcher

- [ ] Add a `volume)` case to the `main()` function's `case` statement.

**File:** `devenv`
**Location:** Inside `main()` at the `case` block (line 429). Add a new branch after `stop)` and before `help|-h|--help)`.

**Add:**

```bash
        volume)
            shift
            cmd_volume "$@"
            ;;
```

---

## Phase 2: Documentation Updates

### Task 2.1: Update `README.md` -- command list

- [ ] Add `volume` commands to the devenv command examples in `README.md`.

**File:** `README.md`
**Location:** The devenv command block starting around line 134. Add after the `devenv stop --all` line (line 140).

**Add these lines before the closing triple backticks:**

```bash
devenv volume list             # List devenv volumes with size
devenv volume rm <name>        # Remove a specific volume
devenv volume rm --all         # Remove all devenv volumes
```

---

### Task 2.2: Update `README.md` -- Configuration Mount Points table

- [ ] Add a new section about persistent volumes below the existing Configuration Mount Points table.

**File:** `README.md`
**Location:** After the Configuration Mount Points table (around line 178) and before the `tvim` section.

**Add a new subsection:**

```markdown
## Persistent Volumes

Runtime state is stored in named Docker volumes that persist across container restarts:

| Volume | Container Mount Point | Purpose |
|--------|----------------------|---------|
| `devenv-data` | `/home/devuser/.local/share` | Installed plugins, tree-sitter parsers, tool databases |
| `devenv-cache` | `/home/devuser/.cache` | Download caches (uv, cargo, npm) |
| `devenv-state` | `/home/devuser/.local/state` | Log files, command history, session state |
| `devenv-tvim-lock` | `/home/devuser/.config/tvim/lazy-lock.json` | Plugin manager lockfile |

Volumes are shared across all devenv containers and labeled `devenv=true` for management.
```

---

### Task 2.3: Update `README.md` -- tvim section

- [ ] Update the tvim description to reflect the `:ro` mount with lockfile volume overlay.

**File:** `README.md`
**Location:** The tvim mount description near line 180: `tvim is mounted read-write to allow plugin installs and lockfile updates.`

**Change to:**

```markdown
`tvim` is mounted read-only. Plugin data (installed plugins, tree-sitter parsers) persists in the `devenv-data` volume at `~/.local/share/tvim`. The `lazy-lock.json` lockfile is overlaid with a named volume (`devenv-tvim-lock`) so updates persist without granting write access to the host config directory.
```

Also update the Configuration Mount Points table row for tvim if it says "read-write" -- it should not indicate `:rw` anymore. The table in `README.md` at line 172 does not explicitly state the mode per row, but the paragraph above it at line 180 does. Update only the paragraph.

---

### Task 2.4: Update `README.md` -- Security section

- [ ] Add a note about volume naming and labels to the Security section.

**File:** `README.md`
**Location:** Security section (starts around line 208). Add a new bullet point.

**Add:**

```markdown
- Persistent volumes use the `devenv-` prefix and carry the `devenv=true` label for discovery and safe cleanup
```

---

## Phase 3: Spec Sync

### Task 3.1: Update `specs/spec.md` -- Configuration Mount Points

- [ ] Update the tvim mount description in the Configuration Mount Points section to reflect `:ro`.

**File:** `specs/spec.md`
**Location:** Line 356: `Tool configurations are provided by the host system and mounted at container runtime. Mount points use equivalent paths in the container. Most mounts are read-only; tvim is read-write to allow plugin installs and lockfile updates:`

**Change to:**

```markdown
Tool configurations are provided by the host system and mounted at container runtime. Mount points use equivalent paths in the container. All config mounts are read-only:
```

---

### Task 3.2: Update `specs/spec.md` -- Docker Run Command Structure

- [ ] Add the three named volume mounts and the tvim lockfile overlay to the Docker Run Command Structure example.

**File:** `specs/spec.md`
**Location:** The `docker run` example starting at line 497. Add volume mounts after the `--label` lines and before the project bind mount.

**Add these lines after `--label devenv.project=<parent>/<project> \`:**

```bash
  -v "devenv-data:/home/devuser/.local/share" \
  -v "devenv-cache:/home/devuser/.cache" \
  -v "devenv-state:/home/devuser/.local/state" \
```

**Also change the tvim mount line (line 508) from:**

```bash
    -v "$HOME/.config/tvim/:/home/devuser/.config/tvim/:rw" \
```

**To:**

```bash
  -v "$HOME/.config/tvim/:/home/devuser/.config/tvim/:ro" \
  -v "devenv-tvim-lock:/home/devuser/.config/tvim/lazy-lock.json" \
```

**Also update the flags table (around line 539):**

Change `| `-v` (configs) | Mount tool configs from host (mostly read-only; tvim is read-write) |`

To: `| `-v` (configs) | Mount tool configs from host (read-only) |`

Add a new row: `| `-v` (volumes) | Persistent named volumes for XDG data, cache, and state |`

---

### Task 3.3: Update `specs/spec.md` -- Command Structure

- [ ] Add `devenv volume` commands to the Command Structure section.

**File:** `specs/spec.md`
**Location:** Command Structure section starting at line 420. Add after the `devenv help` line.

**Add:**

```
devenv volume list            # list devenv volumes with size
devenv volume rm <name>       # remove a specific volume
devenv volume rm --all        # remove all devenv volumes
devenv volume rm --force ...  # skip confirmation prompt
```

---

### Task 3.4: Update `specs/coding-standard.md` -- Security rules table

- [ ] Add a row to the security rules table for volume naming and labels.

**File:** `specs/coding-standard.md`
**Location:** Security rules table at section 3.1 (around lines 362-371).

**Add a new row to the table:**

```markdown
| Volumes use `devenv-` prefix and `devenv=true` label | Enables discovery and prevents accidental removal |
```

---

## Phase 4: Contributor Guidance

### Task 4.1: Update `CONTRIBUTING.md` -- mount point guidance

- [ ] Update the mount point guidance section to distinguish between config bind mounts and persistent named volumes.

**File:** `CONTRIBUTING.md`
**Location:** Section 3 "Adding a mount point" (starts around line 206). Add a subsection after the existing mount point instructions.

**Add a new subsection before Section 4:**

```markdown
### Persistent volumes vs config mounts

The devenv runtime uses two types of mounts:

- **Config bind mounts (`:ro`)** -- host configuration directories/files mounted read-only into the container. These are managed in `build_mounts()` and described in Section 3 above.
- **Persistent named volumes** -- Docker-managed volumes for runtime state (XDG data, cache, state). These are defined as constants (`VOLUME_DATA`, `VOLUME_CACHE`, `VOLUME_STATE`, `VOLUME_TVIM_LOCK`) and provisioned by `ensure_volumes()` in the `devenv` script.

When a tool needs to persist runtime data (caches, plugins, logs, history), it writes to the appropriate XDG directory inside the container. The named volumes automatically persist this data. No code changes are needed for new tools that follow XDG conventions.

The `devenv volume` commands (`list`, `rm`, `rm --all`, `rm --force`) provide operational visibility and cleanup for these volumes.
```

---

## Phase 5: Verification

### Task 5.1: ShellCheck validation

- [ ] Run `shellcheck devenv` and confirm zero warnings.

**Command:**

```bash
shellcheck devenv
```

If `shellcheck` is not installed on the host, run it via Docker:

```bash
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable devenv
```

---

### Task 5.2: Functional smoke test

- [ ] Verify the implementation works end-to-end.

**Test sequence:**

```bash
# 1. Confirm volumes do not exist yet
docker volume ls --filter label=devenv=true

# 2. Start a container (should create volumes)
devenv .

# 3. Inside the container, verify mount points exist
ls -la ~/.local/share/
ls -la ~/.cache/
ls -la ~/.local/state/
ls -la ~/.config/tvim/lazy-lock.json  # if tvim config exists on host

# 4. Exit the container

# 5. Verify volumes are listed
devenv volume list

# 6. Stop the container
devenv stop .

# 7. Test volume rm with confirmation
devenv volume rm devenv-cache
# Answer N, verify no removal
# Answer y, verify removal

# 8. Test volume rm --force
devenv volume rm --force devenv-state

# 9. Test volume rm --all
devenv volume rm --all

# 10. Verify all volumes removed
devenv volume list
```

---

### Task 5.3: Mount ordering verification

- [ ] Verify that the `opencode/auth.json` file bind mount overlays correctly on the `devenv-data` volume.

**Test:**

```bash
# Start a container
devenv .

# Inside the container, check the file exists and is read-only
ls -la ~/.local/share/opencode/auth.json
# Should show the host's auth.json, not an empty path from the volume

# Verify other files in ~/.local/share are writable (from the volume)
touch ~/.local/share/test-write && rm ~/.local/share/test-write
```

---

### Task 5.4: In-use protection verification

- [ ] Verify that `devenv volume rm` refuses to remove volumes mounted by running containers.

**Test:**

```bash
# Start a container
devenv .
# Detach (Ctrl+D or exit)

# Attempt to remove a volume while container is running
devenv volume rm --force devenv-data
# Expected: error message about volume being in use

# Stop the container
devenv stop .

# Now removal should succeed
devenv volume rm --force devenv-data
```

---

## Implementation Order

Execute phases sequentially: Phase 1 (all tasks) -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5.

Within Phase 1, execute tasks 1.1 through 1.6 in order since later tasks depend on earlier ones (e.g., 1.3 uses constants from 1.1, 1.5 calls the function from 1.2, 1.6d references 1.6c).

Phases 2, 3, and 4 are documentation-only and can be done in any order relative to each other, but must come after Phase 1 since they describe the implemented behavior.

Phase 5 is verification and must be last.

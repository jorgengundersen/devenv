# Persistent Docker Volumes

Persistent named Docker volumes provide shared, writable storage for tool state across all devenv containers. This eliminates cold-start costs (plugin installs, parser builds, cache population) after the first container session and preserves log files for troubleshooting.

## Motivation

Tools installed in the devenv image generate runtime state that is expensive to recreate:

- **nvim** installs plugins and builds tree-sitter parsers on first launch.
- **uv**, **cargo**, and **npm** download packages into local caches.
- **opencode** and **gh-copilot** write log files useful for debugging.

Without persistent storage, every new container pays these costs again. Bind-mounting the host `~/.local/share` into the container would solve persistence but grants the container write access to host state, violating the read-only config mount principle.

Named Docker volumes solve both problems: the container has a writable filesystem that persists across `docker stop` / `docker run` cycles, and the host filesystem is not exposed.

## Design

### XDG Base Directory Layout

Three named volumes map to the [XDG Base Directory](https://specifications.freedesktop.org/basedir-spec/latest/) locations inside the container:

| Volume Name | Container Mount Point | XDG Variable | Purpose |
|-------------|----------------------|--------------|---------|
| `devenv-data` | `/home/devuser/.local/share` | `XDG_DATA_HOME` | Installed plugins, tree-sitter parsers, tool databases |
| `devenv-cache` | `/home/devuser/.cache` | `XDG_CACHE_HOME` | Download caches (uv, cargo, npm, pip) |
| `devenv-state` | `/home/devuser/.local/state` | `XDG_STATE_HOME` | Log files, command history, session state |

Three separate volumes rather than a single volume at `~/.local` because:

- Caches can be wiped independently without losing installed plugins or logs.
- Logs can be inspected or rotated without affecting tool data.
- Each volume can be sized, backed up, or removed in isolation.

### Volume Naming

Volume names use the `devenv-` prefix for consistency with the existing naming conventions (container names: `devenv-<parent>-<project>`, image tags: `devenv-project-<parent>-<project>`).

The three volume names are constants:

```bash
readonly VOLUME_DATA="devenv-data"
readonly VOLUME_CACHE="devenv-cache"
readonly VOLUME_STATE="devenv-state"
```

### Shared Across All Containers

All devenv containers mount the same three volumes. This is intentional:

- Tool state (nvim plugins, tree-sitter parsers) is identical regardless of project.
- The first container to launch pays the installation cost. All subsequent containers see the already-populated volumes immediately.
- Log files from all projects accumulate in one place for centralized troubleshooting.

### Volume Labels

All devenv-managed volumes carry the `devenv=true` label, consistent with how containers and images are labeled:

```bash
docker volume create --label devenv=true devenv-data
```

This enables filtering:

```bash
docker volume ls --filter label=devenv=true
```

### Volume Lifecycle

- **Creation:** Docker creates named volumes automatically when referenced in `docker run -v <name>:<path>`. No explicit `docker volume create` is required at container start. Volumes are created with labels during an explicit provisioning step or on first reference.
- **Persistence:** Volumes survive `docker stop` and `docker rm`. The `--rm` flag on `docker run` removes the container but does not remove named volumes.
- **Destruction:** Volumes are removed only by explicit user action (`docker volume rm` or `devenv volume rm`). Automated cleanup (`docker system prune`, `docker volume prune`) removes only unlabeled or unused volumes; the `devenv=true` label provides a filter handle but does not prevent pruning by default. Users should be aware of this when running broad prune commands.

### Mount Ordering with Bind Mounts

Docker processes volume and bind mounts in order. A named volume mounted at `/home/devuser/.local/share` and a bind mount at `/home/devuser/.local/share/opencode/auth.json` coexist correctly: the bind mount overlays the specific file path on top of the volume. The existing `opencode/auth.json` read-only bind mount continues to work unchanged.

## Contents by Volume

### devenv-data (`~/.local/share`)

| Tool | Path Within Volume | Contents |
|------|-------------------|----------|
| nvim | `nvim/` | Plugin data, tree-sitter parsers, shada |
| gh | `gh/` | Extension data, local state |
| opencode | `opencode/` | Session data (auth.json is still bind-mounted `:ro` from host) |

### devenv-cache (`~/.cache`)

| Tool | Path Within Volume | Contents |
|------|-------------------|----------|
| uv | `uv/` | Downloaded Python packages |
| cargo | `cargo/` | Crate downloads, build artifacts |
| npm/node | `npm/`, `node/` | Package downloads |
| nvim | `nvim/` | Plugin manager download cache |

### devenv-state (`~/.local/state`)

| Tool | Path Within Volume | Contents |
|------|-------------------|----------|
| nvim | `nvim/` | Log files, undo history |
| opencode | `opencode/` | Session logs |
| gh-copilot | `gh-copilot/` | Interaction logs |
| bash | `bash/` | Command history (`bash_history`) |

## Implementation

### Changes to `build_mounts()`

The `build_mounts()` primitive in `devenv` adds three volume mount flags:

```bash
# Persistent named volumes (shared across all devenv containers).
mounts_ref+=("-v" "${VOLUME_DATA}:/home/devuser/.local/share")
mounts_ref+=("-v" "${VOLUME_CACHE}:/home/devuser/.cache")
mounts_ref+=("-v" "${VOLUME_STATE}:/home/devuser/.local/state")
```

These lines are placed before the existing bind mounts so that specific file-level bind mounts (like `opencode/auth.json`) overlay correctly.

### Changes to `start_container()`

No changes required. The mount flags are built by `build_mounts()` and passed to `docker run` via the existing `"${mounts[@]}"` expansion.

### Changes to Security Rules

The coding standard security table gains one entry:

| Rule | Rationale |
|------|-----------|
| Volumes are named with `devenv-` prefix and labeled `devenv=true` | Enables discovery and prevents accidental removal |

The existing rules remain unchanged. Named volumes do not expose host state and do not require relaxing the read-only config mount principle. The project directory remains the only host-writable bind mount.

### Docker Run Command Structure

Updated `docker run` with volume mounts (new lines marked):

```bash
docker run -d --rm \
  --name devenv-<parent>-<project> \
  --user devuser:devuser \
  --workdir /home/devuser/<relative_project_path> \
  --label devenv=true \
  --label devenv.project=<parent>/<project> \
  -v "devenv-data:/home/devuser/.local/share" \        # NEW
  -v "devenv-cache:/home/devuser/.cache" \              # NEW
  -v "devenv-state:/home/devuser/.local/state" \        # NEW
  -v "<project_path>:/home/devuser/<relative_project_path>:rw" \
  -v "$HOME/.bashrc:/home/devuser/.bashrc:ro" \
  -v "$HOME/.config/nvim/:/home/devuser/.config/nvim/:ro" \
  -v "$HOME/.config/gh/:/home/devuser/.config/gh/:ro" \
  -v "$HOME/.config/opencode/:/home/devuser/.config/opencode/:ro" \
  -v "$HOME/.local/share/opencode/auth.json:/home/devuser/.local/share/opencode/auth.json:ro" \
  ...
  <image_name> \
  bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
```

### Volume Management Commands

An optional `devenv volume` subcommand provides visibility into persistent state:

```
devenv volume list                 # List devenv volumes with size
devenv volume rm <name>            # Remove a specific volume (interactive confirmation)
devenv volume rm --force <name>    # Remove a specific volume (skip confirmation)
devenv volume rm --all             # Remove all devenv volumes (interactive confirmation)
devenv volume rm --force --all     # Remove all devenv volumes (skip confirmation)
```

`devenv volume list` output:

```
NAME              SIZE
devenv-data       245MB
devenv-cache      1.2GB
devenv-state      12MB
```

#### `devenv volume rm` Behavior

**In-use check:** Before any removal, the command checks whether the target volume is mounted by a running container. If it is, the command refuses to remove it and reports an error. This check applies regardless of `--force`.

**Interactive confirmation (default):** Without `--force`, the command prompts the user for confirmation before removing:

```
Remove volume 'devenv-cache'? [y/N]: y
```

```
Remove all devenv volumes (devenv-data, devenv-cache, devenv-state)? [y/N]: y
```

The default answer is `N` (no). Only `y` or `Y` proceeds with removal.

**Force mode (`--force`):** Skips the interactive confirmation prompt and proceeds directly to removal. The in-use check still applies; `--force` does not override it.

## Ownership and Permissions

Named volumes are initialized empty on first use. When the container writes to the mount point, files are created with the UID/GID of the container process (`devuser`, typically 1000:1000). Since all devenv containers run as the same `devuser` with the same UID/GID, ownership is consistent across containers. No `chown` at runtime is required.

If `USER_UID` or `USER_GID` build arguments differ between images, file ownership mismatches may occur. This is an existing constraint of the devenv architecture and is not introduced by persistent volumes.

## Inspecting Volume Contents

Volumes are Docker-managed and not directly visible on the host filesystem. To inspect contents:

```bash
# List files in the state volume (logs)
docker run --rm -v devenv-state:/data alpine ls -laR /data/

# Interactive shell for browsing
docker run --rm -it -v devenv-state:/data alpine sh

# Copy a log file to the host
docker run --rm -v devenv-state:/data -v "$PWD:/out" alpine cp /data/nvim/log /out/nvim.log
```

The `devenv volume` subcommand provides a more convenient interface for common inspection tasks.

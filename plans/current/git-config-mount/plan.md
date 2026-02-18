# Implementation Plan: Git Config & Home-Relative Project Mount

## Background

The host machine uses `includeIf "gitdir:~/Repos/..."` directives in `~/.gitconfig` to switch git identities (name, email, signing key) based on which directory tree a repository lives in. Currently, devenv containers:

1. Mount projects at `/workspaces/<project_name>` — a flat path that does not preserve the host's `$HOME`-relative directory structure.
2. Do not mount any git configuration files (`~/.gitconfig`, `~/.gitconfig-*`).

This means git inside a container has no user identity, and even if configs were mounted, the `includeIf "gitdir:~/..."` conditions would never match.

## Solution

Mirror the `$HOME`-relative project path inside the container and mount host git configs as read-only. Since `~` in git config resolves to the current user's `$HOME` at runtime, the `includeIf` directives work automatically across both environments:

- Host: `~/Repos/github.com/jorgengundersen/my_project` → `/home/e773438/Repos/github.com/jorgengundersen/my_project`
- Container: `~/Repos/github.com/jorgengundersen/my_project` → `/home/devuser/Repos/github.com/jorgengundersen/my_project`

## Required Reading

- [specs/spec.md](../../specs/spec.md) — current spec (all `/workspaces` references)
- [specs/coding-standard.md](../../specs/coding-standard.md) — bash coding standard
- [bin/devenv](../../bin/devenv) — runtime launcher (primary target)
- [docker/devenv/Dockerfile.base](../../docker/devenv/Dockerfile.base) — base image
- [docker/devenv/templates/Dockerfile.project](../../docker/devenv/templates/Dockerfile.project) — project template

## Execution Rules

- Follow [specs/coding-standard.md](../../specs/coding-standard.md) strictly.
- Run `shellcheck` on any modified bash script.
- All git config mounts must be `:ro` (read-only).
- Do not break existing functionality — all current mounts must continue to work.

---

## Tasks

### Task 1: Update project mount path in `bin/devenv`

Change the project bind mount from `/workspaces/<project_name>` to the `$HOME`-relative equivalent path inside the container.

**File:** `bin/devenv`

- [ ] In `build_mounts()` (~line 174), replace the project mount:
  ```bash
  # Old:
  mounts_ref+=("-v" "${project_path}:/workspaces/${project_name}:rw")

  # New: mirror host $HOME-relative path into container home
  local relative_project_path="${project_path#"${HOME}/"}"
  mounts_ref+=("-v" "${project_path}:/home/devuser/${relative_project_path}:rw")
  ```
- [ ] Add a guard: if `project_path` does not start with `$HOME/`, `die` with a clear error message — devenv requires projects to be under `$HOME`.
- [ ] Introduce a helper function (e.g., `resolve_container_project_path()`) that returns the container-side project path, so it can be reused by `start_container()` and `attach_container()`.

### Task 2: Update `--workdir` in `start_container()` and `attach_container()`

These functions currently hardcode `/workspaces/<project_name>`.

**File:** `bin/devenv`

- [ ] In `start_container()` (~lines 297 and 318), update both `--workdir` flags from `/workspaces/${project_name}` to use the resolved container project path.
- [ ] In `attach_container()` (~line 330), update `--workdir` from `/workspaces/${project_name}` to use the resolved container project path.
- [ ] Pass the container project path through `cmd_start()` to these functions (update function signatures as needed).

### Task 3: Add git config mounts to `build_mounts()`

Mount the host git configuration files into the container as read-only.

**File:** `bin/devenv`

- [ ] Mount `~/.gitconfig` if it exists:
  ```bash
  if [[ -f "${HOME}/.gitconfig" ]]; then
      mounts_ref+=("-v" "${HOME}/.gitconfig:/home/devuser/.gitconfig:ro")
  fi
  ```
- [ ] Auto-discover and mount all `~/.gitconfig-*` files (the include targets):
  ```bash
  local gitconfig_file
  for gitconfig_file in "${HOME}"/.gitconfig-*; do
      if [[ -f "${gitconfig_file}" ]]; then
          local filename="${gitconfig_file##*/}"
          mounts_ref+=("-v" "${gitconfig_file}:/home/devuser/${filename}:ro")
      fi
  done
  ```
- [ ] Also handle `~/.config/git/config` as an alternative global git config location:
  ```bash
  if [[ -f "${HOME}/.config/git/config" ]]; then
      mounts_ref+=("-v" "${HOME}/.config/git/config:/home/devuser/.config/git/config:ro")
  fi
  ```

### Task 4: Update `specs/spec.md`

Update the spec to reflect the new mount strategy and git config support.

**File:** `specs/spec.md`

- [ ] Update the "Configuration Mount Points" table (~line 363) to add git entries:

  | Tool | Host Path | Container Path |
  |------|-----------|----------------|
  | git | `~/.gitconfig` | `/home/devuser/.gitconfig` |
  | git | `~/.gitconfig-*` | `/home/devuser/.gitconfig-*` |
  | git | `~/.config/git/config` | `/home/devuser/.config/git/config` |

- [ ] Update the "Docker Run Command Structure" section (~line 503) to replace:
  ```
  --workdir /workspaces/<project_name>
  -v "<project_path>:/workspaces/<project_name>:rw"
  ```
  with:
  ```
  --workdir /home/devuser/<relative_project_path>
  -v "<project_path>:/home/devuser/<relative_project_path>:rw"
  -v "$HOME/.gitconfig:/home/devuser/.gitconfig:ro"
  -v "$HOME/.gitconfig-*:/home/devuser/.gitconfig-*:ro"
  ```
- [ ] Update the `docker exec` attach command to use the new workdir.
- [ ] Update the flag explanation table to note the project path mirroring strategy.
- [ ] Update the Base Image responsibilities section (~line 115) — remove `/workspaces` references; projects are now mounted at `$HOME`-relative paths.
- [ ] Add a new "Git Configuration" subsection near "Configuration Mount Points" explaining:
  - How `includeIf "gitdir:~/..."` works across host and container
  - Why `$HOME`-relative path mirroring is used
  - That projects must reside under `$HOME`

### Task 5: Update `docker/devenv/Dockerfile.base`

- [ ] Remove the `/workspaces` directory creation and all references to it.
- [ ] Change `WORKDIR` to `/home/devuser`. The `--workdir` flag at runtime will set the actual project path.

### Task 6: Update `docker/devenv/templates/Dockerfile.project` and `Dockerfile.python-uv`

- [ ] In `Dockerfile.project`: replace `WORKDIR /workspaces/project` with `WORKDIR /home/devuser` (runtime `--workdir` overrides).
- [ ] In `Dockerfile.project`: remove `RUN chown -R devuser:devuser /workspaces` — no longer relevant.
- [ ] In `Dockerfile.python-uv`: replace `WORKDIR /workspaces/project` with `WORKDIR /home/devuser`.
- [ ] In `Dockerfile.python-uv`: remove `RUN chown -R devuser:devuser /workspaces`.
- [ ] Remove any other `/workspaces` references in both files.

### Task 7: Validate and test

- [ ] Run `shellcheck bin/devenv` — no errors or warnings.
- [ ] Run `shellcheck bin/build-devenv` — no regressions.
- [ ] Verify the plan covers projects inside `$HOME` (mirrored path).
- [ ] Verify that projects outside `$HOME` are rejected with a clear error.
- [ ] Verify git identity resolves correctly: the `includeIf "gitdir:~/Repos/github.com/jorgengundersen/"` condition must match when working inside the container at `/home/devuser/Repos/github.com/jorgengundersen/<project>`.

---

## Files Modified (Summary)

| File | Change |
|------|--------|
| `bin/devenv` | New helper, updated mounts, workdir, git config mounts |
| `docker/devenv/Dockerfile.base` | Removed `/workspaces`, updated WORKDIR |
| `docker/devenv/templates/Dockerfile.project` | Removed `/workspaces`, updated WORKDIR |
| `docker/devenv/templates/Dockerfile.python-uv` | Removed `/workspaces`, updated WORKDIR |

### Documentation (already updated — verify only)

The following files have already been updated to reflect the new mount strategy and git config support. The implementation agent should verify they are consistent with the code changes but does not need to edit them:

| File | Change |
|------|--------|
| `specs/spec.md` | Updated mount table, docker run structure, new Git Configuration section |
| `specs/persistent-volumes.md` | Updated docker run command |
| `specs/coding-standard.md` | Updated mount example |
| `CONTRIBUTING.md` | Updated template instructions and base image section |
| `docker/devenv/templates/README.md` | Updated template structure description |
| `README.md` | Added git config entries to mount points table |

## Out of Scope

- Changing the container username from `devuser` — kept as-is.
- Mounting `.gitignore_global` or other git-adjacent files — can be added later.
- Credential helpers (`gh auth git-credential`) — already handled via the mounted `~/.config/gh/` directory and SSH agent forwarding.

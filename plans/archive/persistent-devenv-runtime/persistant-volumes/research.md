# Research: Persistent Volumes Gap Analysis

This document analyzes the gap between `specs/persistent-volumes.md` and the current repository state, and maps exactly where code/docs must change.

## Scope and Method

- Source spec: `specs/persistent-volumes.md`
- Current implementation reviewed: `devenv`, `README.md`, `specs/devenv-architecture.md`, `specs/coding-standard.md`, `CONTRIBUTING.md`
- Goal: identify required changes, not implement them in this document.

## Executive Summary

Current runtime behavior does **not** yet implement persistent named Docker volumes for XDG data/cache/state.

Primary gaps:

1. `devenv` lacks volume constants, provisioning, and mount flags for:
   - `devenv-data` -> `/home/devuser/.local/share`
   - `devenv-cache` -> `/home/devuser/.cache`
   - `devenv-state` -> `/home/devuser/.local/state`
2. No `devenv volume` command family exists (`list`, `rm`, `rm --all`, `--force`).
3. Documentation and specs are still centered on config bind mounts; they do not consistently reflect named-volume persistence and lifecycle details.
4. `tvim` config mount is currently `:rw` in code/docs; will change to `:ro` with a named volume overlay on the plugin manager lockfile (`lazy-lock.json`) so lockfile writes persist without granting write access to the full config directory.

## Gap Matrix (Spec vs Current)

| Spec Requirement | Current State | Gap Type | Required Action |
|---|---|---|---|
| Add named volumes for XDG data/cache/state | Not present in `build_mounts()` | NEW | Add 3 volume mounts in `devenv` runtime mount assembly |
| Use fixed volume constants (`devenv-data/cache/state`) | No constants defined | NEW | Add readonly constants near existing constants |
| Volumes labeled `devenv=true` | No volume create/provision path | NEW | Add provisioning primitive using `docker volume create --label devenv=true` |
| Shared across all containers | N/A (no volumes) | NEW | Use fixed global names (not per-project names) |
| Maintain file bind overlay (`opencode/auth.json`) | File bind exists, no parent volume | UPDATE | Ensure volume mount at `.local/share` coexists with existing file bind |
| Optional `devenv volume` subcommand | No subcommand | NEW | Add command dispatch + `list`/`rm` implementation |
| In-use check before rm | No rm feature | NEW | Add running-container mount check before delete |
| Interactive confirm unless `--force` | No rm feature | NEW | Add prompt flow + force bypass |
| tvim config `:ro` + lockfile volume overlay | Currently `:rw` | UPDATE | Mount tvim config `:ro`; add named volume overlay on `lazy-lock.json` for persistent lockfile writes |
| Coding standard security rule for volume naming/labels | Missing | UPDATE | Extend security rules table |

## File and Line Mapping

### 1) Runtime Script (Primary)

#### `devenv`

- **Constants block** around line 7:
  - Current: `readonly IMAGE_PREFIX="devenv"`
  - Add:
    - `readonly VOLUME_DATA="devenv-data"`
    - `readonly VOLUME_CACHE="devenv-cache"`
    - `readonly VOLUME_STATE="devenv-state"`
    - `readonly VOLUME_TVIM_LOCK="devenv-tvim-lock"`

- **Usage text** lines 37-55:
  - Add documented commands:
    - `devenv volume list`
    - `devenv volume rm <name>`
    - `devenv volume rm --all`
    - `devenv volume rm --force <name>`
    - `devenv volume rm --force --all`

- **Mount assembly** in `build_mounts()` (line 156+) and first mount line at 162:
  - Current first mount: project bind mount.
  - Required insertion: named volume mounts for XDG paths.
  - Placement requirement from spec: before existing bind mounts so fine-grained bind overlays still work.

- **tvim mount mode** lines 176-177:
  - Current: `:rw`
  - **Decision:** change to `:ro`. Add a named volume overlay on the lockfile path (`/home/devuser/.config/tvim/lazy-lock.json`) so the plugin manager can persist version pins without requiring write access to the full config directory. `.dockerignore` does not apply to bind mounts, so the overlay approach is the correct Docker-native solution.

- **`opencode/auth.json` bind** lines 191-192:
  - Keep as file bind `:ro`; verify this remains after adding `/home/devuser/.local/share` named volume mount.

- **New primitives/commands (insert near command section)**:
  - Volume existence/provisioning helper
  - Volume list helper (with size)
  - In-use check helper
  - Remove helper(s) with confirm/force flow
  - `cmd_volume()` dispatcher

- **Top-level dispatch** `main()` case at line 429:
  - Add `volume)` branch and subcommand handling.

### 2) User Docs

#### `README.md`

- **devenv command list** lines 134-140:
  - Add `volume` command examples and semantics.

- **Configuration Mount Points** section line 165 onward:
  - Update narrative to distinguish:
    - host config bind mounts (`:ro`)
    - persistent named XDG volumes (`data/cache/state`)

- **tvim statement** line 180:
  - Current text says read-write.
  - Update to `:ro` with named volume overlay for `lazy-lock.json`.

- **Security section** line 208 onward:
  - Add note on named volume labels and prune caveat.

### 3) Authoritative Spec Sync

#### `specs/devenv-architecture.md`

- **Configuration Mount Points section** line 354 onward:
  - Currently states tvim is read-write.
  - Align with persistent-volumes decision.

- **Docker run structure example** line 497 onward:
  - Add 3 named volume mounts.
  - Keep bind mounts and explain overlay behavior.

- **Command structure** line 422 onward:
  - Add `devenv volume ...` command family if this remains part of core interface.

### 4) Coding Rules

#### `specs/coding-standard.md`

- **Security rules table** lines 362-371:
  - Add rule:
    - volumes use `devenv-` prefix and carry `devenv=true` label.

### 5) Contributor Guidance

#### `CONTRIBUTING.md`

- **Mount point guidance** section starts around line 206:
  - Clarify separation:
    - config from host via `:ro` bind mounts
    - runtime state via named volumes under XDG directories
  - Mention new `devenv volume` operational commands for cleanup/inspection.

## Detailed Behavior Gaps for `devenv volume`

Expected behavior from spec and current implementation status:

1. `devenv volume list`
   - **Missing today**.
   - Must list only devenv-managed volumes (label `devenv=true`) and show size.

2. `devenv volume rm <name>`
   - **Missing today**.
   - Must refuse if mounted by running container.
   - Must prompt `[y/N]` unless `--force`.

3. `devenv volume rm --all`
   - **Missing today**.
   - Must resolve devenv-managed volume set and apply same in-use + confirmation rules.

4. `--force`
   - **Missing today**.
   - Must skip prompt but **must not** bypass in-use protection.

## Open Decisions / Validation Required

1. **tvim config mount mode** -- **DECIDED: `:ro` + named volume overlay**
   - Mount `~/.config/tvim` as `:ro` from host.
   - Add a named volume (e.g., `devenv-tvim-lock`) overlaid on `/home/devuser/.config/tvim/lazy-lock.json`.
   - This allows the plugin manager to write lockfile updates that persist across container restarts, without granting write access to the full host config directory.
   - Trade-off accepted: lockfile changes do not automatically flow back to the host dotfiles repo. Manual extraction (`docker cp` or volume inspect) is needed if the user wants to commit updated pins.

2. **Volume provisioning point** -- **DECIDED: Option A: provision during startup**.
   - Option A: provision labeled volumes automatically during `devenv` startup.
   - Option B: provision lazily on first `devenv volume` command.
   - Recommended: Option A for guaranteed labels from first run.

3. **Volume size calculation mechanism for `list`** -- **DECIDED: `docker system df -v` with Go template**

   **Research findings:**

   - `docker volume inspect` does **not** include a size field — it only returns `CreatedAt`, `Driver`, `Labels`, `Mountpoint`, `Name`, `Options`, `Scope`.
   - `docker system df -v` (verbose) is the only Docker-native command that reports per-volume sizes. It exposes `.Name`, `.Size`, `.Labels` (and others) via Go templates.
   - `docker system df` (non-verbose) only reports aggregate volume totals — unusable for per-volume display.
   - Execution time for `docker system df -v` is ~0.8s — acceptable for an interactive CLI command.

   **Evaluated approaches:**

   | Approach | Deps | Pros | Cons |
   |---|---|---|---|
   | `docker system df -v` + Go template name match | Docker only | Zero extra deps; volume names are known constants so `{{if eq .Name "devenv-data"}}` works | Go template `contains` is not available; must enumerate each name or use JSON output |
   | `docker system df -v --format '{{json .Volumes}}'` + `jq` | Docker + jq | Full label filtering (`select(.Labels \| test("devenv=true"))`) | jq may not be on every host; adds a dependency |
   | `docker system df -v --format '{{json .Volumes}}'` + `grep -oP` | Docker + grep -P | No extra deps beyond GNU grep | Fragile JSON parsing; PCRE may not be universal |
   | Helper container `du -sh` per volume | Docker only | Accurate; works on any Docker version | Slow (container spin-up per volume); heavyweight |

   **Decision:** Use `docker volume ls --filter label=devenv=true --format '{{.Name}}'` to get the list of devenv-managed volumes, then a single `docker system df -v` call with Go template to extract sizes by matching each known volume name. This is pure Docker CLI with no external dependencies. Example:

   ```bash
   docker system df -v --format \
     '{{range .Volumes}}{{if eq .Name "devenv-data"}}{{.Name}} {{.Size}}{{end}}{{end}}'
   ```

   Since volume names are fixed constants, each name can be matched with `{{if eq .Name ...}}` — no need for string-contains or jq filtering.

## Suggested Implementation Order

1. Update `devenv` constants, mount construction, and volume provisioning.
2. Add `devenv volume` command family in `devenv`.
3. Apply tvim `:ro` mount + `devenv-tvim-lock` named volume overlay for `lazy-lock.json`.
4. Update `README.md` user-facing command and mount docs.
5. Update `specs/devenv-architecture.md` and `specs/coding-standard.md` for consistency.
6. Update `CONTRIBUTING.md` guidance.

## Risk Notes

- Incorrect mount ordering could hide the `opencode/auth.json` file bind; verify final `docker run` order carefully.
- Volume deletion UX must avoid destructive defaults; confirmation default must remain No.
- If volume labels are not applied consistently, `volume list`/`rm --all` becomes unreliable.

# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

## [1.5.0] - 2026-02-21

### Added
- `repo-base` image with shared foundation for tool layers.
- New opencode helper commands for research, implementation plans, and commits.
- Multi-environment architecture spec, research, and implementation plan docs.

### Changed
- Three-layer build architecture across `repo-base`, `devenv-base`, and `devenv` images.
- Tool images now base on `repo-base` for a consistent foundation.
- `bin/build-devenv` updated for the three-layer build pipeline.
- `README.md` and `CONTRIBUTING.md` updated for the new architecture.
- Updated multi-environment architecture documentation, including generalized references and plan deltas.

## [1.4.0] - 2026-02-19

### Added
- `common-utils` tool Dockerfile (`shared/tools/Dockerfile.common-utils`) with a curated baseline of CLI utilities: `tree`, `less`, `man-db`, `file`, `unzip`, `zip`, `procps`, `lsof`, `iproute2`, `iputils-ping`, `dnsutils`, `netcat-openbsd`.
- `common_utils` intermediate build stage in `docker/devenv/Dockerfile.devenv`; the final `devenv` stage now bases on `common_utils` so all baseline utilities are available at runtime.
- `specs/common-utils.md` specification documenting the stage design, package set, and exclusions.
- Planning docs under `plans/current/common-utils/` (research and implementation plan).

### Changed
- Final stage in `docker/devenv/Dockerfile.devenv` changed from `FROM devenv-base:latest` to `FROM common_utils`.
- `bin/build-devenv` tool list updated to include `common-utils`.
- `README.md` updated to list `common-utils` under Available Tools and reflect the updated build pipeline.
- `specs/devenv-architecture.md` (renamed from `specs/spec.md`) updated to document the new `common_utils` stage in the build pipeline, file tree, and tool table.
- `specs/README.md` updated to reference renamed architecture spec.
- `AGENTS.md` updated with GAP analysis and checkmark usage guidelines.
- `CONTRIBUTING.md` updated to reference `specs/devenv-architecture.md`.

### Removed
- `proposal.md` removed (superseded by spec and planning docs).

## [1.3.0] - 2026-02-18

### Breaking
- `tvim` (NVIM_APPNAME=tvim) wrapper command, config mounts, and lockfile management were removed. Plain `nvim` remains available.
- Project bind mounts now mirror the host `$HOME`-relative path under `/home/devuser/` and projects must live under `$HOME`.

### Added
- Shared Bash logging primitives in `shared/bash/log.sh`.
- Git config mount support for `~/.gitconfig`, `~/.gitconfig-*`, and `~/.config/git/config`.
- Default container resource limits (configurable via `DEVENV_MEMORY`, `DEVENV_MEMORY_SWAP`, `DEVENV_CPUS`).

### Changed
- Restructured the repository to support multiple Docker-based environments sharing a single `shared/tools/` directory.
- Moved CLI entrypoints to `bin/` and installer scripts to `scripts/`.
- Moved devenv Dockerfiles and templates under `docker/devenv/`.
- Scripts now source the shared logging library for consistent output.
- Updated scripts to resolve paths relative to their location for portability.
- Archived completed persistent volume planning docs under `plans/archive/persistent-devenv-runtime/persistant-volumes/`.
- Updated README, contributing docs, and core specs to reflect the new layout and new mount strategy.

### Removed
- `tvim` config mounts and lockfile management.

## [1.2.0] - 2026-02-17

### Added
- Persistent Docker volume support for runtime state with managed volumes: `devenv-data`, `devenv-cache`, `devenv-state`, and `devenv-tvim-lock`.
- New `devenv volume` subcommands for operational volume management: `list`, `rm <name>`, and `rm --all` (with optional `--force`).
- New `specs/persistent-volumes.md` specification documenting design, lifecycle, and operational behavior for persistent volumes.
- New planning docs under `plans/current/` and archived completed persistent runtime plan docs under `plans/archive/persistent-devenv-runtime/`.

### Changed
- `devenv` now provisions and mounts labeled persistent volumes (`devenv=true`) before container startup to retain XDG data/cache/state across sessions.
- `tvim` host config mount is now read-only, with `lazy-lock.json` persisted via a dedicated named volume overlay.
- `install-devenv` now supports `--source`/`-s` for developer-mode symlink installation from an arbitrary script source directory.
- README and core specs were updated to reflect persistent volume behavior, read-only config mount expectations, and new volume management commands.
- `specs/README.md` now references `plans/` as the location for planning and research documents.

## [1.1.1] - 2026-02-16

### Added
- CONTRIBUTING.md guide for adding, modifying, and removing tools and functionality.
- AGENTS.md now references CONTRIBUTING.md in the Read First section.

## [1.1.0] - 2026-02-16

### Added
- `tvim` wrapper command and writable tvim config mount for Neovim app isolation.
- Tree-sitter tool image and CLI integration in the main devenv image.
- Node runtime bundling and system symlinks to make Node available without shell init.
- Runtime build dependencies (`build-essential`, `unzip`) for Neovim plugins and LSP installers.

### Changed
- Neovim runtime discovery now links `/usr/local/share/nvim` to the bundled Neovim runtime.
- build-devenv tool list now includes `tree-sitter`.

## [1.0.0] - 2026-02-16

### Added
- Base and development environment Dockerfiles with multi-stage tool aggregation.
- Tool Dockerfiles for cargo, copilot-cli, fnm, fzf, gh, go, jq, node, nvim, opencode, ripgrep, starship, uv, and yq.
- build-devenv, devenv, and install-devenv scripts for build, runtime, and installation workflows.
- Project Dockerfile templates and documentation/specification guides.

# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

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

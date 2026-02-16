# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog and this project follows Semantic Versioning.

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

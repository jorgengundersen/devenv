# Agent Guidelines

## Read First

- [specs/README.md](specs/README.md) - specification index
- [specs/coding-standard.md](specs/coding-standard.md) - mandatory coding rules
- [CONTRIBUTING.md](CONTRIBUTING.md) - how to add, modify, or remove tools and functionality

## Working Agreements

- Specs describe intent; verify current behavior in the codebase before changing anything.
- Follow the Bash script structure and logging rules exactly as defined in the coding standard.
- Keep edits minimal and intentional; no placeholder or TODO content.
- Use ASCII unless a file already contains non-ASCII characters.

## Repo Layout

- specs/ - authoritative specifications
- plans/ - planning, research, and summary documents
- devenv, build-devenv, install-devenv - executable scripts
- Dockerfile.* and tools/ - build images (do not modify unless explicitly required)

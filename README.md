# Containerized Development Environment

A containerized development environment designed for terminal-based agentic workflows.

## Quick Start

### 1. Make Scripts Executable

Run the following command to make all scripts executable:

```bash
chmod +x ~/.config/devenv/build-devenv ~/.config/devenv/devenv ~/.config/devenv/install-devenv
```

### 2. Install Commands

Run the install script to create symlinks in `~/.local/bin/`:

```bash
~/.config/devenv/install-devenv
```

Or manually create symlinks:

```bash
mkdir -p ~/.local/bin
ln -s ~/.config/devenv/build-devenv ~/.local/bin/build-devenv
ln -s ~/.config/devenv/devenv ~/.local/bin/devenv
```

Ensure `~/.local/bin` is in your PATH:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```

Add this to your `~/.bashrc` or `~/.zshrc` to make it permanent.

### Developer Mode (Live Repo Symlinks)

If you develop devenv from a git repository, point command symlinks to that repo so edits are picked up immediately.

```bash
# From the devenv repository root
./install-devenv --source "$PWD"
```

Verify where commands resolve:

```bash
readlink -f ~/.local/bin/devenv
readlink -f ~/.local/bin/build-devenv
```

Switch back to the default location:

```bash
~/.config/devenv/install-devenv --source ~/.config/devenv
```

### 3. Build Base Image

```bash
build-devenv --stage base
```

### 4. Build Development Environment

```bash
build-devenv --stage devenv
```

### 5. Start Development Environment

```bash
# In current directory
devenv .

# In specific directory
devenv ~/projects/my-project

# List running containers
devenv list

# Stop a container
devenv stop .
```

## Architecture

```
~/.config/devenv/
├── Dockerfile.base              # Base operating system image
├── Dockerfile.devenv            # Complete development environment
├── build-devenv                 # Build management script
├── devenv                       # Runtime environment launcher
├── install-devenv               # Installation script
├── README.md                    # This file
├── tools/                       # Tool-specific Dockerfiles
│   ├── Dockerfile.cargo
│   ├── Dockerfile.copilot-cli
│   ├── Dockerfile.fnm
│   ├── Dockerfile.gh
│   ├── Dockerfile.go
│   ├── Dockerfile.jq
│   ├── Dockerfile.node
│   ├── Dockerfile.nvim
│   ├── Dockerfile.opencode
│   ├── Dockerfile.ripgrep
│   ├── Dockerfile.starship
│   ├── Dockerfile.tree-sitter
│   ├── Dockerfile.uv
│   └── Dockerfile.yq
└── templates/                   # Project templates
    ├── Dockerfile.project
    ├── Dockerfile.python-uv
    └── README.md
```

## Available Tools

- **cargo** - Rust toolchain and package manager
- **copilot-cli** - GitHub Copilot CLI
- **fnm** - Fast Node Manager
- **gh** - GitHub CLI
- **go** - Go programming language
- **jq** - JSON processor
- **node** - Node.js (via fnm)
- **nvim** - Neovim editor
- **tvim** - Neovim wrapper (NVIM_APPNAME=tvim)
- **opencode** - AI coding assistant
- **ripgrep** - Fast file searcher
- **starship** - Shell prompt
- **tree-sitter** - Tree-sitter CLI
- **uv** - Python package manager
- **yq** - YAML processor

## Commands

### build-devenv

Build Docker images for the development environment.

```bash
build-devenv --stage base      # Build base image
build-devenv --stage devenv    # Build complete environment
build-devenv --tool nvim       # Build specific tool
build-devenv --project ./my-project  # Build project-specific image
```

### devenv

Launch persistent containerized development environments.

```bash
devenv help                    # Display help
devenv .                       # Start in current directory
devenv <path>                  # Start in specified directory
devenv --port 3333 <path>      # Bind SSH to localhost:3333
devenv list                    # List running containers
devenv stop <path|name>        # Stop a container
devenv stop --all              # Stop all devenv containers
devenv volume list             # List devenv volumes with size
devenv volume rm <name>        # Remove a specific volume
devenv volume rm --all         # Remove all devenv volumes
```

Persistent containers run in the background and you attach with `docker exec` on subsequent `devenv` calls.

## Project-Specific Configuration

Create a `.devenv/Dockerfile` in your project root to customize the environment:

```dockerfile
FROM devenv:latest

USER root

# Install project-specific dependencies
RUN apt-get update && apt-get install -y \
    postgresql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

USER devuser
```

See the `templates/` directory for examples.

## Configuration Mount Points

The following host configurations are mounted into containers:

| Tool | Host Path | Container Path |
|------|-----------|----------------|
| bash | `~/.bashrc` | `/home/devuser/.bashrc` |
| bash | `~/.inputrc` | `/home/devuser/.inputrc` |
| bash | `~/.config/bash/` | `/home/devuser/.config/bash/` |
| neovim | `~/.config/nvim/` | `/home/devuser/.config/nvim/` |
| tvim | `~/.config/tvim/` | `/home/devuser/.config/tvim/` |
| starship | `~/.config/starship/` | `/home/devuser/.config/starship/` |
| gh | `~/.config/gh/` | `/home/devuser/.config/gh/` |
| opencode | `~/.config/opencode/` | `/home/devuser/.config/opencode/` |

## Persistent Volumes

Runtime state is stored in named Docker volumes that persist across container restarts:

| Volume | Container Mount Point | Purpose |
|--------|----------------------|---------|
| `devenv-data` | `/home/devuser/.local/share` | Installed plugins, tree-sitter parsers, tool databases |
| `devenv-cache` | `/home/devuser/.cache` | Download caches (uv, cargo, npm) |
| `devenv-state` | `/home/devuser/.local/state` | Log files, command history, session state |
| `devenv-tvim-lock` | `/home/devuser/.config/tvim/lazy-lock.json` | Plugin manager lockfile |

Volumes are shared across all devenv containers and labeled `devenv=true` for management.

`tvim` is mounted read-only. Plugin data (installed plugins, tree-sitter parsers) persists in the `devenv-data` volume at `~/.local/share/tvim`. The `lazy-lock.json` lockfile is overlaid with a named volume (`devenv-tvim-lock`) so updates persist without granting write access to the host config directory.

## tvim

If you keep your Neovim config in `~/.config/tvim`, you can launch it in the container with:

```bash
tvim
```

This sets `NVIM_APPNAME=tvim` and keeps state under `/home/devuser/.local/share/tvim`.

## Build Arguments

All Dockerfiles support these build arguments:

| Argument | Default | Description |
|----------|---------|-------------|
| USERNAME | devuser | Non-privileged user name |
| USER_UID | 1000 | User ID (should match host UID) |
| USER_GID | 1000 | Group ID (should match host GID) |

Example with custom UID/GID:

```bash
docker build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) -f Dockerfile.base -t devenv-base .
```

## Security

- All tools are installed as root during build, then ownership is changed to `devuser`
- Containers run as `devuser` (non-privileged user)
- SSH agent is forwarded for secure key access
- SSH `authorized_keys` is bind-mounted at runtime for inbound SSH access (sshd starts only when present)
- SSH binds to `127.0.0.1` only; port priority is `--port`, then `DEVENV_SSH_PORT`, then an allocated port
- Tool configurations are mounted read-only from host
- Persistent volumes use the `devenv-` prefix and carry the `devenv=true` label for discovery and safe cleanup

## Future Improvements

- Add a first-class `devenv exec` command to run a command inside a running container

## Uninstallation

To remove devenv:

```bash
~/.config/devenv/install-devenv --uninstall
```

Or manually:

```bash
rm ~/.local/bin/build-devenv
rm ~/.local/bin/devenv
```

Remove Docker images:

```bash
docker rmi devenv:latest
docker rmi devenv-base:latest
```

## License

GNU General Public License v3.0

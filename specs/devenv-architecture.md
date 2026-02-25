# Containerized Development Environment Specification

A containerized development environment designed for terminal-based agentic workflows. It provides an alternative to Microsoft Dev Containers by eliminating the `devcontainer.json` abstraction layer, using pure Docker-based configuration to deliver an IDE-agnostic, terminal-centric development platform that supports concurrent multi-project workflows with persistent containers.

## Motivation

This project provides an alternative to Microsoft Dev Containers by eliminating the `devcontainer.json` abstraction layer. The specification focuses on pure Docker-based configuration, making it IDE-agnostic and suitable for terminal-centric development workflows.

The persistent container model enables concurrent multi-project workflows: each project runs in its own long-lived container, and developers attach multiple interactive sessions via `docker exec`. This eliminates container startup latency on subsequent connections and supports parallel work across projects.

## Architecture

### File Tree

```
devenv/
├── bin/
│   ├── build-devenv             # Build management script
│   └── devenv                   # Runtime environment launcher
├── scripts/
│   └── install-devenv           # Installation script (creates symlinks)
├── docker/
│   └── devenv/
│       ├── Dockerfile.base      # Base operating system image
│       ├── Dockerfile.devenv    # Complete development environment (base + tools)
│       └── templates/           # Project-specific Dockerfile templates
│           ├── Dockerfile.project       # Generic project template
│           ├── Dockerfile.python-uv     # Python + uv template
│           └── README.md                # Template usage guide
├── shared/
│   └── tools/                   # Tool-specific Dockerfiles
│       ├── Dockerfile.cargo
│       ├── Dockerfile.common-utils
│       ├── Dockerfile.copilot-cli
│       ├── Dockerfile.fnm
│       ├── Dockerfile.fzf
│       ├── Dockerfile.gh
│       ├── Dockerfile.go
│       ├── Dockerfile.hadolint
│       ├── Dockerfile.jq
│       ├── Dockerfile.make
│       ├── Dockerfile.mdformat
│       ├── Dockerfile.node
│       ├── Dockerfile.nvim
│       ├── Dockerfile.opencode
│       ├── Dockerfile.ripgrep
│       ├── Dockerfile.shellcheck
│       ├── Dockerfile.starship
│       ├── Dockerfile.tree-sitter
│       ├── Dockerfile.uv
│       └── Dockerfile.yq
├── plans/                       # Planning and research documents
│   ├── plan.md
│   ├── research.md
│   └── summary.md
└── specs/                       # Specification documents
    ├── README.md                # Spec index
    ├── coding-standard.md       # Authoritative coding standard
    └── devenv-architecture.md    # This file
```

### Build Pipeline

The build pipeline follows a layered architecture:

```
docker/base/Dockerfile.base (Ubuntu + devuser + core utilities)
    ↓
docker/devenv/Dockerfile.base (SSH layer on repo-base)
    ↓
docker/devenv/Dockerfile.devenv (common_utils stage, FROM devenv-base)
    ↓
shared/tools/Dockerfile.* (one tool per Dockerfile, built independently)
    ↓
docker/devenv/Dockerfile.devenv (devenv stage, FROM common_utils, aggregates tools via multi-stage COPY)
    ↓
<project>/.devenv/Dockerfile (extends devenv with project deps)
```

1. **Repo Base Image** — Foundation OS with user setup and core utilities.
2. **Devenv Base Image** — Adds SSH client/server and runtime SSH directories.
3. **Common Utils Stage** — `docker/devenv/Dockerfile.devenv (common_utils stage)` installs a baseline of small CLI utilities on top of the base image.
4. **Tool Images** — Each tool is built independently from the repo base image using multi-stage syntax.
5. **Development Environment** — `docker/devenv/Dockerfile.devenv` final stage composes all tool artifacts into a single image via `COPY --from` instructions, starting from `common_utils`.
6. **Project Extensions** — Project-specific Dockerfiles extend `devenv:latest` with additional dependencies.

## Design Principles

### Configuration via Build Arguments

All Dockerfiles use build arguments for configurable values rather than hardcoded constants. Each Dockerfile provides sensible defaults while allowing value injection at build time.

### Persistent Container Model

Each project runs in its own long-lived background container. The container lifecycle follows the **Background + Exec** model:

- `devenv .` starts a background container (if none exists), then attaches via `docker exec -it`.
- If a container already exists for the project, `devenv .` attaches another session via `docker exec -it`.
- The container runs `sleep infinity` as its main process, with `sshd` started alongside it.
- Containers persist until explicitly stopped via `devenv stop .` or `devenv stop --all`.
- The `--rm` flag on `docker run` ensures automatic cleanup after `docker stop`.

This model eliminates container startup latency on subsequent connections and supports multiple concurrent terminal sessions within the same project environment.

### Localhost-Only SSH by Default

SSH is exposed only on `127.0.0.1` (localhost), preventing remote access unless explicitly configured otherwise. The SSH port is pre-allocated before container start and communicated to the user.

### Named Containers with Labels

Every container is assigned a deterministic name derived from the project path, enabling `docker exec` by name. Labels provide machine-readable metadata for listing and filtering devenv containers:

- `devenv=true` — identifies all devenv-managed containers.
- `devenv.project=<parent>/<basename>` — identifies the specific project.

## Image Specifications

### Repo Base Image

**Path:** `docker/base/Dockerfile.base`

**Responsibilities:**
- Configure the base operating system (Ubuntu)
- Create `devuser` (non-privileged user with matching host UID and GID)
- Install core utilities required by tool installers

**Build Arguments:**

| Argument | Default Value | Description |
|----------|--------------|-------------|
| `USERNAME` | `devuser` | Non-privileged user name |
| `USER_UID` | `1000` | User ID (should match host UID) |
| `USER_GID` | `1000` | Group ID (should match host GID) |

**OS:** Ubuntu (latest LTS)

### Devenv Base Image

**Path:** `docker/devenv/Dockerfile.base`

**Responsibilities:**
- Install SSH client and server (`openssh-client`, `openssh-server`)
- Prepare SSH directory structure (`/home/devuser/.ssh`) for runtime `authorized_keys` mounting

### Tool Images

**Path:** `shared/tools/`

Each tool Dockerfile handles installation of a single tool and its configuration. Tool Dockerfiles use multi-stage syntax:

```dockerfile
FROM repo-base:latest AS tool_<name>
```

Stage naming convention: `tool_<name>` (e.g., `tool_nvim`, `tool_cargo`)

**Build Order:**

Tools must be built in dependency order:

1. **Stage 1 (Base):** `base` — Foundation image with OS and user setup
2. **Stage 2 (Runtimes & Build Tools):** `cargo`, `go`, `fnm`, `uv`, `jq` — Language runtimes and essential build tools (can be parallel)
3. **Stage 3 (Dependent tools):** `node` (depends on `fnm`), `tree-sitter` (depends on `node`), `ripgrep` (depends on `cargo`, `jq`)
4. **Stage 4 (Standalone):** `common-utils`, `gh`, `nvim`, `opencode`, `copilot-cli`, `starship`, `yq`, `fzf`, `make`, `shellcheck`, `hadolint`, `mdformat` — Independent tools (can be parallel)

Note: `common-utils` is also built as part of `docker/devenv/Dockerfile.devenv` as the `common_utils` intermediate stage. The `--tool common-utils` build target produces a standalone tool image for isolated testing.

**Installation Dependencies:**

Tools requiring build dependencies must copy artifacts from prerequisite stages:

```dockerfile
COPY --from=tool_<dependency> <source> <destination>
```

Required runtime dependencies:

| Tool | Dependencies | Artifacts to Copy |
|------|--------------|-------------------|
| `node` | `fnm` | `/usr/local/bin/fnm` binary |
| `tree-sitter` | `node` | `/opt/node` runtime |
| `ripgrep` | `jq` | `/usr/local/bin/jq` |

**Example:** `ripgrep` uses `jq` to fetch the latest version from GitHub API:

```dockerfile
COPY --from=tools-jq:latest /usr/local/bin/jq /usr/local/bin/jq
```

### Version Policy

All tools install their latest stable version. If the Ubuntu package repository does not provide the latest version, alternative installation methods (direct download, build from source, official installers) are used.

### Main Development Environment

**Path:** `docker/devenv/Dockerfile.devenv`

Composes all tool images using multi-stage builds. Each tool is a separate build stage, and the final stage aggregates artifacts using `COPY --from=tool_<name>` instructions.

### Project-Specific Extensions

Projects requiring additional dependencies extend the base development environment.

**Structure:**

```
<project_root>/.devenv/Dockerfile
```

Project Dockerfiles use `devenv:latest` as their base image:

```dockerfile
FROM devenv:latest
```

**Templates:** Project templates are located in `docker/devenv/templates/`:

- `Dockerfile.project` — Generic project template
- `Dockerfile.python-uv` — Python project using uv as package manager

**Template Structure:**
```
docker/devenv/templates/
├── Dockerfile.project      # Base project template
├── Dockerfile.python-uv    # Python + uv template
└── README.md               # Template usage guide
```

**Python/uv Template Example:**
```dockerfile
FROM devenv:latest

# Set working directory (runtime --workdir overrides this)
WORKDIR /home/devuser

# Python best practices
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Install project with dev dependencies (editable mode)
RUN uv pip install -e ".[dev]"
```

## Installation Methods

**Installation Approach:** All tools should be installed as `root` during the Docker build process. File ownership changes should be minimized to the final stage only to avoid slow recursive `chown` operations:

```dockerfile
# In intermediate tool stages - install only
FROM repo-base:latest AS tool_<name>
USER root
RUN apt-get install -y <package>

# In final devenv stage - ownership changes
RUN chown -R devuser:devuser /usr/local/bin
```

### cargo

Install rustup with cargo to system location:

```bash
CARGO_HOME=/usr/local/cargo \
RUSTUP_HOME=/usr/local/rustup \
curl https://sh.rustup.rs -sSf | sh -s -- -y --no-modify-path --default-toolchain stable
```

**Environment:**
- Add `/usr/local/cargo/bin` to `$PATH`
- Set `RUSTUP_HOME=/usr/local/rustup`
- Set `CARGO_HOME=/usr/local/cargo`

### go

```bash
GO_RUNTIME_VERSION=$(curl -s https://go.dev/VERSION?m=text | head -n 1)
curl -LO "https://go.dev/dl/${GO_RUNTIME_VERSION}.linux-amd64.tar.gz"
rm -rf /usr/local/go
tar -C /usr/local -xzf "${GO_RUNTIME_VERSION}.linux-amd64.tar.gz"
```

**Environment:**
- Add `/usr/local/go/bin` to `$PATH`
- Example: `ENV PATH="/usr/local/go/bin:/usr/local/cargo/bin:/usr/local/bin:${PATH}"`

### fnm

```bash
curl -fsSL https://fnm.vercel.app/install | bash
```

### node

Installs latest stable Node.js version via fnm:

```bash
fnm install --lts
fnm use lts-latest
```

### uv

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

### jq

Extract from official Docker image via multi-stage build:

```dockerfile
FROM ghcr.io/jqlang/jq:1.7.1 AS jq_source
FROM repo-base:latest AS tool_jq
COPY --from=jq_source /jq /usr/local/bin/jq
RUN chmod +x /usr/local/bin/jq
```

### ripgrep

**Dynamic Version Fetch:**

```bash
# Fetch latest release tag from GitHub API
LATEST_TAG=$(curl -s https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name')
# Download and install latest release
curl -LO "https://github.com/BurntSushi/ripgrep/releases/download/${LATEST_TAG}/ripgrep_${LATEST_TAG}-1_amd64.deb"
dpkg -i "ripgrep_${LATEST_TAG}-1_amd64.deb"
```

### gh

```bash
(type -p wget >/dev/null || (apt update && apt install -y --no-install-recommends wget)) \
    && mkdir -p -m 755 /etc/apt/keyrings \
    && out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    && cat $out | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && mkdir -p -m 755 /etc/apt/sources.list.d \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt update \
    && apt install -y --no-install-recommends gh
```

### nvim

```bash
curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz
rm -rf /opt/nvim-linux-x86_64
tar -C /opt -xzf nvim-linux-x86_64.tar.gz
```

**Environment:** Add `/opt/nvim-linux-x86_64/bin` to `$PATH`

### opencode

```bash
curl -fsSL https://opencode.ai/install | bash
```

### copilot-cli

```bash
curl -fsSL https://gh.io/copilot-install | bash
```

### starship

```bash
curl -sS https://starship.rs/install.sh | sh
```

### yq

```bash
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq
```

### shellcheck

```bash
SHELLCHECK_URL=$(curl -fsSL https://api.github.com/repos/koalaman/shellcheck/releases/latest | \
    sed -n 's/.*"browser_download_url": "\(https:[^"]*linux.x86_64.tar.xz\)".*/\1/p' | head -n 1)
SHELLCHECK_ARCHIVE="${SHELLCHECK_URL##*/}"
SHELLCHECK_DIR="${SHELLCHECK_ARCHIVE%.linux.x86_64.tar.xz}"
curl -fsSLO "${SHELLCHECK_URL}"
tar -xJf "${SHELLCHECK_ARCHIVE}"
mv "${SHELLCHECK_DIR}/shellcheck" /usr/local/bin/shellcheck
```

### hadolint

```bash
HADOLINT_VERSION=$(curl -fsSL https://api.github.com/repos/hadolint/hadolint/releases/latest | \
    sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p')
curl -fsSLO "https://github.com/hadolint/hadolint/releases/download/${HADOLINT_VERSION}/hadolint-Linux-x86_64"
mv hadolint-Linux-x86_64 /usr/local/bin/hadolint
```

### mdformat

```bash
apt-get update && apt-get install -y --no-install-recommends pipx
pipx install mdformat
mv /root/.local/bin/mdformat /usr/local/bin/mdformat
```

### make

```bash
apt-get update && apt-get install -y --no-install-recommends make
```

## Configuration Mount Points

Tool configurations are mounted at container runtime (from host dotfiles and repo-managed files). Mount points use equivalent paths in the container. All config mounts are read-only:

| Tool | Host Path | Container Path |
|------|-----------|----------------|
| bash | `~/.bashrc` | `/home/devuser/.bashrc` |
| bash | `~/.inputrc` | `/home/devuser/.inputrc` |
| bash | `~/.config/bash/` | `/home/devuser/.config/bash/` |
| neovim | `~/.config/nvim/` | `/home/devuser/.config/nvim/` |
| starship | `~/.config/starship/` | `/home/devuser/.config/starship/` |
| gh | `~/.config/gh/` | `/home/devuser/.config/gh/` |
| gh-copilot | `~/.config/gh-copilot/` | `/home/devuser/.config/gh-copilot/` |
| opencode | `shared/config/opencode/opencode.devenv.jsonc` | `/home/devuser/.config/opencode/opencode.jsonc` |
| git | `~/.gitconfig` | `/home/devuser/.gitconfig` |
| git | `~/.gitconfig-*` | `/home/devuser/.gitconfig-*` |
| git | `~/.config/git/config` | `/home/devuser/.config/git/config` |

`OPENCODE_CONFIG` defaults to `/home/devuser/.config/opencode/opencode.jsonc` in the runtime environment only when `OPENCODE_CONFIG` is not already set.

`~/.config/opencode/` from the host is not mounted; opencode config is provided from `shared/config/opencode/opencode.devenv.jsonc`.

### Git Configuration

Git configuration files from the host are mounted read-only into the container. This includes the main `~/.gitconfig` and any included files matching `~/.gitconfig-*` (auto-discovered at runtime), as well as the XDG-style `~/.config/git/config` if present.

To support git's `includeIf "gitdir:~/..."` conditional includes, the project is mounted at the same `$HOME`-relative path inside the container as it has on the host. Since git resolves `~` to the current user's `$HOME` at runtime, the same `includeIf` directives work in both environments:

- **Host:** `~/Repos/github.com/user/project` → `/home/<host_user>/Repos/github.com/user/project`
- **Container:** `~/Repos/github.com/user/project` → `/home/devuser/Repos/github.com/user/project`

This allows per-directory git identities (name, email, signing key) to work automatically inside containers without any path rewriting.

**Requirement:** Projects must reside under the host user's `$HOME` directory.

## Build System

### Build Script Interface

A `build-devenv` script coordinates image construction:

**Location:** `bin/build-devenv` (or anywhere on your PATH)

**Usage:**
```bash
build-devenv --stage <stage>   # Build base, devenv-base, or devenv stage
build-devenv --tool <tool>     # Build specific tool Dockerfile
build-devenv --project <path>  # Build project-specific image
```

**Examples:**

```bash
build-devenv --stage base # Build docker/base/Dockerfile.base
build-devenv --stage devenv-base # Build docker/devenv/Dockerfile.base
build-devenv --stage devenv # Build docker/devenv/Dockerfile.devenv
build-devenv --tool common-utils # Build shared/tools/Dockerfile.common-utils
build-devenv --tool nvim # Build shared/tools/Dockerfile.nvim
build-devenv --project ./my-project # Build project/.devenv/Dockerfile
```

**Build Context:** The build context defaults to the repository root.
You can override it by setting `DEVENV_HOME=/path/to/repo`.

**Tool Image Tags:** When building individual tools, tag as `tools-<name>:latest` (e.g., `tools-nvim:latest`).

**Tool Isolation Strategy:**

The `--tool` flag builds standalone tool images for isolated debugging without affecting the main development environment:

```bash
# Build and test a single tool in isolation
build-devenv --tool cargo
docker run --rm -it tools-cargo:latest /bin/bash
```

These tool images:
- Contain only the base image + single tool
- Are **not** integrated into `docker/devenv/Dockerfile.devenv`
- Enable isolated debugging of build issues
- Allow quick iteration on tool configurations

## Runtime Interface

The `devenv` script is the primary runtime interface for managing development environment containers.

**Location:** `bin/devenv` (or anywhere on your PATH)

### Command Structure

```
devenv .                      # start/attach to env for current directory
devenv <path>                 # start/attach to env for given path
devenv --port <number> .      # start with explicit SSH port
devenv list                   # list running environments
devenv stop .                 # stop env for current directory
devenv stop <path>            # stop env for given path
devenv stop <name>            # stop env by container name
devenv stop --all             # stop all devenv containers
devenv help                   # show help
devenv volume list            # list devenv volumes with size
devenv volume rm <name>       # remove a specific volume
devenv volume rm --all        # remove all devenv volumes
devenv volume rm --force ...  # skip confirmation prompt
```

### Container Lifecycle

**When `devenv .` is invoked and NO container exists for the project:**

1. Pre-allocate a free port:
   ```bash
   python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'
   ```
2. Start container in background:
   ```bash
   docker run -d --rm --name <container_name> ... <image_name> bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
   ```
3. Log SSH port to user.
4. Attach interactive session:
   ```bash
   docker exec -it <container_name> bash --login
   ```

**When `devenv .` is invoked and a container IS already running:**

1. Log that attaching to existing container.
2. Attach interactive session:
   ```bash
   docker exec -it <container_name> bash --login
   ```

### Container Naming

**Format:** `devenv-<parent_basename>-<project_basename>`

- `parent_basename` = basename of the parent directory of the project path
- `project_basename` = basename of the project path

**Example:** `/home/user/Repos/local/api` → `devenv-local-api`

This deterministic naming enables `docker exec` by name without needing to look up container IDs.

### Container Labels

All devenv containers are labeled for discoverability and management:

| Label | Value | Purpose |
|-------|-------|---------|
| `devenv` | `true` | Identifies all devenv-managed containers |
| `devenv.project` | `<parent_basename>/<project_basename>` | Identifies the specific project |

### SSH Port Binding

SSH is pre-allocated and bound to localhost only:

| Priority | Source | Binding |
|----------|--------|---------|
| 1 (highest) | `--port <number>` CLI flag | `127.0.0.1:<number>:22` |
| 2 | `DEVENV_SSH_PORT` env var | `127.0.0.1:<value>:22` |
| 3 (default) | Pre-allocated free port | `127.0.0.1:<auto>:22` |

SSH is only enabled when `~/.ssh/authorized_keys` exists on the host.

If SSH is enabled, the selected port is validated and must be an integer in the range `1-65535`; otherwise `devenv` exits with an error.

If Docker rejects localhost publishing with `/forwards/expose returned unexpected status: 500`, `devenv` retries `docker run` with `<port>:22`.

### Docker Run Command Structure

The full `docker run` command issued by `devenv` when starting a new container:

```bash
docker run -d --rm \
  --name devenv-<parent>-<project> \
  --user devuser:devuser \
  --workdir /home/devuser/<relative_project_path> \
  --label devenv=true \
  --label devenv.project=<parent>/<project> \
  -v "devenv-data:/home/devuser/.local/share" \
  -v "devenv-cache:/home/devuser/.cache" \
  -v "devenv-state:/home/devuser/.local/state" \
  -v "<project_path>:/home/devuser/<relative_project_path>:rw" \
  -v "$HOME/.bashrc:/home/devuser/.bashrc:ro" \
  -v "$HOME/.inputrc:/home/devuser/.inputrc:ro" \
  -v "$HOME/.config/bash/:/home/devuser/.config/bash/:ro" \
  -v "$HOME/.config/nvim/:/home/devuser/.config/nvim/:ro" \
  -v "$HOME/.config/starship/:/home/devuser/.config/starship/:ro" \
  -v "$HOME/.config/gh/:/home/devuser/.config/gh/:ro" \
    -v "$DEVENV_HOME/shared/config/opencode/opencode.devenv.jsonc:/home/devuser/.config/opencode/opencode.jsonc:ro" \
    -v "$HOME/.local/share/opencode/auth.json:/home/devuser/.local/share/opencode/auth.json:ro" \
  -v "$HOME/.gitconfig:/home/devuser/.gitconfig:ro" \
  -v "$HOME/.gitconfig-*:/home/devuser/.gitconfig-*:ro" \
  -v "$HOME/.config/git/config:/home/devuser/.config/git/config:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent:ro" \
  -v "$HOME/.ssh/authorized_keys:/home/devuser/.ssh/authorized_keys:ro" \
  -e SSH_AUTH_SOCK=/ssh-agent \
    -e OPENCODE_CONFIG=/home/devuser/.config/opencode/opencode.jsonc \
  -e TERM \
  -p "127.0.0.1:<port>:22" \
  --network bridge \
  <image_name> \
  bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
```

`-e OPENCODE_CONFIG=/home/devuser/.config/opencode/opencode.jsonc` is included only when `OPENCODE_CONFIG` is not already set in the caller environment.

If the localhost publish fails with `/forwards/expose returned unexpected status: 500`, the run is retried with `-p "<port>:22"`.

Then attach:

```bash
docker exec -it --workdir /home/devuser/<relative_project_path> devenv-<parent>-<project> bash --login
```

**Docker Run Flags:**

| Flag | Purpose |
|------|---------|
| `-d` | Run container in background (detached) |
| `--rm` | Remove container on stop (stateless) |
| `--name` | Deterministic container name for exec |
| `--user` | Run as devuser (non-privileged) |
| `--workdir` | Start in the project directory (mirrors host `$HOME`-relative path) |
| `--label` | Metadata for listing and filtering |
| `-v` (project) | Bind mount project code at `$HOME`-relative path (read-write) |
| `-v` (configs) | Mount tool configs read-only (host dotfiles and repo-managed opencode config file) |
| `-v` (git) | Mount git config files from host (read-only) |
| `-v` (volumes) | Persistent named volumes for XDG data, cache, and state |
| `-v` (opencode auth) | Mount host opencode auth file (read-only) |
| `-v` (ssh-agent) | Forward host SSH agent for key access |
| `-v` (authorized_keys) | Mount SSH authorized keys for sshd |
| `-e SSH_AUTH_SOCK` | Point container to forwarded SSH agent |
| `-e OPENCODE_CONFIG` | Point opencode to `/home/devuser/.config/opencode/opencode.jsonc` when not already set |
| `-e TERM` | Preserve terminal capabilities |
| `-p` | Bind SSH port to localhost first; retry with `<port>:22` on the known Docker forwarder `500` case |
| `--network bridge` | Standard Docker bridge networking |

### `devenv list` Output

```
NAME                    SSH                     STATUS    STARTED
devenv-local-api        127.0.0.1:54321         running   2h ago
devenv-repos-frontend   127.0.0.1:54987         running   15m ago
```

### `devenv stop` Behavior

- `devenv stop .` / `devenv stop <path>` — Resolves path to container name using the naming convention, then runs `docker stop <container_name>`.
- `devenv stop <name>` — Stops a container by name directly via `docker stop <name>`.
- `devenv stop --all` — Stops all containers with label `devenv=true`:
  ```bash
  docker stop $(docker ps -q --filter label=devenv=true)
  ```

## Image Management

### Tagging Strategy

Use explicit version tags rather than `latest` for traceability:

```bash
docker build -t repo-base:v1.0.0 .
docker tag repo-base:v1.0.0 repo-base:latest
```

**Project image tag format:** `devenv-project-<parent>-<basename>:latest`

Example: A project at `/home/user/Repos/local/api` produces the image `devenv-project-local-api:latest`.

### Cleanup Practices

**Remove dangling images** (untagged build artifacts):

```bash
docker image prune
```

**Remove unused images** (not referenced by containers):

```bash
docker image prune -a
```

**Safe automated cleanup** (preserves volumes):

```bash
# Clean only dangling images and build cache (safest)
0 2 * * 0 docker image prune -f && docker builder prune -f

# To also remove unused images (not running containers)
0 3 * * 0 docker image prune -a -f
```

**Note:** Project-specific images (built via `build-devenv --project`) are tagged and will not be removed by automated cleanup. Manual cleanup is required when projects are no longer needed.

**Volume management best practices:**

- **Never use `--volumes` flag** in automated cleanup unless you're certain no important data exists
- **Label important volumes** for protection
- **Selective volume cleanup** (only removes unlabeled volumes)
- **Manual volume cleanup** when needed

### Registry Considerations

- Implement retention policies to manage storage costs
- Use semantic versioning for release tags
- Tag images with Git commit SHA for traceability
- Consider multi-stage builds to minimize final image size

## Environment Variables

**PATH Configuration:** All PATH modifications (for tools like `go`, `nvim`, `cargo`, etc.) are handled via the mounted `~/.bashrc` configuration file, not in Dockerfiles. This ensures PATH is consistent across container restarts and allows host-controlled customization.

**Other Environment Variables:** Persistent environment variables should also be defined in the mounted `~/.bashrc` configuration file.

## Installation Scripts

**Executable Scripts:** Two executable scripts provide the main interface:

- **`devenv/build-devenv`** — Build management
- **`devenv/devenv`** — Runtime environment launcher

**Installation:** The `install-devenv` script creates symlinks in `~/.local/bin/`:

```bash
# install-devenv creates these symlinks:
ln -s /path/to/devenv/build-devenv ~/.local/bin/build-devenv
ln -s /path/to/devenv/devenv ~/.local/bin/devenv
```

Scripts do not use `.sh` extension.

## Error Handling

All scripts must implement comprehensive error handling:

- `set -euo pipefail` at the top of every script
- Explicit validation of inputs and preconditions
- Logging of actions and errors
- `main()` function structure for clean entry point

## Security

- **SSH binds to `127.0.0.1` by default** — localhost only, preventing remote access unless explicitly configured
- **No Docker socket mounting** — containers cannot control the Docker daemon
- **Containers run as `devuser`** — non-privileged user, never root
- **Read-only config mounts** — tool configurations mounted with `:ro` flag
- **`authorized_keys` enables SSH access** — SSH is only functional when `~/.ssh/authorized_keys` exists on the host and is mounted into the container

## Target Audience

This specification is designed for:

- Individual developers preferring terminal-based workflows
- AI agents requiring reproducible, containerized environments
- Users seeking an alternative to IDE-specific containerization solutions

---

**Note:** This specification prioritizes flexibility and terminal-centric workflows over IDE integration. All configuration is expressed through standard Docker constructs (Dockerfiles, build arguments, environment variables).

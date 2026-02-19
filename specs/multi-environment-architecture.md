# Multi-Environment Architecture Specification

This repository began as a single containerized development environment (devenv).
This specification defines the architecture for supporting multiple environment
types — starting with devenv and adding a Ralph environment for autonomous AI
agent loops — while sharing a common foundation.

## Motivation

The devenv environment is optimized for interactive, terminal-based development:
SSH server, shell prompt, editor, fuzzy finder, and similar interactive tools. A
growing need exists for a second environment type: a headless container that runs
AI coding agents in autonomous loops (the Ralph Wiggum technique). These two
environments share a common Ubuntu base and overlapping tool sets, but differ in
purpose, user experience, and tool selection.

Without a shared foundation, each environment would duplicate base image logic
(Ubuntu setup, user creation, core packages), diverge over time, and increase
maintenance burden. A layered architecture with a shared repo-wide base image
solves this.

### Ralph Wiggum Loop

The Ralph Wiggum technique (coined by Geoffrey Huntley) is an orchestration
pattern for autonomous AI coding agents. In its simplest form:

```bash
while :; do cat PROMPT.md | agent ; done
```

An infinite loop repeatedly feeds a prompt to an AI coding agent. Progress
persists in files and git history, not in the LLM context window. When context
fills up, the agent terminates, the loop restarts with a fresh context, and the
agent resumes from the state on disk. The spec and implementation plan serve as
the source of truth, not the conversation history.

A Ralph environment needs: an agent CLI (e.g., claude-code, opencode), git, and
a working directory. It does not need SSH, interactive shell customization,
editor, or prompt theming.

## Architecture

### Image Hierarchy

```
ubuntu:24.04
  └─ repo-base
       ├─ devenv-base
       │    └─ devenv
       │         └─ devenv-project-*
       │
       └─ ralph-base
            └─ ralph
                 └─ ralph-project-*
```

Three layers, two branches:

1. **repo-base** — shared foundation for all environments.
2. **Environment base** — environment-specific OS-level setup (devenv-base,
   ralph-base).
3. **Environment image** — complete environment with tools aggregated via
   multi-stage builds (devenv, ralph).
4. **Project extensions** — project-specific layers on top of any environment.

### Why Not a Separate Tools Base Image

The tools in `shared/tools/` are built as isolated multi-stage steps. Each tool
needs a minimal Ubuntu image with `curl`, `git`, and `ca-certificates` to
install onto — which is exactly what `repo-base` provides. A separate
`tools-base` image would add an unnecessary layer between `repo-base` and the
tool stages without providing additional value. `repo-base` serves as the tools
base.

## Directory Structure

```
docker/
  base/
    Dockerfile.base              # repo-base: shared foundation
  devenv/
    Dockerfile.base              # devenv-base: interactive environment base
    Dockerfile.devenv            # devenv: complete dev environment
    templates/
      Dockerfile.project         # Generic project extension
      Dockerfile.python-uv       # Python project extension
      README.md
  ralph/
    Dockerfile.base              # ralph-base: headless agent base
    Dockerfile.ralph             # ralph: complete agent environment
    templates/
      Dockerfile.project         # Generic Ralph project extension
      README.md
shared/
  bash/
    log.sh                       # Shared logging library
  tools/
    Dockerfile.*                 # Tool Dockerfiles (FROM repo-base:latest)
specs/
  ...
plans/
  ...
bin/
  build-devenv                   # Build management (extended for multi-env)
  devenv                         # Runtime launcher (devenv)
  ralph                          # Runtime launcher (ralph) [future]
scripts/
  install-devenv                 # Installation script (extended for multi-env)
```

## Image Specifications

### Repo Base Image

**Path:** `docker/base/Dockerfile.base`

**Image name:** `repo-base:latest`

**Responsibilities:**

- Configure the base operating system (Ubuntu 24.04 LTS)
- Install core packages required by all environments and tool builds
- Create a non-privileged user with matching host UID/GID
- Set up sudo access

**What it does NOT do:**

- Install SSH server (environment-specific)
- Configure shell prompt or interactive tools
- Install any development tools
- Set up XDG volume mount points (environment-specific)

**Build Arguments:**

| Argument   | Default    | Description                          |
|------------|------------|--------------------------------------|
| `USERNAME` | `devuser`  | Non-privileged user name             |
| `USER_UID` | `1000`     | User ID (should match host UID)      |
| `USER_GID` | `1000`     | Group ID (should match host GID)     |

**Core Packages:**

- `ca-certificates`
- `curl`
- `git`
- `sudo`
- `wget`

These are the minimal set required by nearly all tool installers and both
environment types.

**Notable exclusion:** `openssh-client` and `openssh-server` are not installed
here. SSH is an interactive devenv concern. The ralph environment does not need
an SSH server. Environments that need SSH install it in their own base image.

### Devenv Base Image

**Path:** `docker/devenv/Dockerfile.base`

**Image name:** `devenv-base:latest`

**FROM:** `repo-base:latest`

**Responsibilities (additive to repo-base):**

- Install SSH client and server (`openssh-client`, `openssh-server`)
- Configure SSH server (`ssh-keygen -A`, `/run/sshd`)
- Prepare SSH directory structure (`/home/<username>/.ssh`)

This image is equivalent to the current `devenv-base:latest` but built on top of
`repo-base` instead of directly on `ubuntu:24.04`.

### Devenv Image

**Path:** `docker/devenv/Dockerfile.devenv`

**Image name:** `devenv:latest`

**FROM:** `devenv-base:latest` (for build stages), `common_utils` (for final
stage)

No changes to the existing multi-stage structure. The `common_utils` stage and
all `tool_*` stages continue to use `devenv-base:latest` as their build base.
The final `devenv` stage composes tool artifacts via `COPY --from=tool_*`.

### Ralph Base Image

**Path:** `docker/ralph/Dockerfile.base`

**Image name:** `ralph-base:latest`

**FROM:** `repo-base:latest`

**Responsibilities (additive to repo-base):**

- Headless-specific configuration (no SSH server, no interactive shell setup)
- Ensure git is configured for non-interactive use
- Pre-create working directory structure

**What ralph-base does NOT include:**

- SSH server or client
- Shell prompt (starship)
- Editor (nvim)
- Fuzzy finder (fzf)

**Build Arguments:** Same as repo-base (`USERNAME`, `USER_UID`, `USER_GID`),
passed through.

### Ralph Image

**Path:** `docker/ralph/Dockerfile.ralph`

**Image name:** `ralph:latest`

**FROM:** `ralph-base:latest` (for build stages and final stage)

**Structure:** Multi-stage build following the same pattern as
`Dockerfile.devenv`. Build stages install tools independently, final stage
aggregates via `COPY --from=tool_*`.

**Tool set (minimal for agent loops):**

| Tool      | Purpose                                     |
|-----------|---------------------------------------------|
| `git`     | Already in repo-base                        |
| `jq`      | JSON processing for API responses           |
| `yq`      | YAML processing for config files            |
| `gh`      | GitHub CLI for PR/issue workflows           |
| `opencode`| AI coding agent                             |
| `ripgrep` | Code search (used by agents)                |
| `uv`      | Python package manager (if needed by agent) |
| `node`    | Runtime for agent tooling                   |
| `fnm`     | Node version management                     |

Tools explicitly excluded from ralph:

| Tool          | Reason                       |
|---------------|------------------------------|
| `nvim`        | Interactive editor           |
| `fzf`         | Interactive fuzzy finder     |
| `starship`    | Interactive shell prompt     |
| `copilot-cli` | Interactive assistant        |
| `common-utils`| Interactive CLI conveniences |

The ralph tool set is deliberately minimal. Additional tools can be added to
ralph-project extensions as needed.

### Project Extensions

Both environments support project-specific extensions:

**Devenv projects:** `<project>/.devenv/Dockerfile` extends `devenv:latest`
(unchanged from current behavior).

**Ralph projects:** `<project>/.ralph/Dockerfile` extends `ralph:latest`.

## Shared Tools

### Migration: shared/tools/ FROM Image

All tool Dockerfiles in `shared/tools/` currently use:

```dockerfile
FROM devenv-base:latest AS tool_<name>
```

This changes to:

```dockerfile
FROM repo-base:latest AS tool_<name>
```

This decouples tool builds from any specific environment. Both `Dockerfile.devenv`
and `Dockerfile.ralph` can reference the same tool stages.

**Exception:** Tools that depend on other tools (e.g., `ripgrep` depends on
`jq`, `tree-sitter` depends on `node`) continue to use `COPY --from=` for
inter-stage dependencies. These references are unaffected by the base image
change.

### Tool Stages in Environment Dockerfiles

The inline tool stages in `Dockerfile.devenv` also change their FROM to
reference `repo-base:latest` instead of `devenv-base:latest`:

```dockerfile
# Before
FROM devenv-base:latest AS tool_cargo

# After
FROM repo-base:latest AS tool_cargo
```

`Dockerfile.ralph` follows the same pattern, defining only the tool stages it
needs.

## Build Pipeline

### Full Build Graph

```
docker/base/Dockerfile.base (Ubuntu + user + core packages)
    ↓
repo-base:latest
    ├── docker/devenv/Dockerfile.base (+ SSH)
    │       ↓
    │   devenv-base:latest
    │       ↓
    │   docker/devenv/Dockerfile.devenv (common_utils + tools)
    │       ↓
    │   devenv:latest
    │       ↓
    │   <project>/.devenv/Dockerfile
    │       ↓
    │   devenv-project-*:latest
    │
    ├── docker/ralph/Dockerfile.base (headless config)
    │       ↓
    │   ralph-base:latest
    │       ↓
    │   docker/ralph/Dockerfile.ralph (agent tools)
    │       ↓
    │   ralph:latest
    │       ↓
    │   <project>/.ralph/Dockerfile
    │       ↓
    │   ralph-project-*:latest
    │
    └── shared/tools/Dockerfile.* (FROM repo-base, standalone testing)
            ↓
        devenv-tool-*:latest (unchanged tag convention)
```

### Auto-Dependency Resolution

The build script resolves dependencies automatically:

| Build Target             | Auto-builds if missing           |
|--------------------------|----------------------------------|
| `--stage devenv-base`    | `repo-base`                      |
| `--stage devenv`         | `repo-base`, `devenv-base`       |
| `--stage ralph-base`     | `repo-base`                      |
| `--stage ralph`          | `repo-base`, `ralph-base`        |
| `--tool <name>`          | `repo-base`                      |
| `--project <path>`       | full chain for detected env type |

### Image Tagging

| Image            | Tag Format                          | Example                  |
|------------------|-------------------------------------|--------------------------|
| Repo base        | `repo-base:<timestamp>`, `repo-base:latest` | `repo-base:20260219.143022` |
| Devenv base      | `devenv-base:<timestamp>`, `devenv-base:latest` | `devenv-base:20260219.143025` |
| Devenv           | `devenv:<timestamp>`, `devenv:latest` | `devenv:20260219.143100` |
| Ralph base       | `ralph-base:<timestamp>`, `ralph-base:latest` | `ralph-base:20260219.143022` |
| Ralph            | `ralph:<timestamp>`, `ralph:latest` | `ralph:20260219.143050` |
| Tool (standalone)| `devenv-tool-<name>:latest`         | `devenv-tool-cargo:latest` |
| Devenv project   | `devenv-project-<parent>-<name>:latest` | `devenv-project-local-api:latest` |
| Ralph project    | `ralph-project-<parent>-<name>:latest` | `ralph-project-local-api:latest` |

## Build Script Changes

### Extended CLI

```
build-devenv --stage <stage>       # base, devenv-base, devenv, ralph-base, ralph
build-devenv --tool <tool>         # Unchanged
build-devenv --project <path>      # Auto-detects .devenv/ or .ralph/
```

The `--stage` argument expands to include:

| Stage          | Dockerfile                       | Image              |
|----------------|----------------------------------|--------------------|
| `base`         | `docker/base/Dockerfile.base`    | `repo-base:latest` |
| `devenv-base`  | `docker/devenv/Dockerfile.base`  | `devenv-base:latest` |
| `devenv`       | `docker/devenv/Dockerfile.devenv`| `devenv:latest`    |
| `ralph-base`   | `docker/ralph/Dockerfile.base`   | `ralph-base:latest` |
| `ralph`        | `docker/ralph/Dockerfile.ralph`  | `ralph:latest`     |

### Project Detection

`--project <path>` inspects the project directory for:

1. `<path>/.devenv/Dockerfile` — builds as devenv project (FROM `devenv:latest`)
2. `<path>/.ralph/Dockerfile` — builds as ralph project (FROM `ralph:latest`)

If both exist, the build script requires explicit disambiguation (error with
guidance).

## Runtime Interface

### Devenv Runtime

The existing `bin/devenv` script is unchanged. It manages interactive
development containers with SSH, volumes, and config mounts.

### Ralph Runtime

A new `bin/ralph` script manages headless agent containers. Its interface mirrors
`bin/devenv` but is adapted for non-interactive use:

```
ralph <path>                      # Start ralph container for project
ralph list                        # List running ralph containers
ralph stop <path>                 # Stop ralph container
ralph stop --all                  # Stop all ralph containers
ralph logs <path>                 # View agent output logs
```

Key differences from devenv:

| Concern              | devenv                          | ralph                           |
|----------------------|---------------------------------|---------------------------------|
| Container start      | `sleep infinity` + `sshd`       | Agent loop command              |
| User interaction     | `docker exec -it` (interactive) | `docker logs` (observe)         |
| SSH                  | Yes, localhost-bound             | No                              |
| Config mounts        | Shell, editor, prompt configs   | Git config, agent config only   |
| Volumes              | `devenv-data/cache/state`       | `ralph-data/cache/state`        |
| Container naming     | `devenv-<parent>-<name>`        | `ralph-<parent>-<name>`         |
| Container labels     | `devenv=true`                   | `ralph=true`                    |

### Ralph Container Lifecycle

Ralph containers are not persistent in the same way as devenv containers. A
ralph container runs the agent loop as its main process. When the loop completes
(or is stopped), the container exits and is removed (`--rm`).

```bash
docker run -d --rm \
  --name ralph-<parent>-<project> \
  --user devuser:devuser \
  --workdir /home/devuser/<relative_project_path> \
  --label ralph=true \
  --label ralph.project=<parent>/<project> \
  -v "ralph-data:/home/devuser/.local/share" \
  -v "ralph-cache:/home/devuser/.cache" \
  -v "ralph-state:/home/devuser/.local/state" \
  -v "<project_path>:/home/devuser/<relative_project_path>:rw" \
  -v "$HOME/.gitconfig:/home/devuser/.gitconfig:ro" \
  -v "$HOME/.gitconfig-*:/home/devuser/.gitconfig-*:ro" \
  -v "$HOME/.config/git/config:/home/devuser/.config/git/config:ro" \
  -v "$HOME/.config/opencode/:/home/devuser/.config/opencode/:ro" \
  -v "$SSH_AUTH_SOCK:/ssh-agent:ro" \
  -e SSH_AUTH_SOCK=/ssh-agent \
  -e TERM \
  --network bridge \
  ralph:latest \
  bash -lc "while :; do cat PROMPT.md | opencode ; done"
```

The agent command and prompt file are configurable per project (defined in the
project's `.ralph/` directory).

## Persistent Volumes

Ralph uses its own set of named volumes, separate from devenv:

| Volume Name    | Container Mount Point          | Purpose                        |
|----------------|--------------------------------|--------------------------------|
| `ralph-data`   | `/home/devuser/.local/share`   | Agent state, session data      |
| `ralph-cache`  | `/home/devuser/.cache`         | Package caches                 |
| `ralph-state`  | `/home/devuser/.local/state`   | Logs, history                  |

Separate volumes prevent agent loops from polluting devenv state and vice versa.
The volume naming and labeling conventions mirror devenv (`ralph-` prefix,
`ralph=true` label).

## Non-Goals

- Changing the devenv runtime behavior or interface.
- Sharing Docker volumes between devenv and ralph environments.
- Supporting more than two environment types in this iteration (the architecture
  accommodates future environments, but only devenv and ralph are specified).
- Implementing a full Ralph orchestration framework. This spec covers the
  container infrastructure; the agent loop configuration is project-specific.
- Renaming the repository. The repo name `devenv` predates multi-env support.
  The `docker/base/` directory and `repo-base` image name establish the shared
  foundation without requiring a repo rename.

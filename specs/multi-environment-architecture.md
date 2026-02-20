# Multi-Environment Architecture Specification

This repository began as a single containerized development environment (devenv).
This specification defines the architecture for supporting multiple environment
types while sharing a common foundation. The first environment is devenv; the
architecture is designed so that additional environments can be added without
duplicating base image logic.

## Motivation

The devenv environment is optimized for interactive, terminal-based development:
SSH server, shell prompt, editor, fuzzy finder, and similar interactive tools. A
growing need exists for specialized environments that serve different purposes —
for example, a headless container that runs AI coding agents in autonomous loops,
or a CI-focused environment with a minimal tool set.

These environments share a common Ubuntu base and overlapping tool sets, but
differ in purpose, user experience, and tool selection. Without a shared
foundation, each environment would duplicate base image logic (Ubuntu setup, user
creation, core packages), diverge over time, and increase maintenance burden. A
layered architecture with a shared repo-wide base image solves this.

### Example: Headless Agent Loops

One motivating use case is the "Ralph Wiggum technique" (coined by Geoffrey
Huntley) — an orchestration pattern for autonomous AI coding agents. In its
simplest form:

```bash
while :; do cat PROMPT.md | agent ; done
```

An infinite loop repeatedly feeds a prompt to an AI coding agent. Progress
persists in files and git history, not in the LLM context window. When context
fills up, the agent terminates, the loop restarts with a fresh context, and the
agent resumes from the state on disk.

An environment for this use case needs: an agent CLI (e.g., claude-code,
opencode), git, and a working directory. It does not need SSH, interactive shell
customization, editor, or prompt theming. This illustrates why a single
monolithic environment is insufficient — different use cases require different
tool selections built on the same foundation.

## Architecture

### Image Hierarchy

```
ubuntu:24.04
  └─ repo-base
       └─ <env>-base
            └─ <env>
                 └─ <env>-project-*
```

The current environment following this pattern:

```
ubuntu:24.04
  └─ repo-base
       └─ devenv-base
            └─ devenv
                 └─ devenv-project-*
```

Future environments add sibling branches from `repo-base`:

```
ubuntu:24.04
  └─ repo-base
       ├─ devenv-base
       │    └─ devenv
       │         └─ devenv-project-*
       │
       └─ <env>-base
            └─ <env>
                 └─ <env>-project-*
```

Three core layers per environment:

1. **repo-base** — shared foundation for all environments.
2. **Environment base** (`<env>-base`) — environment-specific OS-level setup.
3. **Environment image** (`<env>`) — complete environment with tools aggregated
   via multi-stage builds.

Project extensions are optional per-project layers on top of any environment
image. They are not part of the core architecture but allow projects to add
dependencies specific to their needs.

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
  build-devenv                   # Build management
  devenv                         # Runtime launcher (devenv)
scripts/
  install-devenv                 # Installation script
```

Future environments add a `docker/<env>/` directory following the same layout as
`docker/devenv/` (a `Dockerfile.base`, a `Dockerfile.<env>`, and optionally a
`templates/` directory). They may also add a `bin/<env>` runtime launcher and
a corresponding entry in `scripts/install-devenv`.

## Image Specifications

### Repo Base Image

**Path:** `docker/base/Dockerfile.base`

**Image name:** `repo-base:latest`

**Label:** `repo-base=true`

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

These are the minimal set required by nearly all tool installers and all
environment types.

**Notable exclusion:** `openssh-client` and `openssh-server` are not installed
here. SSH is an interactive devenv concern. Environments that need SSH install
it in their own base image.

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

**FROM:** `repo-base:latest` (for `tool_*` build stages), `devenv-base:latest`
(for `common_utils`), `common_utils` (for final stage)

The `tool_*` build stages change their FROM from `devenv-base:latest` to
`repo-base:latest` (see [Shared Tools](#shared-tools)). The `common_utils` stage
remains `FROM devenv-base:latest` because it installs interactive CLI utilities
that belong to the devenv environment. The final `devenv` stage composes tool
artifacts via `COPY --from=tool_*`.

### Project Extensions

Environment images support project-specific extensions:

**Devenv projects:** `<project>/.devenv/Dockerfile` extends `devenv:latest`
(unchanged from current behavior).

Future environments follow the same pattern: `<project>/.<env>/Dockerfile`
extends `<env>:latest`.

## Shared Tools

### Migration: shared/tools/ FROM Image

All tool Dockerfiles in `shared/tools/` use:

```dockerfile
FROM repo-base:latest AS tool_<name>
```

This decouples tool builds from any specific environment. Any environment
Dockerfile can reference the same tool stages.

**Exception — inter-tool dependencies:** Two tools have a second `FROM`
statement that pulls in a pre-built standalone tool image (not a build stage
within the same Dockerfile). These inter-tool `FROM` references are distinct
from the base image `FROM` and follow a different migration path:

- **Base image FROM** is `repo-base:latest` (same as all other tool Dockerfiles).
- **Inter-tool FROM** uses `tools-<name>:latest` to match the standalone tag
  convention (see [Image Tagging](#image-tagging)).

The two affected tools:

| Tool | Depends on | Inter-tool FROM |
|------|-----------|-----------------|
| `ripgrep` | `jq` | `FROM tools-jq:latest AS jq_source` |
| `tree-sitter` | `node` | `FROM tools-node:latest AS tool_node` |

In both cases, the standalone tool image is referenced via a `FROM` statement
(creating a named stage), and the binary or directory is then copied into the
final stage with `COPY --from=<stage_name>`. For example, `Dockerfile.ripgrep`
uses `FROM tools-jq:latest AS jq_source` followed by
`COPY --from=jq_source /usr/local/bin/jq /usr/local/bin/jq`.

**Build script impact:** The `build_tool()` function in `bin/build-devenv`
resolves inter-tool dependencies at build time — it checks whether
`tools-node:latest` exists before building `tree-sitter` and builds the `node`
tool first if missing. Tool images are tagged as `tools-<name>:latest`.

### Tool Stages in Environment Dockerfiles

The inline tool stages in `Dockerfile.devenv` use `repo-base:latest`:

```dockerfile
FROM repo-base:latest AS tool_cargo
```

Future environment Dockerfiles follow the same pattern, defining only the tool
stages they need.

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
    └── shared/tools/Dockerfile.* (FROM repo-base, standalone testing)
            ↓
        tools-*:latest
```

Future environments extend the graph with sibling branches from `repo-base`.

### Auto-Dependency Resolution

The build script resolves dependencies automatically:

| Build Target             | Auto-builds if missing           |
|--------------------------|----------------------------------|
| `--stage devenv-base`    | `repo-base`                      |
| `--stage devenv`         | `repo-base`, `devenv-base`       |
| `--tool <name>`          | `repo-base`                      |
| `--project <path>`       | full chain for detected env type |

### Image Tagging

| Image            | Tag Format                          | Example                  |
|------------------|-------------------------------------|--------------------------|
| Repo base        | `repo-base:<timestamp>`, `repo-base:latest` | `repo-base:20260219.143022` |
| Devenv base      | `devenv-base:<timestamp>`, `devenv-base:latest` | `devenv-base:20260219.143025` |
| Devenv           | `devenv:<timestamp>`, `devenv:latest` | `devenv:20260219.143100` |
| Tool (standalone)| `tools-<name>:latest`               | `tools-cargo:latest`     |
| Devenv project   | `devenv-project-<parent>-<name>:latest` | `devenv-project-local-api:latest` |

Standalone tool images carry `LABEL tools=true` for filtering and discovery.
This distinguishes them from environment images (`devenv=true`) and the shared
foundation (`repo-base=true`).

Future environments follow the same tagging convention: `<env>-base:<timestamp>`,
`<env>:<timestamp>`, and `<env>-project-<parent>-<name>:latest`.

## Build Script Changes

### Extended CLI

```
build-devenv --stage <stage>       # base, devenv-base, devenv
build-devenv --tool <tool>         # Unchanged
build-devenv --project <path>      # Detects .devenv/ in project
```

The `--stage` argument expands to include `base` for the repo-base image:

| Stage          | Dockerfile                       | Image              |
|----------------|----------------------------------|--------------------|
| `base`         | `docker/base/Dockerfile.base`    | `repo-base:latest` |
| `devenv-base`  | `docker/devenv/Dockerfile.base`  | `devenv-base:latest` |
| `devenv`       | `docker/devenv/Dockerfile.devenv`| `devenv:latest`    |

## Runtime Interface

### Devenv Runtime

The existing `bin/devenv` script is unchanged. It manages interactive
development containers with SSH, volumes, and config mounts.

Future environments will have their own runtime launchers (`bin/<env>`) tailored
to their specific use cases, following patterns appropriate for their purpose
(e.g., interactive attachment, log observation, headless execution).

## Persistent Volumes

Each environment maintains its own set of named volumes, separate from other
environments. The devenv volumes are defined in the
[persistent volumes spec](persistent-volumes.md).

Future environments follow the same XDG-based naming convention with their own
prefix (e.g., `<env>-data`, `<env>-cache`, `<env>-state`). Separate volumes
prevent environments from polluting each other's state.

## Extending the Architecture

To add a new environment:

1. Create `docker/<env>/Dockerfile.base` — `FROM repo-base:latest`, add
   environment-specific OS-level configuration.
2. Create `docker/<env>/Dockerfile.<env>` — multi-stage build composing tool
   stages (`FROM repo-base:latest`) and the environment base, following the same
   pattern as `Dockerfile.devenv`.
3. Optionally create `docker/<env>/templates/` with project extension templates.
4. Create `bin/<env>` — runtime launcher for the environment.
5. Add `--stage <env>-base` and `--stage <env>` to `build-devenv` (or create a
   dedicated build script if warranted).
6. Define the environment's persistent volume set.
7. Write a specification for the environment.

Each environment owns its specification, tool selection, runtime behavior, and
volume layout. The shared architecture provides the foundation: `repo-base`,
shared tool Dockerfiles, and the layered image pattern.

## Non-Goals

- Changing the devenv runtime behavior or interface.
- Sharing Docker volumes between environments.
- Implementing future environment specifications in this iteration. This spec
  covers the shared architecture and the structural changes needed to support
  multiple environments. Individual environment specs are separate documents.
- Renaming the repository. The repo name `devenv` predates multi-env support.
  The `docker/base/` directory and `repo-base` image name establish the shared
  foundation without requiring a repo rename.

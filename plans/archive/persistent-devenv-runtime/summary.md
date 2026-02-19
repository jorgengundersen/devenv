# Conversation Summary: devenv Multi-Project Enhancement

## Context

The `devenv` project is a containerized development environment for terminal-based agentic workflows. It uses pure Docker (no `devcontainer.json`) and is IDE-agnostic. The user wants to enhance it to support concurrent multi-project usage with proper container lifecycle management.

## Key Findings

### 1. Port Discovery Research

Three approaches were evaluated for discovering SSH ports when using auto-assigned ports (`-p 0:22`):

**Pre-allocate port (chosen):** Grab a free port before `docker run`, bind to it explicitly. Tiny TOCTOU race (port freed then re-bound) but negligible in practice. This is the pattern VS Code Dev Containers and similar tools use.

```bash
SSH_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
docker run -it --rm -p "127.0.0.1:${SSH_PORT}:22" ...
```

**Background + exec + trap:** Start container detached, query port via `docker port`, then `docker exec -it`. Eliminates the race but changes the execution model (entrypoint doesn't run, signals differ). This approach was ultimately chosen for a different reason — it enables the persistent container model.

**In-container discovery:** Not possible. The container's network namespace cannot see host-side NAT mappings. Mounting Docker socket grants root-equivalent host access — rejected for security.

### 2. WezTerm Mux Server Research

Investigated running `wezterm-mux-server` inside containers as an alternative to SSH:

- Technically possible — headless binary (~30-70MB), supports TLS and SSH-tunneled connections
- Nesting works: host mux + container mux coexist as separate "domains" without prefix conflicts
- **Rejected for now:** Adds significant image bloat, version coupling between host and container, mux protocol is "still a young feature" per official docs, and it doesn't eliminate port discovery — just shifts it

**Decision:** Defer WezTerm mux to future enhancement. SSH is simpler, stable, and already works.

### 3. Container Lifecycle Model

The original model (`docker run -it --rm`) creates a new container per invocation and destroys it on exit. This is problematic for multi-session workflows (e.g., multiple opencode instances on the same project).

Two models were evaluated:

**Model A — SSH for additional sessions:** First tab runs `devenv .` (creates container), subsequent tabs SSH in. Problem: Tab 1 is the "anchor" — closing it kills all sessions.

**Model B — Background container + exec (chosen):** Container runs in background (`docker run -d --rm`). Every `devenv .` invocation either starts a new container or attaches to the existing one via `docker exec -it`. All sessions are equal — no anchor tab. Container persists until explicit `devenv stop`.

## Decisions Made

### Container Lifecycle: Background + Exec (Model B)

- `devenv .` starts a background container if none exists for the project, then `docker exec -it` into it
- If container already exists, `docker exec -it` to attach another session
- Container runs `sleep infinity` as main process with sshd started
- User explicitly stops via `devenv stop .` or `devenv stop --all`
- `--rm` on the background container ensures cleanup after `docker stop`

### SSH Port: Pre-allocate with Localhost Binding

- Default: `127.0.0.1:0:22` (localhost-only, auto-assign port)
- Pre-allocate port before container start, print it to user
- `DEVENV_SSH_PORT` env var overrides port (specific port number)
- `--port <number>` CLI flag overrides both (port number only, not bind spec)

### Container Naming: Named per Project

- Format: `devenv-<parent>-<basename>` (e.g., `devenv-local-api`)
- Enables `docker exec` by name, `devenv stop .` by name
- Name collision = project already running → attach instead of fail

### Image Tagging: Parent-Basename

- Format: `devenv-project-<parent>-<basename>:latest` (e.g., `devenv-project-local-api:latest`)
- Avoids collision between projects with same basename under different parent dirs
- Uses parent directory basename + project basename

### Labels

- `devenv=true` on all devenv containers
- `devenv.project=<parent>/<basename>` for project identification
- No full-path labels (too noisy)

### Command Interface

```
devenv .                  # start/attach to env for current directory
devenv <path>             # start/attach to env for given path
devenv --port <number> .  # start with specific SSH port
devenv list               # list running environments (name, SSH port, status, started)
devenv stop .             # stop env for current directory
devenv stop <path>        # stop env for given path
devenv stop <name>        # stop env by container name
devenv stop --all         # stop all devenv containers
devenv help               # show help
```

### Security

- SSH binds to `127.0.0.1` by default (localhost only, not all interfaces)
- No Docker socket mounting into containers
- Containers run as `devuser` (non-privileged)
- Tool configs mounted read-only

### Backward Compatibility

- Not a concern — the project is still a prototype
- No deprecation notices needed

## Tradeoffs Accepted

| Decision | Tradeoff | Rationale |
|----------|----------|-----------|
| Pre-allocate port | Tiny TOCTOU race | Negligible in practice; keeps code simple |
| Background + exec | Requires explicit `devenv stop` | Equal sessions outweighs cleanup friction |
| Parent-basename naming | Extremely unlikely collision if same parent+basename | Good enough; full-path hashing is overkill |
| No WezTerm mux | Lose native terminal integration | SSH is proven; mux is immature |
| Localhost-only SSH | Can't SSH from remote machines by default | Secure default; overridable via env var |

## Current Implementation State

### Files

| File | Purpose | Lines |
|------|---------|-------|
| `devenv` | Runtime launcher | 228 lines |
| `build-devenv` | Build management | 219 lines |
| `install-devenv` | Installation script | 144 lines |
| `devenv-architecture.md` | Specification | 588 lines |
| `README.md` | User documentation | 213 lines |
| `Dockerfile.base` | Base OS image | exists |
| `Dockerfile.devenv` | Complete environment | exists |
| `tools/Dockerfile.*` | Per-tool Dockerfiles | 14 files |
| `templates/` | Project templates | 3 files |

### Current `devenv` Behavior (what changes)

- Uses `docker run -it --rm` (ephemeral, one session per invocation)
- SSH port defaults to `2222`, binds to `0.0.0.0` (all interfaces)
- No container naming
- No labels
- No `list` or `stop` commands
- No `--port` flag

### What Stays the Same

- Build system (`build-devenv`) — no changes needed
- Installation (`install-devenv`) — no changes needed
- Dockerfile architecture — no changes needed
- Volume mount strategy — no changes needed
- Image selection logic — minor change to naming scheme

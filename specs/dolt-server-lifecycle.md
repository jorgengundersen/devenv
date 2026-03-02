# Dolt Server Lifecycle Management

A shared Dolt SQL server managed as a container-level service, enabling concurrent multi-agent access to the beads issue tracker without database lock contention.

## Motivation

Devenv containers support multiple concurrent shell sessions via `docker exec`. Each session may run AI agents or developer workflows that interact with beads (`bd`). Beads uses Dolt as its storage backend in server mode (`dolt sql-server`), which is the correct architecture for multi-writer access.

The problem: `bd` auto-starts a `dolt sql-server` process on first use. When a second shell session runs `bd`, it attempts to start another server on the same data directory. Dolt holds an exclusive write lock on the database directory, so the second attempt fails:

```
database "dolt" is locked by another dolt process
```

This makes multi-agent workflows impossible. Only one shell session can use beads at a time.

The root cause is that the Dolt server lifecycle is tied to individual `bd` invocations rather than to the container itself. The server should start once and be shared by all sessions.

### Additional Issues

- **Zombie processes:** `bd`-managed Dolt servers produce orphaned child processes that are never reaped, because the container's PID 1 (`sleep infinity` via `bash -lc`) does not reap adopted children.
- **Fragile lifecycle:** The `bd` auto-start logic uses PID files and lock files for coordination, but these are insufficient when multiple shells race to start/connect.

## Design

### Container Startup Sequence

The container's main process starts `dolt sql-server` before accepting shell sessions. The startup sequence becomes:

```
Container Start
    │
    ├─ 1. Start init process (tini) as PID 1
    │
    ├─ 2. Start sshd
    │
    ├─ 3. Start dolt sql-server (background, supervised)
    │     ├─ Bind: 127.0.0.1:<port>
    │     ├─ Data dir: .beads/dolt/
    │     └─ Write PID to .beads/dolt-server.pid
    │
    ├─ 4. Wait for server ready (health check)
    │
    └─ 5. exec sleep infinity (keep container alive)
```

All `bd` commands from all shell sessions connect to this single server instance via MySQL protocol. No auto-start attempts occur.

### Init Process (Zombie Reaping)

The container must use a proper init process as PID 1 to reap orphaned child processes. `tini` is the standard solution for Docker containers:

```
PID 1: tini
  └─ entrypoint.sh
       ├─ sshd (background)
       ├─ dolt sql-server (background)
       └─ sleep infinity (foreground, keeps container alive)
```

`tini` is already available in Ubuntu base images via `docker-init` or can be installed as a package.

### Beads Configuration

Beads must be configured to never auto-start its own Dolt server. This is a per-project setting in `.beads/config.yaml`:

```yaml
dolt:
  auto-start: false
```

With this setting, `bd` assumes the server is already running and connects to it. If the server is down, `bd` returns an error rather than attempting to start one.

### Entrypoint Script

A shell script replaces the inline `bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"` command. The script:

1. Starts `sshd` (existing behavior).
2. Locates the project's `.beads/dolt/` directory and starts `dolt sql-server` if it exists.
3. Waits for the server to accept connections (TCP check on the configured port).
4. Execs into `sleep infinity` to keep the container alive.

The entrypoint script is located at:

```
shared/scripts/entrypoint.sh
```

The entrypoint is invoked via tini in the `docker run` command:

```bash
bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"
```

The script is copied into the image at build time to `/usr/local/share/devenv/entrypoint.sh`, but invoked through `bash -l` so that the login shell profile (PATH, environment variables) is loaded before the entrypoint runs.

### Server Discovery

The entrypoint must discover which project directory contains a `.beads/dolt/` database. Since the container's working directory is set to the project path via `--workdir`, the entrypoint uses `$PWD` to locate the beads directory:

```
$PWD/.beads/dolt/    →  start server for this project
```

If no `.beads/dolt/` exists at container start, the server is not started. This handles fresh projects that haven't run `bd init` yet. When `bd init` is later run, beads' own auto-start will handle the first launch. Subsequent shells will then find the server already running.

### Server Port

The server port is read from `.beads/dolt/config.yaml` if it exists, or defaults to Dolt's standard port. The entrypoint does not hardcode a port number. It reads the port from the existing beads configuration to stay consistent with what `bd` expects.

### Health Check

After starting the server, the entrypoint waits for the server to accept TCP connections before proceeding. This prevents race conditions where a shell attaches before the server is ready:

```bash
# Wait up to 30 seconds for server to accept connections
for i in $(seq 1 30); do
  if dolt sql -q "SELECT 1" --host 127.0.0.1 --port "$port" --user root 2>/dev/null; then
    break
  fi
  sleep 1
done
```

If the server fails to start within the timeout, the entrypoint logs a warning and continues. The container remains functional for non-beads work; `bd` commands will report the server as unavailable.

### Failure Mode

The entrypoint must not prevent the container from starting if the Dolt server fails to launch. The server is a best-effort service. Failure scenarios:

| Scenario | Behavior |
|----------|----------|
| No `.beads/dolt/` directory | Skip server start, no warning |
| Server fails to start | Log warning to stderr, continue |
| Server crashes after start | Not restarted (intentional; `bd` commands will error) |
| `dolt` binary not found | Log warning to stderr, continue |

Server crashes are not automatically recovered. If the server dies during the session, agents will see connection errors. Manual restart is required via `bd dolt start` or by restarting the container. Automatic restart via a process supervisor is a future enhancement if crash frequency warrants it.

## Implementation

### Changes to Dockerfile

Install `tini` in the base image:

```dockerfile
# docker/devenv/Dockerfile.base
RUN apt-get update && apt-get install -y --no-install-recommends tini && rm -rf /var/lib/apt/lists/*
```

Copy the entrypoint script in the devenv image:

```dockerfile
# docker/devenv/Dockerfile.devenv
COPY shared/scripts/entrypoint.sh /usr/local/share/devenv/entrypoint.sh
RUN chmod +x /usr/local/share/devenv/entrypoint.sh
```

### Changes to `devenv` Runtime Script

The `docker run` command changes from:

```bash
bash -lc "sudo /usr/sbin/sshd; exec sleep infinity"
```

To:

```bash
bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"
```

The entrypoint script handles sshd, dolt, and sleep infinity internally.

### Changes to `.beads/config.yaml`

Add `auto-start: false` to the dolt section. This is a per-project configuration that must be set after `bd init`:

```yaml
dolt:
  auto-start: false
```

This can be set manually or automated as part of a post-init hook.

### Entrypoint Script

**Path:** `shared/scripts/entrypoint.sh`

Responsibilities:

1. Start sshd via `sudo /usr/sbin/sshd`.
2. Detect `.beads/dolt/` in `$PWD`.
3. Read server port from `.beads/dolt/config.yaml` (or `.beads/dolt-server.port` if it exists).
4. Start `dolt sql-server` in background with output redirected to `.beads/dolt-server.log`.
5. Write PID to `.beads/dolt-server.pid`.
6. Health-check the server (TCP, up to 30 seconds).
7. `exec sleep infinity`.

The script must follow the coding standard: `set -euo pipefail`, `main()` function structure, input validation.

### Docker Run Command Structure

Updated command (changes marked):

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
  ... (existing mounts unchanged) ...
  <image_name> \
  bash -lc "exec tini -- /usr/local/share/devenv/entrypoint.sh"   # CHANGED
```

## Verification

- Start a devenv container for a project with an initialized beads database.
- Verify `dolt sql-server` is running: `ps aux | grep dolt`.
- From the first shell, run `bd list` -- must succeed.
- Open a second shell (`docker exec`), run `bd list` -- must succeed without lock errors.
- Open a third shell, run `bd create "test" -p 2 --json` -- must succeed.
- Verify no zombie processes: `ps aux | grep defunct` returns empty.
- Start a container for a project without `.beads/` -- container starts normally, no dolt-related errors.
- Kill the dolt server manually (`kill <pid>`), verify `bd` commands report server unavailable (not a hang or crash).

## Non-Goals

- **Process supervisor / auto-restart:** The Dolt server is not automatically restarted if it crashes. This keeps the design simple. A supervisor (e.g., s6-overlay) can be added later if needed.
- **Multi-project Dolt servers:** Each container serves one project. If a container somehow needs multiple beads databases, that is out of scope.
- **Remote Dolt access:** The server binds to `127.0.0.1` only. Cross-container or cross-host access is not addressed.
- **Dolt remote sync:** Configuring Dolt push/pull to DoltHub or other remotes is orthogonal to this spec.

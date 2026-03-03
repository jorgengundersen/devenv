# Dolt & Beads Troubleshooting

Troubleshooting guide for the dolt sql-server and beads (`bd`) issue tracker
inside devenv containers.

## Architecture Overview

A single `dolt sql-server` process runs per container, started by
`entrypoint.sh` at container boot. All `bd` commands connect to this shared
server via MySQL protocol on `127.0.0.1:<port>`.

**Port resolution order** (see `shared/scripts/entrypoint.sh`):

1. `.beads/dolt/config.yaml` key `listener.port` (authoritative)
2. `.beads/config.yaml` key `dolt.port` (fallback)
3. Default: `3306`

**Key config requirement** in `.beads/config.yaml`:

```yaml
dolt:
  auto-start: false
```

This prevents `bd` from starting its own dolt server, which would conflict with
the entrypoint-managed one.

## Quick Diagnostics

Run these commands to understand the current state:

```bash
# Is dolt running? How many instances?
ps aux | grep "dolt sql-server" | grep -v grep

# Which port is bd using?
bd dolt status

# What port does the dolt server config specify?
yq '.listener.port' .beads/dolt/config.yaml

# Can bd reach the server?
bd list --json

# Check the server log for errors
tail -50 .beads/dolt-server.log
```

## Common Problems

### "database is locked by another dolt process"

**Symptom:** `bd` commands fail with:

```
database "dolt" is locked by another dolt process
```

**Cause:** Two `dolt sql-server` processes are running against the same data
directory (`.beads/dolt/`). This typically happens when:

- The entrypoint starts dolt on one port (e.g. 3306) and `bd` starts its own
  on a different port (e.g. 13784) because the port configs disagree.
- `dolt.auto-start` is not set to `false` in `.beads/config.yaml`.

**Fix:**

```bash
# 1. Identify all dolt processes
ps aux | grep "dolt sql-server" | grep -v grep

# 2. Check which ports they use
ss -tlnp | grep dolt

# 3. Kill the wrong one (usually the one NOT matching bd's expected port)
bd dolt status          # Shows the port bd expects
kill <wrong_pid>

# 4. Verify configs agree
yq '.listener.port' .beads/dolt/config.yaml    # Authoritative port
yq '.dolt.port' .beads/config.yaml              # Should match or be absent

# 5. Ensure auto-start is disabled
grep "auto-start" .beads/config.yaml            # Must show "false"
```

**Permanent fix:** Ensure `.beads/dolt/config.yaml` has the correct
`listener.port` and that `.beads/config.yaml` has `dolt.auto-start: false`.
Restart the container.

### bd commands hang or return connection errors

**Symptom:** `bd list`, `bd ready`, or `bd create` hang or return connection
refused errors.

**Cause:** The dolt server is not running.

**Fix:**

```bash
# Check if dolt is running
ps aux | grep "dolt sql-server" | grep -v grep

# If not running, check the entrypoint log
cat ~/.local/state/devenv/$(basename $(git rev-parse --show-toplevel))/dolt-server.log

# Restart the container (cleanest fix)
# From the HOST:
devenv stop .
devenv .

# Or start dolt manually inside the container (temporary)
dolt sql-server \
  --data-dir .beads/dolt \
  --host 127.0.0.1 \
  --port $(yq '.listener.port' .beads/dolt/config.yaml) &
```

### Database corruption (corrupt backup directories appear)

**Symptom:** Directories like `.beads/dolt.<timestamp>.corrupt.backup/` appear.
`bd` may have recreated the database from JSONL backups.

**Cause:** Corruption is usually caused by two dolt servers writing to the same
data directory simultaneously (see "database is locked" above). It can also
happen if the container is killed without giving dolt time to flush.

**Recovery:**

`bd` automatically detects corruption and recovers from JSONL backups. After
recovery:

```bash
# 1. Verify bd works
bd list --json

# 2. Check if any issues were lost
bd list --json | jq length   # Compare with backup
cat .beads/backup/issues.jsonl | wc -l

# 3. Clean up old corrupt backups (optional, after verifying recovery)
ls -la .beads/*.corrupt.backup/
rm -rf .beads/dolt.*.corrupt.backup/

# 4. Fix the root cause (port mismatch) to prevent recurrence
```

### "database not found: \<name\>"

**Symptom:** Dolt server log contains:

```
unable to process ComInitDB: database not found: devenv
```

**Cause:** The dolt server started against the wrong data directory, or the
database was not initialized. This happens when the entrypoint starts dolt on
the default port 3306 but the actual database is configured for a different
port in `.beads/dolt/config.yaml`.

**Fix:** Same as the "database is locked" fix -- align the port configs and
restart the container.

### Zombie dolt processes

**Symptom:** `ps aux` shows dolt processes in `<defunct>` state.

**Cause:** A killed dolt process whose parent hasn't reaped it yet. `tini`
(PID 1) should reap these eventually, but if the parent process is still alive
and not waiting on its children, zombies can accumulate.

**Fix:** Zombies are harmless (they consume no resources beyond a PID table
entry). They are cleaned up on container restart. If many accumulate:

```bash
# Check for zombies
ps aux | grep defunct

# Restart the container to clean up
# From the HOST:
devenv stop .
devenv .
```

## Configuration Reference

### `.beads/config.yaml` (beads project config)

```yaml
dolt:
  auto-start: false   # REQUIRED -- entrypoint manages the server
  port: 13784          # Fallback port (should match dolt server config)
```

### `.beads/dolt/config.yaml` (dolt server config)

```yaml
listener:
  host: 127.0.0.1
  port: 13784          # Authoritative port -- entrypoint reads this first
```

### State files

| File | Location | Purpose |
|------|----------|---------|
| Entrypoint PID | `$XDG_STATE_HOME/devenv/<project>/dolt-server.pid` | PID of entrypoint-started dolt |
| Entrypoint log | `$XDG_STATE_HOME/devenv/<project>/dolt-server.log` | Entrypoint dolt server log |
| bd PID | `.beads/dolt-server.pid` | PID of bd-managed dolt (should not exist if auto-start is false) |
| bd log | `.beads/dolt-server.log` | bd-managed dolt server log |
| bd port | `.beads/dolt-server.port` | Port bd is using |
| bd lock | `.beads/dolt-server.lock` | Server lock file |

## Preventive Checks

Run these after any changes to dolt/beads configuration:

```bash
# Exactly one dolt process should be running
test $(ps aux | grep "dolt sql-server" | grep -v grep | wc -l) -eq 1 \
  && echo "OK: single dolt server" \
  || echo "PROBLEM: expected exactly 1 dolt server"

# Port should match between configs
DOLT_PORT=$(yq '.listener.port' .beads/dolt/config.yaml 2>/dev/null)
BD_STATUS_PORT=$(bd dolt status 2>/dev/null | grep Port | awk '{print $2}')
test "$DOLT_PORT" = "$BD_STATUS_PORT" \
  && echo "OK: ports match ($DOLT_PORT)" \
  || echo "PROBLEM: dolt config says $DOLT_PORT, bd uses $BD_STATUS_PORT"

# auto-start must be false
AUTO=$(yq '.dolt["auto-start"]' .beads/config.yaml 2>/dev/null)
test "$AUTO" = "false" \
  && echo "OK: auto-start is false" \
  || echo "PROBLEM: auto-start is '$AUTO', should be 'false'"
```

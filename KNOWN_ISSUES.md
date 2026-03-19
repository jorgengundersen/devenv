# Known Issues

## claude.json bind-mounted read-write (quick fix)

**Date:** 2026-03-15
**Status:** Workaround in place

**Problem:** Claude Code writes project state (trust dialogs, session info) to
`~/.claude.json` at runtime. When the file was bind-mounted read-only (`:ro`),
writes failed with `EROFS: read-only file system`, causing Claude Code to
silently hang on startup — no output, no error.

**Current fix:** Changed the bind-mount from `:ro` to `:rw` in `bin/devenv` so
Claude Code can write to the file. This means container runtime state (project
paths, sessions) leaks back into `shared/config/claude/claude.json`.

**Clean fix (TODO):** Bake the seed `claude.json` into the Docker image or copy
it during container startup (e.g. in the entrypoint). This gives the container a
writable copy while keeping the repo config file clean. Revisit if the repo file
starts accumulating container-specific state.

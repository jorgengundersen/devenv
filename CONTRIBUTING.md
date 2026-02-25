# Contributing to devenv

This guide explains how to add, modify, or remove tools and functionality in
the devenv framework. It is written for both human contributors and coding
agents.

Before making changes, read these documents:

- [specs/coding-standard.md](specs/coding-standard.md) -- mandatory coding
  rules for Bash scripts and Dockerfiles
- [specs/devenv-architecture.md](specs/devenv-architecture.md) -- system design and architecture

## Architecture overview

```
docker/base/Dockerfile.base             Ubuntu 24.04 + devuser + core utilities
       |
docker/devenv/Dockerfile.base           Devenv base with SSH
       |
shared/tools/Dockerfile.*               One tool per Dockerfile, independent build stages
       |
docker/devenv/Dockerfile.devenv         Multi-stage build that aggregates all tools via COPY --from
       |
<project>/.devenv/Dockerfile   (optional) Project-specific layer extending devenv:latest
```

The `devenv` script launches and attaches to persistent containers.
The `build-devenv` script builds images at each layer.

---

## 1. Adding a tool

This is the most common change. You need to touch four files.

### Step 1: Create the tool Dockerfile

Create `shared/tools/Dockerfile.<toolname>`.

Every tool Dockerfile follows the same structure:

```dockerfile
# syntax=docker/dockerfile:1

# Tool: <toolname> (<short description>)

FROM repo-base:latest AS tool_<toolname>
LABEL tools=true

USER root

# Install <toolname>
RUN <installation commands>

# Change ownership to devuser
RUN chown devuser:devuser /usr/local/bin/<toolname>

USER devuser
```

Rules:

- Stage name must be `tool_<toolname>`.
- `LABEL tools=true` is required.
- Install as `root`, then `chown` to `devuser` and end with `USER devuser`.
- Place binaries in `/usr/local/bin/` when possible.
- Chain related `RUN` commands with `&&` and clean up caches in the same layer.
- Use `--no-install-recommends` on every `apt-get install`.
- Never use `ADD` when `COPY` suffices.
- Never use `curl | bash` without the `-f` flag.

#### Reference examples

| Complexity | File | Pattern |
|------------|------|---------|
| Simple (single binary download) | `shared/tools/Dockerfile.yq` | Download binary, `chmod`, done |
| Simple (installer script) | `shared/tools/Dockerfile.starship` | Run installer, `chown` binary |
| Medium (apt repository) | `shared/tools/Dockerfile.gh` | Add apt key + source, `apt-get install`, clean up |
| Medium (install + relocate) | `shared/tools/Dockerfile.uv` | Run installer, move binaries to `/usr/local/bin/` |
| Complex (depends on another tool) | `shared/tools/Dockerfile.node` | Multi-stage: build `fnm` first, then use it to install Node |
| Complex (external image dependency) | `shared/tools/Dockerfile.ripgrep` | Pulls from `tools-jq:latest`, copies `jq` in |

### Step 2: Add the tool stage to Dockerfile.devenv

Open `docker/devenv/Dockerfile.devenv` and add two things:

**A. A build stage** in the appropriate section. Place independent tools in
Stage 2 or Stage 4; tools that depend on other stages go in Stage 3.

```dockerfile
FROM repo-base:latest AS tool_<toolname>
USER root
RUN <same installation commands as the standalone Dockerfile>
```

**B. A `COPY --from` line** in the final `devenv` stage, inside the
"Copy all tool artifacts" block:

```dockerfile
COPY --from=tool_<toolname> /usr/local/bin/<toolname> /usr/local/bin/<toolname>
```

For multi-file tools (entire directories), copy the directory:

```dockerfile
COPY --from=tool_<toolname> /opt/<toolname> /opt/<toolname>
```

If the tool adds a new directory to `PATH`, update the `ENV PATH=` line in the
final stage.

### Step 3: Update build-devenv usage text

Add the new tool name to the `--tool` valid tools list in the `usage()`
function (`build-devenv`, around line 46):

```
Valid tools: cargo, copilot-cli, fnm, fzf, gh, go, <toolname>, jq, node, ...
```

Keep the list alphabetically sorted.

### Step 4: Update README.md

Add the tool to the "Available Tools" list in `README.md` (alphabetical order):

```markdown
- **<toolname>** - <short description>
```

Also add it to the architecture tree if you want it listed there.

### Step 5: If the tool has host configuration

If users configure this tool via files on the host (e.g., `~/.config/<tool>/`),
add a mount point. See [Section 4: Adding a mount point](#4-adding-a-mount-point).

### Verification

```bash
# Build the tool in isolation to test it
build-devenv --tool <toolname>

# Rebuild the full devenv image
build-devenv --stage devenv

# Start a container and verify the tool works
devenv .
<toolname> --version
```

---

## 2. Removing a tool

### Step 1: Check for dependents

Before removing, check whether other tools depend on it. Known dependencies:

| Tool | Depended on by |
|------|----------------|
| `fnm` | `node` (uses fnm to install Node.js) |
| `cargo` | `ripgrep` (copied into ripgrep stage in `docker/devenv/Dockerfile.devenv`) |
| `jq` | `ripgrep` (used to parse GitHub API response) |

If other tools depend on the one you are removing, you must update or remove
those dependents first.

### Step 2: Remove from Dockerfile.devenv

Remove both:
- The build stage (`FROM ... AS tool_<toolname>` and its `RUN` commands)
- The `COPY --from=tool_<toolname>` line(s) in the final stage

If the tool contributed a `PATH` entry, remove it from the `ENV PATH=` line.

### Step 3: Delete the standalone Dockerfile

```bash
rm shared/tools/Dockerfile.<toolname>
```

### Step 4: Update build-devenv usage text

Remove the tool name from the `--tool` valid tools list in `usage()`.

### Step 5: Update README.md

Remove the tool from the "Available Tools" list and the architecture tree.

### Step 6: Remove mount points (if any)

If the tool had a config mount in `build_mounts()` (in the `devenv` script),
remove the corresponding `if` block. Also remove it from the "Configuration
Mount Points" table in `README.md`.

### Verification

```bash
build-devenv --stage devenv
devenv .
# Confirm the tool is no longer present
which <toolname>  # should fail
```

---

## 3. Adding a mount point

Mount points allow host configuration files to be available inside the
container. All mount logic lives in the `build_mounts()` function in the
`devenv` script (around line 156).

### When to add a mount

Add a mount when a tool inside the container needs to read configuration from
the host. Examples: editor config (`nvim`), shell prompt config (`starship`),
CLI auth tokens (`gh`).

### Step 1: Add the mount to build_mounts()

Open the `devenv` script and find the `build_mounts()` function. Add a
conditional block following the existing pattern:

**For a directory:**

```bash
if [[ -d "${HOME}/.config/<tool>" ]]; then
    mounts_ref+=("-v" "${HOME}/.config/<tool>:/home/devuser/.config/<tool>:ro")
fi
```

**For a single file:**

```bash
if [[ -f "${HOME}/.config/<tool>/config.json" ]]; then
    mounts_ref+=("-v" "${HOME}/.config/<tool>/config.json:/home/devuser/.config/<tool>/config.json:ro")
fi
```

Rules:

- Always wrap in an `if` that checks the path exists. The mount is skipped
  silently when the host path is absent.
- Use `:ro` (read-only) for configuration. Only the project directory uses `:rw`.
- Container paths generally mirror the host structure under `/home/devuser/`.
  Exception: opencode config is sourced from the repository file
  `shared/config/opencode/opencode.devenv.jsonc`, mounted read-only at
  `/home/devuser/.config/opencode/opencode.jsonc`, and
  `OPENCODE_CONFIG` defaults to that container path when unset. The host
  directory `~/.config/opencode/` is not mounted.

### Step 2: Update README.md

Add a row to the "Configuration Mount Points" table:

```markdown
| <tool> | `~/.config/<tool>/` | `/home/devuser/.config/<tool>/` |
```

### Verification

```bash
# Create a test config on the host
mkdir -p ~/.config/<tool>
echo "test" > ~/.config/<tool>/config

# Stop any running container, then restart
devenv stop .
devenv .

# Inside the container, verify the mount
cat ~/.config/<tool>/config  # should print "test"
ls -la ~/.config/<tool>/     # should show read-only
```

### Persistent volumes vs config mounts

The devenv runtime uses two types of mounts:

- **Config bind mounts (`:ro`)** -- host configuration directories/files mounted read-only into the container. These are managed in `build_mounts()` and described in Section 3 above.
- **Persistent named volumes** -- Docker-managed volumes for runtime state (XDG data, cache, state). These are defined as constants (`VOLUME_DATA`, `VOLUME_CACHE`, `VOLUME_STATE`) and provisioned by `ensure_volumes()` in the `devenv` script.

When a tool needs to persist runtime data (caches, plugins, logs, history), it writes to the appropriate XDG directory inside the container. The named volumes automatically persist this data. No code changes are needed for new tools that follow XDG conventions.

The `devenv volume` commands (`list`, `rm`, `rm --all`, `rm --force`) provide operational visibility and cleanup for these volumes.

---

## 4. Adding a project template

Project templates live in `docker/devenv/templates/` and provide starting points for
project-specific Dockerfiles.

### Step 1: Create the template

Create `docker/devenv/templates/Dockerfile.<type>`. All templates must:

- Extend `devenv:latest` (never `devenv-base:latest`).
- Install as `root`, then switch to `devuser`.
- Set `WORKDIR /home/devuser` (runtime `--workdir` overrides to the project path).
- End with `USER devuser` and `CMD ["/bin/bash"]`.
- Use comments to explain project-specific customization points.

Use `docker/devenv/templates/Dockerfile.python-uv` as a reference:

```dockerfile
# <Type> Project
# Template for <type> projects

FROM devenv:latest

USER root

# Set working directory (runtime --workdir overrides)
WORKDIR /home/devuser

# Environment variables
ENV KEY=value

# Install project-specific dependencies
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     <dependency> \
#     && rm -rf /var/lib/apt/lists/*

# Change ownership
# (Not needed for project files — bind mount uses UID matching)

USER devuser

# Default command
CMD ["/bin/bash"]
```

### Step 2: Update docker/devenv/templates/README.md

Add a section for the new template with a description and usage example:

```markdown
### Dockerfile.<type>

<Description of when to use this template.>

**Usage:**
\```bash
cp Dockerfile.<type> /path/to/your/project/.devenv/Dockerfile
\```
```

### Verification

```bash
# Copy template to a test project
mkdir -p /tmp/test-project/.devenv
cp docker/devenv/templates/Dockerfile.<type> /tmp/test-project/.devenv/Dockerfile

# Build and start
build-devenv --project /tmp/test-project
devenv /tmp/test-project
```

---

## 5. Modifying the base image or devenv image

These images are the foundation for every container. Changes here affect all
tools, all projects, and all users. Modify them only when necessary.

### When to modify Dockerfile.base

Modify `docker/devenv/Dockerfile.base` only when the change is required by the core
container infrastructure. This includes:

- **OS-level packages needed by multiple tools** (e.g., adding `unzip` if
  three or more tools need it).
- **Changes to the user/group setup** (UID/GID handling, sudo configuration).
- **SSH server configuration changes**.
- **Core directory structure** (`/home/devuser/.ssh`).

### When NOT to modify Dockerfile.base

Do not modify `docker/devenv/Dockerfile.base` for:

- A package needed by only one tool. Install it in that tool's Dockerfile
  instead.
- Language runtimes or development tools. These belong in `shared/tools/`.
- Configuration files. These are bind-mounted at runtime.
- Anything that only one project needs. Use a project-specific
  `.devenv/Dockerfile` instead.

### When to modify Dockerfile.devenv

The final stage of `docker/devenv/Dockerfile.devenv` (the `devenv` stage starting with
`FROM common_utils AS devenv`) handles artifact composition: copying
binaries from tool stages, setting `PATH`, and fixing ownership.

Modify it when:

- **Adding or removing a tool** (see Sections 1 and 2).
- **A new tool requires a shared environment variable** (add to the `ENV`
  block in the final stage).
- **Ownership or permissions need adjustment** for a new install location.

### When NOT to modify Dockerfile.devenv

Do not modify `docker/devenv/Dockerfile.devenv` for:

- Installing packages directly in the final stage. Each tool should have its
  own build stage, and only the artifacts should be copied in.
- Project-specific dependencies. Use `.devenv/Dockerfile`.

### Procedure for base image changes

1. Make the change in `docker/base/Dockerfile.base`.
2. Rebuild the repo base image: `build-devenv --stage base`.
3. Rebuild the devenv base image: `build-devenv --stage devenv-base`.
4. Rebuild the devenv image: `build-devenv --stage devenv`.
5. Test that all existing tools still work.
6. Test with at least one project-specific image.

### Procedure for devenv final stage changes

1. Make the change in `docker/devenv/Dockerfile.devenv` (final stage only).
2. Rebuild: `build-devenv --stage devenv`.
3. Verify the change inside a container: `devenv .`.

---

## Checklist for all changes

Before submitting any change, verify:

- [ ] Dockerfiles start with `# syntax=docker/dockerfile:1`.
- [ ] Tool images have `LABEL tools=true`, environment images have `LABEL devenv=true`, repo-base has `LABEL repo-base=true`.
- [ ] Tool stages are named `tool_<name>`.
- [ ] Final `USER` is `devuser` in every Dockerfile.
- [ ] No `ADD` used where `COPY` suffices.
- [ ] No `chmod 777` anywhere.
- [ ] No hardcoded secrets or tokens.
- [ ] `apt-get install` uses `--no-install-recommends` and cleans up with
      `rm -rf /var/lib/apt/lists/*` in the same `RUN` layer.
- [ ] Bash scripts pass `shellcheck` with zero warnings.
- [ ] Bash functions use `local` for all variables.
- [ ] Return values use `printf`, not `echo`.
- [ ] `README.md` reflects the change (tools list, architecture tree, mount
      table, as applicable).
- [ ] `build-devenv` usage text is updated if tool list changed.
- [ ] Full rebuild succeeds: `build-devenv --stage base && build-devenv --stage devenv-base && build-devenv --stage devenv`.
- [ ] Container starts and the change works: `devenv .`.

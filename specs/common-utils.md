# Common Utils Stage Specification

## Goal
Provide a curated baseline of small CLI utilities in the main `devenv` image
without bloating the base image or mixing tool responsibilities.

## Motivation
The base image should remain minimal and focused on OS setup, user creation, and
SSH support. Common CLI utilities are expected by most developers, but do not
belong in the base layer. A dedicated `common_utils` stage creates a clear
boundary between core OS setup and developer conveniences.

## Architecture

### Build Pipeline Integration

```
docker/devenv/Dockerfile.base
    ↓
docker/devenv/Dockerfile.devenv (common_utils stage)
    ↓
docker/devenv/Dockerfile.devenv (devenv stage, FROM common_utils)
```

### Stage Structure

- `common_utils` is a build stage based on `devenv-base`.
- `devenv` is based on `common_utils` so the packages are present at runtime.
- Tool stages remain independent and are still aggregated into the final image
  via `COPY --from=tool_<name>`.

### Naming

Stage name: `common_utils`

Rationale: this is a baseline composition stage, not an isolated tool build.

## Package Set

Included (small, widely used):

- `tree`
- `less`
- `man-db` (no manpages by default)
- `file`
- `unzip`, `zip`
- `procps` (ps/top)
- `lsof`
- `iproute2` (ip)
- `iputils-ping` (ping)
- `dnsutils` (dig)
- `netcat-openbsd` (nc)

Excluded (explicitly):

- `eza`/`exa`
- `fd`
- `bat`

### Optional Packages

These are intentionally excluded from the default stage and may be added as a
separate tool stage if needed:

- `build-essential` (meta package, large footprint)
- `manpages` (adds size without critical runtime value)

## Implementation Requirements

1. Add `shared/tools/Dockerfile.common-utils` with a single `apt-get install`
   list matching the package set above.
2. Add a `common_utils` stage in `docker/devenv/Dockerfile.devenv` using the
   same package list.
3. Change the final stage base to `FROM common_utils AS devenv`.
4. Update `bin/build-devenv` tool list and `README.md` available tools list.

## Verification

- `build-devenv --tool common-utils`
- `build-devenv --stage devenv`
- In a container: verify `tree`, `less`, `man`, `file`, `ip`, `dig`, `nc`.

## Non-Goals

- Replace or modify existing tool stages.
- Add opinionated developer tools (ripgrep, fzf, bat, fd, exa).
- Include full toolchains by default (`build-essential`).

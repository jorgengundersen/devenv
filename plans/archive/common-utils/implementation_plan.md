# Implementation Plan: Common Utils

Source research: `plans/current/common-utils/research.md`

Specs (must satisfy):

- `specs/common-utils.md`
- `specs/devenv-architecture.md`

Goal: add a curated baseline of common CLI utilities to the final `devenv` image via a dedicated `common_utils` stage and a corresponding buildable tool Dockerfile (`common-utils`).

Non-goals (per spec): do not add `eza`/`exa`, `fd`, `bat`, `build-essential`, or `manpages`.

## Package Set (Authoritative)

Install exactly this set, with `--no-install-recommends`:

- `tree`
- `less`
- `man-db`
- `file`
- `unzip`
- `zip`
- `procps`
- `lsof`
- `iproute2`
- `iputils-ping`
- `dnsutils`
- `netcat-openbsd`

## Execution Checklist

- [ ] Create `shared/tools/Dockerfile.common-utils`.
- [ ] Add `common_utils` stage to `docker/devenv/Dockerfile.devenv` (package list must match tool Dockerfile).
- [ ] Change final stage base to `FROM common_utils AS devenv`.
- [ ] Update `bin/build-devenv` help text to include `common-utils`.
- [ ] Update `README.md` (Available Tools + architecture description) to include `common-utils` and the new `common_utils` stage.
- [ ] Update `specs/devenv-architecture.md` to reflect the new architecture (build pipeline + file tree + tool documentation).
- [ ] Confirm `specs/README.md` still links to `specs/common-utils.md` (update only if needed).
- [ ] Optional cleanup: align `proposal.md` wording with implemented stage naming (`common_utils` vs `tool_common_utils`).
- [ ] Run verification builds and runtime checks.

## Step Details

### 1) Add tool Dockerfile for `common-utils`

Create `shared/tools/Dockerfile.common-utils`.

Constraints:

- [ ] Single `apt-get install` list containing the full package set above.
- [ ] Buildable via `build-devenv --tool common-utils`.

Use this exact file content:

```dockerfile
# syntax=docker/dockerfile:1

# Tool: common-utils
# Installs a baseline of small CLI utilities expected in most environments.

FROM devenv-base:latest AS tool_common_utils
LABEL devenv=true

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tree \
        less \
        man-db \
        file \
        unzip \
        zip \
        procps \
        lsof \
        iproute2 \
        iputils-ping \
        dnsutils \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

USER devuser
```

Notes:

- [ ] Do not add any other packages.
- [ ] Keep this as a single `RUN` install block (spec requirement).

### 2) Add `common_utils` stage to the main devenv Dockerfile

Edit `docker/devenv/Dockerfile.devenv`.

Add a new stage after the existing `devenv-base` stage definition:

```dockerfile
# Stage 1.5: Common CLI utilities
FROM devenv-base:latest AS common_utils
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        tree \
        less \
        man-db \
        file \
        unzip \
        zip \
        procps \
        lsof \
        iproute2 \
        iputils-ping \
        dnsutils \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*
```

Constraints:

- [ ] Use the exact same package list as in `shared/tools/Dockerfile.common-utils`.
- [ ] Keep this as a single `RUN` install block (spec requirement).
- [ ] Do not change existing tool stages to depend on `common_utils` (spec says tool stages remain independent).

### 3) Base the final `devenv` stage on `common_utils`

In `docker/devenv/Dockerfile.devenv`, change the final stage header:

- Replace `FROM devenv-base:latest AS devenv`
- With `FROM common_utils AS devenv`

Do not change the rest of the final stage content unless needed to resolve build errors.

### 4) Wire `common-utils` into the build script help/tool list

Edit `bin/build-devenv`.

Update the `usage()` text under `--tool <tool>` so `common-utils` is listed as a valid tool.

Change this line (or its equivalent):

- `Valid tools: cargo, copilot-cli, fnm, fzf, gh, go, jq, node, nvim, opencode, ripgrep, starship, tree-sitter, uv, yq`

To include `common-utils` (keep alphabetical or match existing ordering; either is fine as long as it appears in the list). Recommended ordering:

- `Valid tools: cargo, common-utils, copilot-cli, fnm, fzf, gh, go, jq, node, nvim, opencode, ripgrep, starship, tree-sitter, uv, yq`

Optional (recommended): add an example line in `usage()`:

- `build-devenv --tool common-utils`

No other script logic changes are required because the script already resolves tools by checking for `shared/tools/Dockerfile.<tool>`.

### 5) Document `common-utils` in README

Edit `README.md`.

Update the following sections:

- [ ] **Available Tools**: add `common-utils` with a short description, for example:

- `**common-utils** - Baseline CLI utilities (tree/less/man/file/network tools)`

- [ ] **Architecture tree** (the code block showing the repo layout): add `shared/tools/Dockerfile.common-utils`.
- [ ] If the README describes the build pipeline as “base -> tools -> devenv”, update the wording to include the `common_utils` stage as part of `docker/devenv/Dockerfile.devenv` (base -> common_utils -> devenv), while keeping tool images independent.

### 6) Update system spec documentation (`specs/devenv-architecture.md`)

This change affects the overall architecture; update `specs/devenv-architecture.md` so it matches the implemented pipeline.

Make these edits (minimum required):

- [ ] **Build Pipeline diagram**: update the pipeline to include `common_utils` as an intermediate stage in `docker/devenv/Dockerfile.devenv`.
  - Base remains `docker/devenv/Dockerfile.base`.
  - Tools remain `shared/tools/Dockerfile.*` and are copied into the final image as before.
  - New intermediate composition stage: `docker/devenv/Dockerfile.devenv (common_utils stage)`.
  - Final stage now starts from `common_utils`.

Suggested replacement snippet for the pipeline block in `specs/devenv-architecture.md`:

```text
docker/devenv/Dockerfile.base (Ubuntu + devuser + SSH)
    ↓
docker/devenv/Dockerfile.devenv (common_utils stage, FROM devenv-base)
    ↓
shared/tools/Dockerfile.* (one tool per Dockerfile, built independently)
    ↓
docker/devenv/Dockerfile.devenv (devenv stage, FROM common_utils, aggregates tools via multi-stage COPY)
    ↓
<project>/.devenv/Dockerfile (extends devenv with project deps)
```

- [ ] **File Tree**: add `shared/tools/Dockerfile.common-utils` to the listed tree (and keep existing entries intact).
- [ ] **Tool Images section**: ensure `common-utils` is mentioned as a valid `--tool` build target (it is a tool image for isolated builds) and clarify that the runtime baseline comes from the `common_utils` stage in `docker/devenv/Dockerfile.devenv`.

If `specs/devenv-architecture.md` also contains a "build order" list, do not force `common-utils` into the tool dependency order (it is not a tool dependency); it is part of the main image layering.

Also update any other documentation blocks in `specs/devenv-architecture.md` that enumerate tool Dockerfiles or valid `--tool` values so they include `common-utils`.

### 7) Optional: Align `proposal.md`

`proposal.md` currently references stage naming; update it to match the implemented design:

- [ ] Use `common_utils` as the composition stage name.
- [ ] Ensure the final stage base is described as `FROM common_utils AS devenv`.
- [ ] Remove references to `build-essential` as part of the default package list (it is explicitly optional/excluded by `specs/common-utils.md`).
- [ ] Replace any mention of `tool_common_utils` as the stage the final image is based on; the final image must be based on `common_utils`.

## Verification (must pass)

All commands are run from the repo root.

1. Build base image:

```bash
build-devenv --stage base
```

2. Build the standalone common utils tool image:

```bash
build-devenv --tool common-utils
```

3. Build the full devenv image (this must now include `common_utils` packages at runtime):

```bash
build-devenv --stage devenv
```

4. Runtime verification inside the built image:

```bash
docker run --rm devenv:latest bash -lc 'command -v tree less man file ip dig nc && tree --version && less --version | head -n 1 && man --version | head -n 1 && file --version | head -n 1 && ip -V && dig -v && nc -h 2>&1 | head -n 1'
```

Acceptance criteria:

- [ ] `build-devenv --tool common-utils` succeeds.
- [ ] `build-devenv --stage devenv` succeeds.
- [ ] The runtime verification command succeeds (all binaries present; version/help outputs return exit code 0).
- [ ] Package set matches the list in `specs/common-utils.md` and excludes explicitly excluded/optional packages.

## Self-check against spec

Before considering the work done, confirm:

- [ ] `shared/tools/Dockerfile.common-utils` exists and contains only the specified apt install list.
- [ ] `docker/devenv/Dockerfile.devenv` contains a `common_utils` stage based on `devenv-base` with the same install list.
- [ ] Final stage is `FROM common_utils AS devenv`.
- [ ] `bin/build-devenv` help lists `common-utils` as a valid tool.
- [ ] `README.md` lists `common-utils` under Available Tools.
- [ ] `specs/devenv-architecture.md` build pipeline and file tree reflect the `common_utils` stage.

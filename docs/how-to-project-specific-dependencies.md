# How-To: Project-Specific Dependencies with devenv

Use this guide when a project needs extra dependencies that should not be added to the global `devenv:latest` image.

## What this gives you

- A per-project image built from `<project>/.devenv/Dockerfile`
- Isolated dependencies for that project only
- A repeatable setup that agents can apply in any repo

## Prerequisites

- `devenv` and `build-devenv` installed
- Docker daemon running
- Base image available (`build-devenv --stage devenv`)
- Project path is under your host `${HOME}` (required by `devenv`)

## Quick setup (copy/paste)

From the `devenv` repository:

```bash
mkdir -p /path/to/project/.devenv
cp docker/devenv/templates/Dockerfile.project /path/to/project/.devenv/Dockerfile
```

Edit `/path/to/project/.devenv/Dockerfile` and add project dependencies.

Then build and launch:

```bash
build-devenv --project /path/to/project
devenv /path/to/project
```

## Recommended Dockerfile pattern

Use this structure for project-specific dependencies:

```dockerfile
FROM devenv:latest

USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    redis-tools \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /home/devuser
USER devuser
CMD ["/bin/bash"]
```

Rules:

- Always `FROM devenv:latest`
- Install system packages as `root`
- Switch back to `USER devuser`
- Keep project-only dependencies here (do not modify global Dockerfiles)

## Verify dependencies are available

```bash
devenv exec /path/to/project -- psql --version
devenv exec /path/to/project -- redis-cli --version
```

If the command succeeds, the dependency is in the project image.

## Rebuild behavior (important)

`devenv /path/to/project` auto-builds the project image only when the image does not already exist.

If you change `.devenv/Dockerfile`, rebuild explicitly:

```bash
build-devenv --project /path/to/project
devenv stop /path/to/project
devenv /path/to/project
```

## Agent checklist

Use this exact checklist when setting up a new project:

1. Ensure `<project>/.devenv/Dockerfile` exists (copy from template if missing).
2. Confirm the Dockerfile starts with `FROM devenv:latest`.
3. Add only project-specific dependencies.
4. Build with `build-devenv --project <project-path>`.
5. Start with `devenv <project-path>`.
6. Verify using `devenv exec <project-path> -- <tool> --version`.

## Troubleshooting

- `Project path must be under /home/<user>`: move the project under `${HOME}`.
- `Project Dockerfile not found`: create `<project>/.devenv/Dockerfile`.
- Dependencies not updated after edits: rerun `build-devenv --project <project-path>`.
- `Devenv image not found`: run `build-devenv --stage devenv` first.

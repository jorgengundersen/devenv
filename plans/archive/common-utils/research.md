# Common Utils Gap Analysis

Spec: `specs/common-utils.md`

## Current State Snapshot

- `docker/devenv/Dockerfile.devenv` has tool stages and final `devenv` stage based on `devenv-base`; no `common_utils` stage present.
- `shared/tools/` has per-tool Dockerfiles only; no `Dockerfile.common-utils`.
- `bin/build-devenv` tool list does not include `common-utils`.
- `README.md` available tools list does not mention `common-utils`.

## Spec Requirements vs Current State

1) Add `shared/tools/Dockerfile.common-utils` with a single `apt-get install` list matching the package set.
- Gap: File does not exist.

2) Add a `common_utils` stage in `docker/devenv/Dockerfile.devenv` using the same package list.
- Gap: No `common_utils` stage in the Dockerfile.

3) Change final stage base to `FROM common_utils AS devenv`.
- Gap: Final stage is `FROM devenv-base:latest AS devenv`.

4) Update `bin/build-devenv` tool list and `README.md` available tools list.
- Gap: `bin/build-devenv` help text/tool validation does not include `common-utils`.
- Gap: `README.md` does not list `common-utils`.

## Package Set Compliance

Required packages (spec): `tree`, `less`, `man-db`, `file`, `unzip`, `zip`, `procps`, `lsof`, `iproute2`, `iputils-ping`, `dnsutils`, `netcat-openbsd`.
- Gap: No install list present anywhere for these packages in the common utils context.

Explicitly excluded packages: `eza`/`exa`, `fd`, `bat`.
- Gap: Not applicable until common-utils is implemented; ensure these are not added.

Optional packages to keep out by default: `build-essential`, `manpages`.
- Gap: Not applicable until common-utils is implemented; ensure they remain excluded.

## Verification Gaps

- No `build-devenv --tool common-utils` path.
- No `common_utils` stage to build via `build-devenv --stage devenv`.
- No documented or scripted verification for `tree`, `less`, `man`, `file`, `ip`, `dig`, `nc` in container.

## Notes

- `proposal.md` references a `common-utils` tool stage and `common_utils` stage but the implementation is missing.
- Branch name `feat/common-utils` suggests work is intended but not completed yet.

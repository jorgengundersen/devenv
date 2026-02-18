# Common Utils Proposal

## Goal
Add a curated set of small, commonly expected CLI utilities to the devenv image
without bloating the base image or mixing tool responsibilities.

## Summary of the Idea
Create a dedicated tool stage called `common-utils` that installs a set of
small utilities via apt, and make the final `devenv` image inherit from that
stage (so the packages are present at runtime).

This keeps `docker/devenv/Dockerfile.base` minimal while still shipping a
useful baseline of standard CLI tools.

## Proposed Package Set
Included (small, widely used):

- tree
- less
- man-db (optionally manpages)
- file
- unzip, zip
- build-essential (make/gcc/g++)
- procps (ps/top)
- lsof
- iproute2 (ip)
- iputils-ping (ping)
- dnsutils (dig)
- netcat-openbsd (nc)

Excluded (explicitly):

- eza/exa
- fd
- bat

## Implementation Sketch

1) Add `shared/tools/Dockerfile.common-utils` with apt install list.
2) Add `tool_common_utils` stage in `docker/devenv/Dockerfile.devenv` with the
   same apt install list.
3) Change the final stage base to `FROM tool_common_utils AS devenv`.
4) Update `bin/build-devenv` tool list and `README.md` available tools list.

## Open Questions

- Should `tree` remain in `docker/devenv/Dockerfile.base`, or be included only
  via `common-utils`?
- Should `manpages` be included alongside `man-db`?
- Is `build-essential` acceptable for all users, or should it remain scoped to
  tool stages only?

## Verification

- build-devenv --tool common-utils
- build-devenv --stage devenv
- In a container: verify `tree`, `less`, `man`, `file`, `ip`, `dig`, `nc`.

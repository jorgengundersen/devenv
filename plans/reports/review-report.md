# Project Review Report — devenv

**Date:** 2026-02-21
**Reviewer:** Automated (claude-opus-4.6)

## Status update (2026-02-23)

- `P0-3` (`gh-copilot` mount undocumented) is resolved in `README.md`.
- `P1-2` (`opencode/auth.json` mount undocumented) is resolved in `README.md`.
- `README.md` now also documents repo-managed opencode config mount behavior (`shared/config/opencode/opencode.devenv.jsonc` -> `/home/devuser/.config/opencode.jsonc`) and the Docker forwarder `/forwards/expose ... 500` SSH publish fallback.

## Findings

### P0 — Broken / Spec-Violating

- **[P0-1] Missing `--no-install-recommends` on apt-get install in Dockerfile.devenv** — Coding standard §2.3 mandates this flag on every `apt-get install`. No exceptions.
  - `docker/devenv/Dockerfile.devenv:118:apt-get install gh -y` (missing `--no-install-recommends`)

- **[P0-2] Missing `fzf` from README "Available Tools" list** — Tool is built, shipped, and referenced in CONTRIBUTING.md but invisible to users in the primary README.
  - `README.md:131-147` — lists 15 tools, omits fzf
  - `bin/build-devenv:34` — fzf in valid tools list
  - `shared/tools/Dockerfile.fzf` — exists and is used

- **[P0-3] `gh-copilot` mount point undocumented** — Implementation mounts the directory but README config table omits it, so users won't know to set it up.
  - `bin/devenv:221-222:~/.config/gh-copilot/:/home/devuser/.config/gh-copilot/:ro`
  - `README.md:203-218` — no gh-copilot row

### P1 — Likely Bug / Major Drift

- **[P1-1] Missing `# syntax=docker/dockerfile:1` directive in template Dockerfiles** — Coding standard §2.2 requires this as the first line.
  - `docker/devenv/templates/Dockerfile.python-uv:1`
  - `docker/devenv/templates/Dockerfile.project:1`

- **[P1-2] `opencode/auth.json` mount undocumented** — Auth file is silently mounted but not in README config table.
  - `bin/devenv:227-229:~/.local/share/opencode/auth.json:/home/devuser/.local/share/opencode/auth.json:ro`

- **[P1-3] CONTRIBUTING.md references wrong line number for tools list** — Says "around line 46" but actual location is line 34.
  - `CONTRIBUTING.md:115:"valid tools list in the usage() function (build-devenv, around line 46)"`
  - `bin/build-devenv:34` — actual location

- **[P1-4] Pipe-to-grep patterns mask docker command failures** — Multiple `docker ps/images ... | grep -q` patterns hide upstream errors due to pipefail semantics.
  - `bin/devenv:171`, `bin/devenv:263`, `bin/devenv:288`
  - `bin/build-devenv:128`, `bin/build-devenv:155`, `bin/build-devenv:160`

### P2 — Maintainability / Minor Drift

- **[P2-1] Duplicated `derive_project_image_suffix` function across scripts** — Same logic in two files.
  - `bin/devenv:144-158` and `bin/build-devenv:85-99`

- **[P2-2] Commented-out code in template Dockerfiles** — Coding standard §4.1 forbids commented-out code.
  - `docker/devenv/templates/Dockerfile.python-uv:20-26`
  - `docker/devenv/templates/Dockerfile.project:9-12`

- **[P2-3] README architecture tree missing `Dockerfile.fzf`** — Tree lists 14 tool Dockerfiles but there are 16.
  - `README.md:114-128`

- **[P2-4] CHANGELOG references removed `devenv-tvim-lock` volume** — Stale reference in v1.2.0 entry.
  - `CHANGELOG.md:68`

## Evidence

| ID | File:Line | Snippet / Detail |
|---|---|---|
| P0-1 | `docker/devenv/Dockerfile.devenv:118` | `apt-get install gh -y` (missing `--no-install-recommends`) |
| P0-2 | `README.md:131-147` | Tools list omits fzf |
| P0-3 | `bin/devenv:221-222` | gh-copilot mount exists but undocumented |
| P1-1 | `docker/devenv/templates/Dockerfile.python-uv:1` | Missing `# syntax=docker/dockerfile:1` |
| P1-2 | `bin/devenv:227-229` | opencode auth.json mount undocumented |
| P1-3 | `CONTRIBUTING.md:115` | Says "line 46", actual is line 34 |
| P1-4 | `bin/devenv:171,263,288` | `docker ps ... \| grep -q .` masks failures |
| P2-1 | `bin/devenv:144-158`, `bin/build-devenv:85-99` | Duplicated function |
| P2-2 | `docker/devenv/templates/Dockerfile.python-uv:20-26` | Commented-out code |
| P2-3 | `README.md:114-128` | Architecture tree incomplete |
| P2-4 | `CHANGELOG.md:68` | Stale `devenv-tvim-lock` reference |

## Recommended Next Actions

1. [ ] **Fix P0-1**: Add `--no-install-recommends` to `docker/devenv/Dockerfile.devenv:118`
2. [ ] **Fix P0-2 + P2-3**: Add `fzf` to README tools list and architecture tree
3. [ ] **Fix P0-3 + P1-2**: Add `gh-copilot` and `opencode/auth.json` rows to README config mount table
4. [ ] **Fix P1-1**: Add `# syntax=docker/dockerfile:1` to both template Dockerfiles
5. [ ] **Fix P1-3**: Update CONTRIBUTING.md line reference from 46 → 34
6. [ ] **Fix P1-4**: Refactor pipe-to-grep patterns — capture docker output to a variable first, then grep
7. [ ] **Fix P2-1**: Extract shared functions into `shared/bash/utils.sh` and source from both scripts
8. [ ] **Fix P2-2**: Remove commented-out code from template Dockerfiles
9. [ ] **Run shellcheck**: `shellcheck --severity=style bin/devenv bin/build-devenv scripts/install-devenv shared/bash/log.sh` — could not be executed in this environment; should be run to confirm full compliance

## Notes

- **Shellcheck could not run** in the review environment (not installed / permission issue). Manual code review was performed but automated shellcheck validation is recommended before acting on P1-4.
- **Docker builds could not be tested** — no Docker daemon available. Build-level verification is deferred.
- **No CI/CD pipeline exists** — the project uses OpenCode agents instead. Consider adding a pre-commit hook or Makefile target for `shellcheck` to enforce the AGENTS.md zero-warnings policy automatically.

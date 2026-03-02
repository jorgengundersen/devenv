# Proposal: Testing Standard

## Goal
Define a highly visible testing standard that guides test design in this repo,
emphasizing black-box testing, the testing trophy model, and a strict
red-green-refactor loop (ONE test -> ONE implementation -> repeat).

## Motivation
- The project is CLI-first with clear primitive/command boundaries in
  `bin/devenv` and `bin/build-devenv`.
- Tests should be productive, stable, and resistant to harmless refactors.
- A dedicated testing standard will be more visible than a subsection in the
  coding standard.

## Current State (Quick Review)
- No test suite is currently present in the repo.
- There is a proposal for Bats in `plans/proposals/bats-test-setup.md` that
  targets fast, deterministic CLI tests with a fake Docker.
- Code structure already supports testable primitives and black-box CLI
  behavior.

## Principles Evaluation
### Black-box testing
Best fit for CLI behavior: assert exit codes, stdout/stderr, and observable
effects (fake docker call logs), not internal functions or implementation
details.

### Testing trophy model
Most value comes from small/fast tests: primitives, CLI contracts, and
integration tests with fake Docker. Real Docker end-to-end tests should be rare
and opt-in.

### Red-green-refactor (ONE test -> ONE implementation -> repeat)
Aligns with the repo's "no slop" rule and keeps change sets focused. For
bug-fixes: add a failing test first, then fix, then refactor.

## Proposal
Create a new, top-level testing standard file:

`specs/testing-standard.md`

This file should define:
- Testing strategy aligned to the testing trophy model.
- Black-box-first rules for CLI behavior and contracts.
- Red-green-refactor discipline with one-test/one-change cadence.
- Determinism requirements (no Docker/network by default).
- Guardrails to prevent brittle tests (avoid golden outputs with dynamic
  values, normalize outputs, assert minimal contracts).
- Expectations for primitives vs commands (primitives testable without docker
  or exit; commands may call `die()` and shell out).

## Plan
- [x] Draft proposal for dedicated testing standard file
- [ ] Create `specs/testing-standard.md` with the rules above
- [ ] Align future test harness work (Bats + fake Docker) with the standard

## Out of Scope
- Implementing the test suite
- Editing existing proposals
- Running CI changes

## Success Criteria
- A dedicated testing standard exists and is referenced in future test work.
- The standard keeps tests stable across harmless refactors.

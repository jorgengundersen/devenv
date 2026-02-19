---
description: Create an implementation plan from a research document
model: github-copilot/claude-opus-4.6
---

Create an implementation plan based on the research document provided as argument.

## Input

Research file: $ARGUMENTS

## Instructions

1. Read the research file (`$ARGUMENTS`) completely.
2. Read `AGENTS.md` for project-level agent guidelines.
3. Read `specs/coding-standard.md` if it exists (for standards compliance requirements).
4. Read every file listed in the research document's File-Level Change Map.
5. Convert the research into a precise, ordered implementation plan for a delegated coding agent.

## Output

Derive the output path from the research filename: strip the directory prefix and `.md` extension, then write to `plans/current/<name>/implementation_plan.md`.

Example: `plans/current/common-utils/research.md` -> `plans/current/common-utils/implementation_plan.md`

Create the directory if it does not exist.

The document must follow this structure and be concise:

### Required Sections

**Title and References**
- `# Implementation Plan: <Feature Name>`
- Link the source research file.
- List required specs or standards the implementer must read first.

**Execution Rules**
- Project-specific rules (from research/specs/AGENTS.md) that affect implementation order, logging, validation, or tooling.

**Task List (with Checkmarks)**
- Use checkboxes `- [ ]` and numbered tasks.
- Organize with phases or sections for larger and complex implementation plans
- Each task must include:
  - Title
  - Files to modify (use `path:line` format, matching `grep -n` style)
  - Description (1-3 sentences)
  - Before: exact current snippet or "new function/file" if adding
  - After: exact target snippet or precise pseudocode for non-trivial changes
  - Verification: task-specific check(s)
- Order tasks to minimize conflicts and allow incremental verification.
- If the research includes explicit wording or snippets, reuse them verbatim.

**Verification Plan**
- List end-to-end checks and any required linters/tests (e.g., `shellcheck`) from the research/specs.

**External References**
- Always include this section, even if empty (use `None` when not applicable).

**Completion Checklist**
- Bullet checklist summarizing the must-hit outcomes.

## Quality Criteria

- No ambiguity: a coding agent can execute without interpretation.
- Every change in the research must map to a task.
- Use `path:line` references that match `grep -n` output style.
- List external references (docs, specs, issues) when needed.
- Keep it short and actionable; avoid repeating the research verbatim.

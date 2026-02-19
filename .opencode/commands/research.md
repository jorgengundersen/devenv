---
description: Create a research document (gap analysis) from a spec
subtask: true
---

Create a research document based on the spec provided as argument.

## Input

Spec file: $ARGUMENTS

## Instructions

1. Read the spec file (`$ARGUMENTS`) completely.
2. Read `AGENTS.md` for project-level agent guidelines.
3. Read `specs/coding-standard.md` if it exists (for standards compliance checks).
4. Scan the current codebase to understand what exists today vs what the spec requires.
   - Read every file the spec references or affects.
   - Note line numbers, function names, and current behavior.

## Output

Derive the output path from the spec filename: strip the directory prefix and `.md` extension, then write to `plans/current/<name>/research.md`.

Example: `specs/multi-environment-architecture.md` → `plans/current/multi-environment-architecture/research.md`

Create the directory if it does not exist.

The document must follow this structure — scale depth to match the spec's complexity:

### Required Sections

**Title and Spec Reference**
- `# Research: <Feature Name> Gap Analysis`
- Cite the source spec path and list all files analyzed with line counts.

**Current State Snapshot**
- Brief summary of what exists in the codebase today that relates to this spec.

**Gap Analysis Matrix**
- Compare every spec requirement against the current implementation.
- Use a table with columns: Spec Requirement | Current State | Gap Type | Required Action.
- Categorize each gap as: `NO CHANGE`, `UPDATE`, `NEW`, or `REMOVE`.

**File-Level Change Map**
- For each file that needs changes, list:
  - Filename and current line count.
  - Sections/lines that change (with line numbers where possible).
  - Nature of change (UPDATE / NEW / REMOVE).
  - Dependencies on other file changes.
- Also list files that explicitly do NOT change, with a brief reason.

**Function/Block-Level Detail** (for non-trivial changes)
- For each function or code block that changes:
  - Current behavior (what it does now).
  - Target behavior (what the spec requires).
  - Specific lines affected.
  - New functions/blocks to add.
  - Functions/blocks to remove.

**Edge Cases and Tradeoffs**
- List scenarios the implementation must handle.
- Include race conditions, missing dependencies, invalid input, and error paths.
- State the recommended handling for each.

**External Dependencies**
- New runtime or build dependencies introduced.
- Availability and fallback strategies.

**Open Decisions** (if any)
- Questions that need resolution before implementation.
- Provide options with tradeoffs for each.

**Suggested Implementation Order**
- Ordered list of changes that minimizes conflicts and enables incremental verification.

## Quality Criteria

- Every section of the spec must map to either `NO CHANGE` or a specific code change — no gaps left unmapped.
- No ambiguity: an implementation agent reading this document should know exactly what to change, where, and why.
- Use line numbers and function names from the actual codebase, not approximations.
- Keep it concise — do not pad with boilerplate. Scale detail proportionally to complexity.

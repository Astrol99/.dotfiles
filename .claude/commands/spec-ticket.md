---
description: Spec out a ticket or create new ticket from description
argument-hint: <TICKET-ID | text description | pr NUMBER>
scope: global
---

# Spec Ticket

Fully spec out an existing ticket, or create a new ticket from a description.

**Arguments:** $ARGUMENTS (LLM interprets)

```
/spec-ticket ENG-123                   → Spec out existing ticket
/spec-ticket Fix the timeout bug...    → Create new ticket from description
/spec-ticket pr 456                    → Create ticket/spec from PR
```

---

## Instructions

### Step 1: Determine Mode

**Parse arguments to determine mode:**

| Input Pattern | Mode |
|---------------|------|
| `ENG-123`, `HAM-456` (ticket ID) | Existing Ticket |
| `pr 123`, `PR #123` | From PR |
| Free text (bug description, feature request) | New Ticket |

---

### Mode A: Existing Ticket (ENG-123)

**1. Fetch ticket from Linear:**

```
ticket = mcp__linear__get_issue({ id: "ENG-123" })
```

Extract:
- Title
- Description
- Acceptance criteria
- Labels (bug, feature, etc.)
- Priority
- Comments (for additional context)

**2. Explore codebase with WarpGrep:**

```
mcp__morph-mcp__warpgrep_codebase_search({
  search_string: "Find where to implement: ${TITLE} - ${DESCRIPTION}",
  repo_path: "${CWD}"
})
```

**3. Assess scope and complexity:**

Count:
- Files that need modification
- Logical layers touched (schema, API, UI, tests)
- Dependencies and risks

**4. Check if splitting is recommended:**

```
IF any of these are true:
  - >10 files would be modified
  - >3 logical layers touched
  - Estimated >2 days of work
  - Multiple independent features bundled
THEN:
  Suggest: "This ticket seems large. Consider `/split-task ENG-123` first."
```

**5. Generate engineering spec:**

See [Engineering Spec Template](#engineering-spec-template) below.

**6. Update Linear ticket with spec:**

```
mcp__linear__update_issue({
  id: "ENG-123",
  description: "${ORIGINAL_DESC}\n\n---\n\n## Engineering Spec\n${SPEC}"
})
```

Or create a comment:
```
mcp__linear__create_comment({
  issueId: "ENG-123",
  body: "## Engineering Spec\n${SPEC}"
})
```

**7. Output spec document.**

---

### Mode B: New Ticket (text description)

**1. Analyze description:**

Determine:
- **Type**: Bug Fix / Feature / Refactor / Chore
- **Title**: Concise summary (max 80 chars)
- **Description**: Full details from input
- **Team**: Detect from context or ask

**2. Explore codebase with WarpGrep:**

```
mcp__morph-mcp__warpgrep_codebase_search({
  search_string: "${USER_DESCRIPTION}",
  repo_path: "${CWD}"
})
```

**3. Assess scope:**

If scope is large:
```markdown
⚠️ **Large Scope Detected**

This idea touches:
- {N} files across {M} apps
- {L} logical layers (schema, API, UI, tests)

**Recommendation:** Split into smaller tickets first.

Run: `/split-task ${IDEA_DESCRIPTION}`

Or proceed with single ticket? [split/proceed]
```

**4. If proceeding, generate engineering spec:**

See [Engineering Spec Template](#engineering-spec-template) below.

**5. Create Linear ticket:**

```
mcp__linear__create_issue({
  title: "${TITLE}",
  team: "${TEAM}",
  description: "${DESCRIPTION}\n\n---\n\n## Engineering Spec\n${SPEC}",
  assignee: "me",
    state: "Todo",
  labels: ["${TYPE_LABEL}"]
})
```

**6. Output ticket link + spec.**

---

### Mode C: From PR (pr 456)

**1. Fetch PR details:**

```bash
PR_DATA=$(gh pr view 456 --json title,body,headRefName,files)
PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
PR_BODY=$(echo "$PR_DATA" | jq -r '.body')
PR_FILES=$(echo "$PR_DATA" | jq -r '.files[].path')
```

**2. Analyze PR for ticket context:**
- Extract ticket ID from branch/title if exists
- Understand what the PR implements
- Get file changes for scope

**3. If ticket exists, spec it:**

```
/spec-ticket ${TICKET_ID}
```

**4. If no ticket, create one:**

Generate ticket from PR context with engineering spec.

**5. Link ticket to PR:**

Add comment to PR with ticket link.

---

## Scope Assessment

**Triggers for split recommendation:**

| Indicator | Threshold | Action |
|-----------|-----------|--------|
| Files modified | >10 | Suggest split |
| Logical layers | >3 | Suggest split |
| Estimated time | >2 days | Suggest split |
| Apps touched | >2 | Suggest split |
| Independent features | >1 | Suggest split |

**Output when large scope detected:**

```markdown
## ⚠️ Scope Assessment

**This ticket appears large:**
- **Files:** ~15 files across 3 apps
- **Layers:** Schema, API, UI, Tests
- **Estimate:** ~4 days

**Recommendation:** Consider splitting first

```
/split-task ENG-123
```

This will break it into smaller, reviewable chunks.

---

**Proceed anyway?** The spec below covers the full scope.
```

---

## Engineering Spec Template

```markdown
# Engineering Spec: [TICKET-ID] Title

## Overview
Brief description of the change and why it's needed.

## Scope Assessment
- **Complexity:** Low / Medium / High
- **Estimated Time:** X days
- **Files:** ~N files
- **Layers:** Schema, API, UI, Tests
- **Split Recommended:** Yes/No

## Analysis
- **Type:** Bug Fix / Feature / Refactor
- **Affected Areas:**
  - `apps/evals-web/src/...`
  - `apps/evals-queue/src/...`

## Current State
{Description of current behavior/implementation}

## Proposed Changes

### Files to Modify
| File | Changes |
|------|---------|
| `path/to/file.ts` | Add X, modify Y |
| `path/to/other.ts` | Update Z |

### New Files
| File | Purpose |
|------|---------|
| `path/to/new.ts` | Description |

## Implementation Approach

### Step 1: {Description}
- Detail 1
- Detail 2

### Step 2: {Description}
- Detail 1
- Detail 2

### Step 3: {Description}
- Detail 1
- Detail 2

## Dependencies
- {Any blocked-by tickets}
- {External dependencies}

## Risks & Considerations
| Risk | Mitigation |
|------|------------|
| Risk 1 | How to mitigate |
| Risk 2 | How to mitigate |

## Testing Plan
- [ ] Unit tests for X
- [ ] Integration test for Y
- [ ] Manual verification of Z

## Acceptance Criteria
- [ ] Criteria 1
- [ ] Criteria 2
- [ ] Criteria 3

## Open Questions
- {Any unresolved questions}
```

---

## Output

```markdown
# ✅ Ticket Spec Complete

## Ticket
- **{TICKET_ID}** - {Title}
- **Type:** {Bug Fix / Feature / Refactor}
- **Scope:** {Low / Medium / High}
- **Link:** {Linear URL}

{If large scope:}
## ⚠️ Consider Splitting
This ticket is large. Run `/split-task {TICKET_ID}` to break it down.

## Engineering Spec

{Full spec content}

## Files Identified
| File | Purpose |
|------|---------|
| path/to/file.ts | Main implementation |
| path/to/test.ts | Unit tests |

## Next Steps
{If small scope:}
1. `/start-ticket {TICKET_ID}` to begin implementation

{If large scope:}
1. `/split-task {TICKET_ID}` to break down into subtasks
2. Then `/start-ticket` on each subtask
```

---

## Notes

- **Uses WarpGrep** to explore codebase before speccing
- **Assesses scope** and recommends splitting if large
- **Updates Linear** with spec (in description or comment)
- **Creates tickets** with full engineering context
- **Assigns to me** automatically
- **Detects type** from input (bug, feature, refactor)
- **Identifies files** that need modification
- **Integrates with `/split-task`** for large tickets
- Can work from: existing tickets, free text, or PRs

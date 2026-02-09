---
description: Create pull request with auto-assignment
argument-hint: [ready] [N/M subtitle] [from PR] [needs PR] [base BRANCH]
scope: global
---

# Create PR

Create PR from current branch with smart summary generation.

**Arguments:** $ARGUMENTS (LLM interprets)

```
/create-pr                        → Draft PR (default)
/create-pr ready                  → Ready for review
/create-pr 1/3 schema             → Part 1 of 3, subtitle "schema"
/create-pr from 456               → Split from PR #456
/create-pr needs 201              → Depends on PR #201
/create-pr base feat/ENG-123      → Custom base branch
/create-pr from 456 1/3 schema    → Split PR with part info
```

---

## Instructions

### Step 0: Pre-flight Check

**Ensure before running:**
- Code compiles (`/code-check` passed)
- Branch has commits not in main

**Note:** Run `/quality-check` separately before PR if needed.

---

### Step 1: Validate Branch

```bash
BRANCH=$(git branch --show-current)
BASE_BRANCH=${BASE:-main}  # Use base arg if provided, else main
```

**If main:** Error - switch to feature branch first

### Step 2: Get Changes & Extract Info

**Use GetWorkspaceDiff for actual changes:**
```
mcp__conductor__GetWorkspaceDiff({ stat: true })  // File summary
mcp__conductor__GetWorkspaceDiff()                 // Full diff for context
```

**Extract ticket ID:**
```bash
TICKET_ID=$(echo "$BRANCH" | grep -oE '[A-Z]+-[0-9]+')
```

### Step 3: Get Ticket Details from Linear

Use `mcp__linear__get_issue({ id: "ENG-123", includeRelations: true })` to get:
- Title for PR title
- Description for context
- URL for linking
- **Parent issue** (if this is a subtask)
- **Sibling subtasks** (to determine N/M position)

**Check for parent ticket:**
```
ticket = mcp__linear__get_issue({ id: "ENG-123", includeRelations: true })

if ticket.parent:
  # This is a subtask - get siblings to determine position
  parent = mcp__linear__get_issue({ id: ticket.parent.id })
  siblings = mcp__linear__list_issues({ parentId: ticket.parent.id })
  
  # Find position (sorted by creation date or priority)
  position = siblings.findIndex(s => s.id === ticket.id) + 1
  total = siblings.length
  
  PART_INFO = "${position}/${total}"
  PARENT_TITLE = parent.title
```

### Step 4: Auto-Generate PR Content

**Detect PR Type from branch:**
- `fix/` or `bugfix/` → Bug Fix
- `feat/` or `feature/` → Feat
- `refactor/` → Refactor
- `chore/` → Chore
- Other → Chore

**Build Title:**
```bash
# Base format: [Type] [TICKET] Brief description
TITLE="[$PR_TYPE] [$TICKET_ID] $DESCRIPTION"

# If subtask of parent ticket (auto-detected)
if [ -n "$PART_INFO" ]; then
  TITLE="[$PR_TYPE] [$TICKET_ID] $PARENT_TITLE $PART_INFO: $DESCRIPTION"
fi

# If part info provided explicitly (N/M subtitle) - overrides auto-detect
if [ -n "$EXPLICIT_PART" ]; then
  TITLE="[$PR_TYPE] [$TICKET_ID] $MAIN_TITLE $EXPLICIT_PART: $SUBTITLE"
fi

# If dependency provided (needs PR)
if [ -n "$DEPENDS_ON" ]; then
  TITLE="$TITLE (needs #$DEPENDS_ON)"
fi
```

**Title Examples:**
```
[Feat] [ENG-123] Add user authentication
[Bug Fix] [ENG-456] Fix timeout issue
[Feat] [ENG-123] Add user auth 1/3: Database schema
[Feat] [ENG-124] Chart explanations 1/5: Types and definitions
[Feat] [ENG-123] Add user auth 2/3: API endpoints (needs #201)
```

**Generate Summary from diff:**
Analyze the diff and list:
- What files changed (grouped by type: components, hooks, API, tests)
- What functionality was added/modified/removed
- Key implementation details

**Auto-detect Test Plan from changed files:**
| Changed Files | Test Plan |
|--------------|-----------|
| `components/` | Test UI renders, interactions work |
| `hooks/` | Test hook behavior, edge cases |
| `server/routers/` | Test API endpoints return expected data |
| `*.spec.ts` | Run test suite, verify coverage |
| `utils/` | Test utility functions |

### Step 5: Create PR

```bash
# Build PR body
BODY="## Summary
{Auto-generated from diff analysis}

## Changes
- file1.ts: Added X functionality
- file2.ts: Fixed Y issue

## Linear
{URL from mcp__linear__get_issue}"

# Add parent ticket info if subtask
if [ -n "$PARENT_TICKET" ]; then
  BODY="$BODY

## Parent Ticket
Part of [$PARENT_TICKET] $PARENT_TITLE

## Related PRs
{Table of sibling subtask PRs if they exist}"
fi

# Add split PR info if 'from PR' provided
if [ -n "$SPLIT_FROM" ]; then
  BODY="$BODY

## Split From
This PR was split from #$SPLIT_FROM

## Related PRs
{Table of all PRs from the split}"
fi

# Add dependency info if 'needs PR' provided
if [ -n "$DEPENDS_ON" ]; then
  BODY="$BODY

## Dependencies
⚠️ This PR depends on #$DEPENDS_ON - merge that first"
fi

BODY="$BODY

## Test Plan
{Auto-generated based on changed files}
- [ ] Verify X
- [ ] Check Y"

# Create PR (draft by default)
DRAFT_FLAG="--draft"
if [ "$READY" = "true" ]; then
  DRAFT_FLAG=""
fi

gh pr create \
  $DRAFT_FLAG \
  --assignee @me \
  --base "$BASE_BRANCH" \
  --title "$TITLE" \
  --body "$BODY"
```

### Step 6: Output

```markdown
# ✅ PR Created

**#123** - [Feat] [ENG-456] Add new feature
- Status: Draft
- Base: main
- Link: {url}
- Changes: {N} files

{If subtask:}
- Parent: [ENG-123] Parent ticket title
- Part: 1/5

{If split PR:}
- Split from: #456
- Dependencies: None (or: Needs #122)

## Summary
{Brief summary of changes}

Next: Request review when ready
```

---

## Subtask Detection

When the ticket has a parent in Linear:

1. **Auto-detect part position** from sibling subtasks
2. **Include parent title** in PR title
3. **Add parent ticket section** in PR body
4. **Show related sibling PRs** if they exist

**Example:**
```
Ticket: ENG-11897 (subtask of ENG-11895)
Parent: ENG-11895 "Chart Explanations Feature"
Siblings: ENG-11897, ENG-11898, ENG-11899, ENG-11900, ENG-11901 (5 total)
Position: 1/5

PR Title: [Feat] [ENG-11897] Chart explanations 1/5: Types and definitions
```

---

## Split PR Mode

When called with `from PR`:

1. **Add split reference** - Links to original PR
2. **Include related PRs table** - Shows all parts of the split
3. **Add merge order note** - If stacked

Example for independent split:
```markdown
## Split From
This PR was split from #456

## Related PRs (from split)
| PR | Title | Base | Status |
|----|-------|------|--------|
| #201 | [Feat] [ENG-123] Add auth 1/3: Schema | main | This PR |
| #202 | [Feat] [ENG-123] Add auth 2/3: API | main | Draft |
| #203 | [Feat] [ENG-123] Add auth 3/3: UI | main | Draft |
```

Example for stacked split:
```markdown
## Dependencies
⚠️ This PR depends on #201 - merge that first

## Merge Order
#201 → This PR (#202) → #203
```

---

## Notes

- Always draft by default (`ready` for ready-for-review)
- Auto-assigns to @me
- Uses Linear MCP for ticket link
- Uses GetWorkspaceDiff for accurate change summary
- Smart test plan based on file types changed
- **Title format**: `[Type] [TICKET] Title` or `[Type] [TICKET] Parent N/M: Title`
- **Auto-detects subtasks** and adds part info from Linear parent
- **Supports stacked PRs** with `base BRANCH` and `needs PR`
- **Supports split PRs** with `from PR` and part info
- **No inline quality check** - run `/quality-check` separately if needed

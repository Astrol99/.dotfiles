---
description: Start work on tickets with parallel agents
argument-hint: <TICKET-IDs or keywords>
scope: global
---

# Start Ticket

View ticket summary or implement tickets (parallel for multiple).

**Arguments:** $ARGUMENTS

**Formats:**
- No args → Show ticket summary
- Single: `ENG-123` → Plan and implement in current workspace
- Multiple: `ENG-123 ENG-124 ENG-125` → Parallel agents via worktrees
- Keywords: `todo`, `not-started`

---

## Instructions

### No Arguments → Show Summary

Use `mcp__linear__list_issues({ assignee: "me", state: "started" })` to fetch tickets.

```markdown
## 📋 Your Tickets

### 🎯 Todo ({N})
| Ticket | Title | Priority |
| ENG-123 | Fix timeout | 🔴 High |

### 🔨 In Progress ({N})
| Ticket | Title | PR | Branch |
| ENG-126 | Refactor | #92 | feat/ENG-126 |

### 👀 In Review ({N})
| Ticket | Title | PR | Feedback |
| ENG-127 | Config | #89 | 3 new |

---
**Suggested:** /start-ticket {highest_priority}
```

---

### Single Ticket → Implement Here

**1. Check for existing work:**
```bash
gh pr list --json headRefName,number -q '.[] | select(.headRefName | contains("TICKET_ID"))'
```

**2. Fetch from Linear:**
Use `mcp__linear__get_issue({ id: "ENG-123", includeRelations: true })` for:
- Title, description, acceptance criteria
- Priority, labels, assignee
- Related issues and blockers
- **Parent issue** (if subtask)

**3. Explore codebase with WarpGrep:**
```
mcp__morph-mcp__warpgrep_codebase_search({
  search_string: "Find where to implement {TITLE} - {DESCRIPTION}",
  repo_path: "${CWD}"
})
```

**4. Create implementation plan:**
```markdown
## 📋 Plan for {TICKET_ID}

**Title:** {Title}
**Complexity:** Low/Medium/High
**Relevant Files:** {from WarpGrep}
{If subtask:}
**Parent:** {PARENT_TICKET_ID} - {Parent Title}
**Part:** {N}/{M}

### Tasks
- [ ] Type stubs and interfaces
- [ ] Core feature logic
- [ ] Test scaffolding
- [ ] Integration tests

Proceed? [Y/n]
```

**5. Implement** (use `mcp__morph-mcp__edit_file` for all edits)

**6. Verify with /code-check:**
```
/code-check
```

**7. Self-Review:**
```
/loop-review --iterations=4
```

**8. Commit & PR:** `/create-pr`

---

### Multiple Tickets → Parallel Agents

**Phase 1: Pre-fetch ALL ticket data (Main Agent)**

```
# Batch fetch from Linear BEFORE launching agents
# Include relations to detect parent/sibling structure
tickets = mcp__linear__list_issues({
  assignee: "me",
  query: "ENG-123 OR ENG-124 OR ENG-125"
})

# Or individual fetches (parallel) with relations
for each TICKET_ID:
  ticket_data[TICKET_ID] = mcp__linear__get_issue({ 
    id: TICKET_ID, 
    includeRelations: true 
  })
  
  # If subtask, get parent and siblings for part info
  if ticket_data[TICKET_ID].parent:
    parent_id = ticket_data[TICKET_ID].parent.id
    siblings = mcp__linear__list_issues({ parentId: parent_id })
    ticket_data[TICKET_ID].partInfo = {
      position: siblings.findIndex(s => s.id === TICKET_ID) + 1,
      total: siblings.length,
      parentTitle: ticket_data[TICKET_ID].parent.title
    }
```

**Phase 2: Sequential Worktree Setup**

Run `/setup-worktree` for each ticket sequentially (slash commands cannot be backgrounded):

```
/setup-worktree ENG-123
# Wait for completion, get path
WORKTREE_123 = ".worktrees/ENG-123"

/setup-worktree ENG-124
WORKTREE_124 = ".worktrees/ENG-124"

/setup-worktree ENG-125
WORKTREE_125 = ".worktrees/ENG-125"
```

**Phase 3: Parallel Implement (Background Agents)**

Launch one agent per ticket in a single message:

```
# All Task() calls in ONE message for parallel execution

Task({
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: `Implement ticket ${TICKET_ID}.

## Context
Worktree: ${CWD}/.worktrees/${TICKET_ID}/
Branch: feat/${TICKET_ID}
Title: ${TITLE}
Description: ${DESCRIPTION}
Acceptance Criteria: ${CRITERIA}
${PART_INFO ? `Parent: ${PARENT_TITLE}\nPart: ${PART_INFO.position}/${PART_INFO.total}` : ''}

## Instructions

1. Explore first:
   mcp__morph-mcp__warpgrep_codebase_search({ search_string: "${TITLE}", repo_path: "${CWD}/.worktrees/${TICKET_ID}" })

2. Implement using mcp__morph-mcp__edit_file for all edits

3. Verify with /code-check:
   (cd to worktree first, then run /code-check)

4. Commit and push:
   cd ${CWD}/.worktrees/${TICKET_ID} && git add . && git commit -m "[${TICKET_ID}] ${TITLE}"
   cd ${CWD}/.worktrees/${TICKET_ID} && git push -u origin feat/${TICKET_ID}

5. Detect PR type from branch/title:
   - fix/, bugfix/ in branch or "fix" in title → Bug Fix
   - feat/, feature/ in branch or "add", "implement" in title → Feat
   - refactor/ in branch → Refactor
   - Otherwise → Feat

6. Build PR title:
   - If subtask (PART_INFO exists):
     TITLE = "[${PR_TYPE}] [${TICKET_ID}] ${PARENT_TITLE} ${PART_INFO.position}/${PART_INFO.total}: ${TITLE}"
   - Otherwise:
     TITLE = "[${PR_TYPE}] [${TICKET_ID}] ${TITLE}"

7. Create draft PR with correct title format:
   cd ${CWD}/.worktrees/${TICKET_ID} && gh pr create --draft --assignee @me \
     --title "${PR_TITLE}" \
     --body "## Summary
Implements ${TICKET_ID}
${PART_INFO ? '\n## Parent Ticket\nPart of [' + PARENT_ID + '] ' + PARENT_TITLE : ''}

## Linear
{TICKET_URL}

## Test Plan
- [ ] Verify implementation works as expected"

8. Report: files changed, PR link, issues encountered`
})

# Launch all agents in a SINGLE message (parallel)
Task({ ... for ENG-123 })
Task({ ... for ENG-124 })
Task({ ... for ENG-125 })
```

**Phase 4: Wait for All Agents**

```
TaskOutput({ task_id: "agent-1-id", block: true })
TaskOutput({ task_id: "agent-2-id", block: true })
TaskOutput({ task_id: "agent-3-id", block: true })
```

**Phase 5: Sequential Self-Review (Optional)**

```
for each TICKET_ID:
  /loop-review --path=.worktrees/${TICKET_ID} --iterations=4
```

**Phase 6: Cleanup**

```bash
for each TICKET_ID:
  git worktree remove .worktrees/${TICKET_ID} --force
```

**Output:**
```markdown
# ✅ Tickets Implemented

| Ticket | Title | PR | Part | Status |
|--------|-------|-----|------|--------|
| ENG-123 | Types & definitions | #95 | 1/5 | ✅ Draft PR |
| ENG-124 | Service layer | #96 | 2/5 | ✅ Draft PR |
| ENG-125 | API endpoints | #97 | 3/5 | ✅ Draft PR |

## Parent Ticket
[ENG-122] Chart Explanations Feature

## Self-Review Summary (if run)
- ENG-123: Clean on iteration 1
- ENG-124: 2 issues fixed
- ENG-125: Clean on iteration 1

## Next Steps
- Review draft PRs
- Run `/code-check` in each branch if needed
```

---

## Parallel Execution Strategy

```
/start-ticket ENG-123 ENG-124 ENG-125

Phase 1: Pre-fetch (Main Agent - Parallel API calls)
└─→ Linear API calls via list_issues or parallel get_issue
└─→ Detect parent/sibling relationships for part info

Phase 2: Setup Worktrees (Sequential - slash commands can't background)
├─→ /setup-worktree ENG-123
├─→ /setup-worktree ENG-124
└─→ /setup-worktree ENG-125

Phase 3: Implement (Parallel Agents)
├─→ Agent 1: ENG-123  ─┐
├─→ Agent 2: ENG-124  ─┼─→ Background agents (isolated worktrees)
└─→ Agent 3: ENG-125  ─┘

Phase 4: Wait (Main Agent)
└─→ TaskOutput for each agent

Phase 5: Self-Review (Sequential)
├─→ /loop-review ENG-123
├─→ /loop-review ENG-124
└─→ /loop-review ENG-125

Phase 6: Cleanup (Sequential)
└─→ Remove worktrees
```

---

## PR Title Format

**Always use:** `[Type] [TICKET_ID] Title`

**For subtasks:** `[Type] [TICKET_ID] Parent Title N/M: Subtask Title`

**Type Detection:**
| Branch/Title Pattern | Type |
|---------------------|------|
| `fix/`, `bugfix/`, contains "fix" | Bug Fix |
| `feat/`, `feature/`, contains "add", "implement" | Feat |
| `refactor/` | Refactor |
| `chore/` | Chore |
| Other | Feat |

**Examples:**
```
[Feat] [ENG-123] Add user authentication
[Bug Fix] [ENG-456] Fix timeout issue
[Refactor] [ENG-789] Refactor auth module
[Feat] [ENG-124] Chart explanations 1/5: Types and definitions
[Feat] [ENG-125] Chart explanations 2/5: Service layer
```

---

## Notes

- Uses `/setup-worktree` for smart worktree creation
- Uses `/loop-review` for self-review after implementation
- **Uses `/code-check`** for verification (not inline commands)
- **Uses `/create-pr`** for single ticket mode (correct title format)
- **PR title format**: `[Type] [TICKET_ID] Title` (matches `/create-pr`)
- **Auto-detects subtasks** and includes part info (N/M) from Linear parent
- **Main agent pre-fetches** all Linear data including relations before spawning agents
- **Agents use WarpGrep** to explore codebase before implementing
- **Agents use edit_file** for faster edits (10x faster than Edit)
- **Worktree setup is sequential** (slash commands cannot be backgrounded)
- **Parallel agents** work in isolated worktrees
- **Sequential review** (Codex may have rate limits)
- Single ticket = implement in current workspace
- Multiple tickets = parallel agents via `.worktrees/`
- Claude Opus handles all code implementation
- Codex for review only (via `/loop-review`)
- **Testing**: When modifying `*.service.ts` or `*.utils.ts` files, read `.cursor/rules/unit-testing-best-practices.mdc` and consider adding tests

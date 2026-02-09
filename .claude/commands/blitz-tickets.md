---
description: High-volume parallel planning → sequential execution, own branch per ticket, no worktrees
argument-hint: <TICKET-IDs or keywords>
scope: global
---

# Blitz Tickets

High-throughput ticket workflow: parallel planning agents race, execute as each finishes, each on its own branch with a PR. No worktrees — just branch switching. Inspired by Duc's 500-PR-week workflow.

**Arguments:** $ARGUMENTS

**Formats:**
- `ENG-123 ENG-124 ENG-125 ENG-126 ENG-127` → Blitz 5 tickets
- `todo` or `not-started` → Blitz all your unstarted tickets
- `ENG-123 ENG-124 --dry-run` → Plan only, don't execute

---

## Key Differences from `/start-ticket`

| | `/start-ticket` (multiple) | `/blitz-tickets` |
|---|---|---|
| **Isolation** | Worktrees (separate directories) | Branch switching (single directory) |
| **Execution** | Parallel execution | Parallel planning → sequential execution |
| **Overhead** | `npm ci` per worktree, disk space | Zero — just `git checkout` |
| **PRs** | One PR per ticket | One PR per ticket |
| **Speed** | Slower setup, faster execution | Faster setup, sequential execution |
| **Planning** | Plans inline during execution | Plans upfront in parallel (race model) |

---

## Instructions

### Parse Arguments

```
INPUT = "$ARGUMENTS"

if INPUT contains "todo" or "not-started":
  tickets = mcp__linear__list_issues({ assignee: "me", state: "todo" })
  TICKET_IDS = tickets.map(t => t.identifier)
elif INPUT contains "in-progress" or "started":
  tickets = mcp__linear__list_issues({ assignee: "me", state: "started" })
  TICKET_IDS = tickets.map(t => t.identifier)
else:
  TICKET_IDS = parse ticket IDs from INPUT (e.g., ENG-123 ENG-124 ...)

DRY_RUN = INPUT contains "--dry-run"
```

### Phase 1: Pre-fetch ALL Ticket Data (Main Agent)

```
# Record the starting branch to return to after each ticket
STARTING_BRANCH = git rev-parse --abbrev-ref HEAD
BASE_REF = origin/main  # or origin/master — detect which exists

# Fetch latest
git fetch origin

# Batch fetch from Linear BEFORE launching agents
# Include relations to detect parent/sibling structure
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

Show summary table before proceeding:

```markdown
## Blitz Plan

| # | Ticket | Title | Priority |
|---|--------|-------|----------|
| 1 | ENG-123 | Fix timeout | High |
| 2 | ENG-124 | Add validation | Medium |
...

**Base:** main
**Mode:** Branch per ticket, no worktrees
**Tickets:** {N}

Proceed? [Y/n]
```

### Phase 2: Parallel Planning (Background Agents)

Launch ALL planning agents simultaneously in a single message. Each agent ONLY plans — does NOT implement.

```
# Launch ALL in a SINGLE message for parallel execution
# Limit to 5 concurrent agents max

for each TICKET_ID in TICKET_IDS (max 5 at a time):
  Task({
    subagent_type: "general-purpose",
    run_in_background: true,
    prompt: `PLANNING ONLY - Do NOT implement or edit any files.

## Ticket
ID: ${TICKET_ID}
Title: ${TITLE}
Description: ${DESCRIPTION}
Acceptance Criteria: ${CRITERIA}
${PART_INFO ? 'Parent: ' + PARENT_TITLE + '\nPart: ' + PART_INFO.position + '/' + PART_INFO.total : ''}

## Instructions

1. Explore codebase:
   mcp__morph-mcp__warpgrep_codebase_search({
     search_string: "Find where to implement ${TITLE} - ${DESCRIPTION}",
     repo_path: "${CWD}"
   })

2. Read relevant files to understand current code structure

3. Output a PLAN in this exact format:

---PLAN-START---
TICKET: ${TICKET_ID}
TITLE: ${TITLE}
COMPLEXITY: Low|Medium|High
FILES_TO_MODIFY:
- path/to/file1.ts (description of change)
- path/to/file2.ts (description of change)
FILES_TO_CREATE:
- path/to/new-file.ts (purpose)
STEPS:
1. Step one description
2. Step two description
3. ...
ESTIMATED_LINES: N
DEPENDENCIES: (other tickets that should go first, if any)
RISKS: (potential conflicts with other tickets in this batch)
---PLAN-END---

IMPORTANT: Output ONLY the plan. Do NOT make any edits.`
  })
```

### Phase 3: Execute as Plans Finish (Race Model)

Poll for completed plans and execute them as they arrive. Do NOT wait for all plans.

```
completed = []
executing = false
plans = {}
results = {}

# Check agents periodically
while len(completed) < len(TICKET_IDS):

  for each agent_id not yet completed:
    result = TaskOutput({ task_id: agent_id, block: false, timeout: 5000 })

    if result.status == "completed":
      plan = parse_plan(result.output)
      plans[plan.TICKET] = plan

      # If not currently executing another ticket, start this one
      if not executing and not DRY_RUN:
        executing = true
        results[plan.TICKET] = execute_plan(plan)  # See Phase 3a below
        executing = false
        completed.append(plan.TICKET)

  # Brief wait before polling again
  wait 3 seconds

# Execute any remaining plans that arrived while we were busy
for plan in plans where plan.TICKET not in completed:
  results[plan.TICKET] = execute_plan(plan)
  completed.append(plan.TICKET)
```

### Phase 3a: Execute a Single Plan

Each ticket gets its own branch. Stash any uncommitted work, branch from main, implement, commit, push, create PR, then return.

```
execute_plan(plan):
  TICKET_ID = plan.TICKET
  BRANCH_NAME = "feat/${TICKET_ID}"

  # 1. Ensure clean working directory
  git stash --include-untracked -m "blitz-stash before ${TICKET_ID}"

  # 2. Create a fresh branch from latest main
  git checkout -b "${BRANCH_NAME}" "${BASE_REF}"

  # 3. Report what we're about to do
  print("## Executing ${TICKET_ID}: ${plan.TITLE}")
  print("Branch: ${BRANCH_NAME}")
  print("Files: ${plan.FILES_TO_MODIFY}")

  # 4. Implement using edit_file
  # Follow the STEPS from the plan
  # Use mcp__morph-mcp__edit_file for all edits

  # 5. Stage all changes on this branch (safe — branch is isolated)
  git add -A

  # 6. Commit with ticket reference
  git commit -m "[${TICKET_ID}] ${plan.TITLE}"

  # 7. Quick verification (no full test suite — CI handles that)
  npx tsc --noEmit --pretty 2>&1 | head -20

  # 8. Push branch
  git push -u origin "${BRANCH_NAME}"

  # 9. Create draft PR
  #    Detect PR type from branch/title:
  #    - fix/, bugfix/ or "fix" in title → Bug Fix
  #    - feat/, feature/ or "add", "implement" in title → Feat
  #    - refactor/ → Refactor
  #    - Otherwise → Feat
  #
  #    Build PR title:
  #    - If subtask: "[Type] [TICKET_ID] Parent Title N/M: Title"
  #    - Otherwise:  "[Type] [TICKET_ID] Title"

  gh pr create --draft --assignee @me \
    --title "${PR_TITLE}" \
    --body "## Summary
  Implements ${TICKET_ID}: ${plan.TITLE}

  ${PART_INFO ? '## Parent Ticket\nPart of ' + PARENT_ID + ' ' + PARENT_TITLE : ''}

  ## Changes
  ${plan.FILES_TO_MODIFY.map(f => '- ' + f).join('\n')}
  ${plan.FILES_TO_CREATE.map(f => '- ' + f + ' (new)').join('\n')}

  ## Test Plan
  - [ ] CI passes
  - [ ] Verify implementation

  ## Linear
  ${TICKET_URL}"

  PR_URL = capture PR URL from gh output

  # 10. Return to starting branch
  git checkout "${STARTING_BRANCH}"

  # 11. Pop stash if we stashed earlier
  git stash pop 2>/dev/null || true  # may be empty

  return { ticket: TICKET_ID, branch: BRANCH_NAME, pr: PR_URL, commit: COMMIT_SHA }
```

### Phase 4: Summary

After all tickets are executed (or after planning if --dry-run):

```markdown
## Blitz Complete

**Tickets:** {N} planned, {M} executed
**PRs Created:** {M}

| # | Ticket | Title | Branch | PR | Status |
|---|--------|-------|--------|-----|--------|
| 1 | ENG-123 | Fix timeout | feat/ENG-123 | #101 | Draft PR |
| 2 | ENG-124 | Add validation | feat/ENG-124 | #102 | Draft PR |
| 3 | ENG-125 | Refactor auth | feat/ENG-125 | #103 | Draft PR |

{If DRY_RUN:}
### Plans Only (--dry-run)
{Show each plan with files and steps}

### Conflict Analysis
{Any files that appear in multiple ticket plans — FYI only, branches are isolated}

### Next Steps
- CI running on all {M} PRs
- Review PRs: `gh pr list --author @me`
- Mark ready: `gh pr ready {PR_NUM}` when CI passes
- Bulk ready: `gh pr list --draft --json number -q '.[].number' | xargs -I{} gh pr ready {}`
```

---

## Conflict Detection

Before executing, scan all plans for overlapping files. Since each ticket is on its own branch this is informational only (no actual git conflicts), but helps you know which PRs may conflict at merge time:

```
# Build file → ticket mapping
file_map = {}
for plan in plans:
  for file in plan.FILES_TO_MODIFY + plan.FILES_TO_CREATE:
    if file in file_map:
      file_map[file].append(plan.TICKET)
    else:
      file_map[file] = [plan.TICKET]

# Find overlaps
overlaps = {f: tickets for f, tickets in file_map.items() if len(tickets) > 1}

if overlaps:
  print("## Merge Conflict Risk")
  print("These files are modified by multiple tickets (will conflict at merge):")
  for file, tickets in overlaps:
    print(f"- {file}: {', '.join(tickets)}")
  print("")
  print("Recommendation: Merge these PRs sequentially, resolve conflicts on second PR.")
```

---

## Batch Size Management

If more than 5 tickets, process in waves:

```
WAVE_SIZE = 5

for wave_start in range(0, len(TICKET_IDS), WAVE_SIZE):
  wave = TICKET_IDS[wave_start:wave_start + WAVE_SIZE]
  print(f"## Wave {wave_start // WAVE_SIZE + 1}: {wave}")

  # Run Phase 2-3 for this wave
  parallel_plan(wave)
  sequential_execute(wave)
```

---

## Usage Examples

```bash
# Blitz 5 tickets — each gets its own branch + draft PR
/blitz-tickets ENG-123 ENG-124 ENG-125 ENG-126 ENG-127

# Blitz all your unstarted tickets
/blitz-tickets todo

# Plan only (see what would happen)
/blitz-tickets ENG-123 ENG-124 --dry-run

# Blitz in-progress tickets
/blitz-tickets started
```

---

## Execution Strategy

```
/blitz-tickets ENG-1 ENG-2 ENG-3 ENG-4 ENG-5

Phase 1: Pre-fetch (Main Agent)
└─→ Linear API calls for all tickets + git fetch origin

Phase 2: Parallel Planning (Background Agents - RACE)
├─→ Agent 1: ENG-1 plan  ─┐
├─→ Agent 2: ENG-2 plan  ─┼─→ Racing! First to finish gets executed first
├─→ Agent 3: ENG-3 plan  ─┤
├─→ Agent 4: ENG-4 plan  ─┤
└─→ Agent 5: ENG-5 plan  ─┘

Phase 3: Execute as Plans Arrive (branch per ticket)
├─→ ENG-3 finishes first → checkout -b feat/ENG-3 → implement → commit → push → PR #101
├─→ ENG-1 finishes next  → checkout -b feat/ENG-1 → implement → commit → push → PR #102
├─→ ENG-5 finishes       → checkout -b feat/ENG-5 → implement → commit → push → PR #103
├─→ ENG-2 finishes       → checkout -b feat/ENG-2 → implement → commit → push → PR #104
└─→ ENG-4 finishes last  → checkout -b feat/ENG-4 → implement → commit → push → PR #105

Phase 4: Summary
└─→ 5 branches, 5 draft PRs, CI running on all
```

---

## Safety Notes

- **Branch isolation** — each ticket on its own branch, no cross-contamination
- **Stash/restore** — working directory stashed before each branch switch, restored after
- **CI/CD handles verification** — only quick `tsc --noEmit` locally, full suite in CI
- **Push after each ticket** — CI starts immediately, parallelizes with next implementation
- **Wave processing** — max 5 planning agents at a time to avoid rate limits
- **If implementation fails** — delete the branch, skip that ticket, continue with others
- **Conflict detection** — warns about files touched by multiple tickets (merge-time conflicts)
- **No worktrees** — zero disk overhead, just branch switching
- **Returns to starting branch** — always comes back to where you were

---

## Notes

- Branch per ticket, no worktrees (zero overhead)
- Parallel planning → sequential execution (avoids write conflicts)
- Race model: execute whichever plan finishes first
- Each ticket gets a draft PR automatically
- CI/CD handles type checking and linting (not local)
- Conflict detection warns about potential merge conflicts across PRs
- Wave processing for large batches (>5 tickets)
- `--dry-run` mode for safe exploration
- PR title format matches `/create-pr`: `[Type] [TICKET_ID] Title`
- Subtask detection from Linear parent → adds N/M part info

---
description: Automatically review and fix all PRs with feedback until ready
argument-hint: [keyword]
scope: global
---

# Start PR Review

Auto-fix all PRs with feedback using parallel agents.

**Arguments:** $ARGUMENTS (optional)

- No args / `all` → Fix all PRs with feedback
- `high` → Only high priority
- `PR_NUM` → Fix specific PR

---

## Instructions

### Phase 1: Get PRs with Feedback

```bash
# Get repo info
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')

# Get open non-draft PRs authored by me
gh pr list --author @me --state open --draft=false --json number,title,headRefName
```

**For each PR, run `/review-pr-comments` to get categorized feedback:**

```
/review-pr-comments 89
/review-pr-comments 91
/review-pr-comments 95
```

Filter to PRs with actionable feedback (High/Medium priority items).

---

### Phase 2: Sequential Worktree Setup

Run `/setup-worktree` for each PR sequentially:

```
/setup-worktree 89
/setup-worktree 91
/setup-worktree 95
```

---

### Phase 3: Parallel Fix Agents

Launch one agent per PR in a **single message**:

```
# All Task() calls in ONE message for parallel execution

Task({
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: `Fix PR #${PR_NUM} comments.

## Context
Worktree: ${CWD}/.worktrees/pr-${PR_NUM}/
Branch: ${PR_BRANCH}
PR URL: https://github.com/${REPO}/pull/${PR_NUM}

## Comments from /review-pr-comments
${REVIEW_COMMENTS_OUTPUT}

## Instructions

1. cd to worktree:
   cd ${CWD}/.worktrees/pr-${PR_NUM}/

2. Run /fix-pr-comments all
   This will:
   - Fix each comment using edit_file
   - Run /code-check --quick
   - Commit and push
   - Resolve threads (FIX/SKIP/REPLY → resolve, DEFER → leave open)

3. Report: which items fixed, any that couldn't be fixed`
})

# Launch all in parallel
Task({ ... for PR #89 })
Task({ ... for PR #91 })
Task({ ... for PR #95 })
```

---

### Phase 4: Wait for Agents

```
TaskOutput({ task_id: "agent-1-id", block: true })
TaskOutput({ task_id: "agent-2-id", block: true })
TaskOutput({ task_id: "agent-3-id", block: true })
```

---

### Phase 5: Final Verification

**Helper function for fresh thread queries:**

```bash
OWNER=${REPO%%/*}
REPO_NAME=${REPO##*/}

fetch_unresolved_threads() {
  local PR_NUM=$1
  ALL_THREADS="[]"
  CURSOR=""

  while true; do
    if [ -z "$CURSOR" ]; then
      RESULT=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -F prNumber=$PR_NUM -f query='query($owner: String!, $repo: String!, $prNumber: Int!) { repository(owner: $owner, name: $repo) { pullRequest(number: $prNumber) { reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { id isResolved path line comments(first: 1) { nodes { body } } } } } } }')
    else
      RESULT=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -F prNumber=$PR_NUM -f cursor="$CURSOR" -f query='query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String!) { repository(owner: $owner, name: $repo) { pullRequest(number: $prNumber) { reviewThreads(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { id isResolved path line comments(first: 1) { nodes { body } } } } } } }')
    fi

    PAGE_THREADS=$(echo "$RESULT" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)]')
    ALL_THREADS=$(echo "$ALL_THREADS $PAGE_THREADS" | jq -s 'add')

    HAS_NEXT=$(echo "$RESULT" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
    if [ "$HAS_NEXT" != "true" ]; then break; fi
    CURSOR=$(echo "$RESULT" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
  done

  echo "$ALL_THREADS"
}
```

**Verify all threads resolved:**

```bash
for PR_NUM in ${PR_NUMBERS[@]}; do
  FINAL_UNRESOLVED=$(fetch_unresolved_threads $PR_NUM)
  FINAL_COUNT=$(echo "$FINAL_UNRESOLVED" | jq 'length')
  
  if [ "$FINAL_COUNT" -gt 0 ]; then
    echo "⚠️ PR #$PR_NUM: $FINAL_COUNT unresolved threads remain:"
    echo "$FINAL_UNRESOLVED" | jq -r '.[] | "  - \(.path):\(.line)"'
  else
    echo "✅ PR #$PR_NUM: All threads resolved"
  fi
done
```

---

### Phase 6: Optional Self-Review

For each PR, optionally run review loop:

```
for PR_NUM in ${PR_NUMBERS[@]}; do
  /loop-review --path=.worktrees/pr-${PR_NUM} --iterations=4
done
```

---

### Phase 7: Cleanup & Report

```bash
for PR_NUM in ${PR_NUMBERS[@]}; do
  git worktree remove .worktrees/pr-$PR_NUM --force
done
```

**Output:**
```markdown
# ✅ PR Review Complete

## Fixed PRs

| PR | Branch | Comments | Resolved | Status |
|----|--------|----------|----------|--------|
| #89 | feat/ENG-123 | 3 | 3 ✅ | ✅ Pushed |
| #91 | fix/ENG-456 | 1 | 1 ✅ | ✅ Pushed |
| #95 | feat/ENG-789 | 2 | 2 ✅ | ✅ Pushed |

## Final Verification
- All PRs verified with fresh query
- Any remaining: listed above

## Self-Review (if run)
- PR #89: Clean on iteration 1
- PR #91: 1 issue fixed
- PR #95: Clean on iteration 1

## Next Steps
- PRs updated and pushed
- Comments resolved
- Waiting for CI / re-review
```

---

### Single PR Mode

If only one PR specified:
1. If already on correct branch → fix in current workspace (no worktree)
2. Run `/review-pr-comments {PR_NUM}` to get categorized comments
3. Run `/fix-pr-comments all` to fix them
4. Done

---

## Command Composition

```
/start-pr-review
│
├─→ Phase 1: /review-pr-comments (for each PR)
│   └─→ Returns categorized comments with FIX/REPLY/SKIP/DEFER recommendations
│
├─→ Phase 2: /setup-worktree (for each PR)
│   └─→ Creates isolated worktrees
│
├─→ Phase 3: Parallel Agents
│   └─→ Each agent calls /fix-pr-comments all
│       └─→ /fix-pr-comments: edit_file → /code-check --quick → commit → resolve threads
│
├─→ Phase 4: Wait for agents
│
├─→ Phase 5: Final verification (fresh query)
│
├─→ Phase 6: /loop-review (optional)
│
└─→ Phase 7: Cleanup
```

---

## Notes

- **Uses `/review-pr-comments`** to get categorized feedback before fixing
- **Agents call `/fix-pr-comments`** which handles: edits, /code-check, commit, resolve
- Uses `/setup-worktree` for smart worktree creation
- Uses `/loop-review` for optional self-review
- **Fresh queries**: Always starts pagination from scratch (no cached cursors)
- **Merge base compare**: Compares against merge base to catch all PR changes
- **Pagination support**: Fetches ALL threads/comments (not just first 100)
- Thread resolution uses GitHub GraphQL API (batch comments aren't resolvable)
- **Resolution logic**: FIX/SKIP/REPLY → resolve, DEFER → leave open with ticket

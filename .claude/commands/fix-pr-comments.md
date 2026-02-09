---
description: Address specific PR comments with fixes
argument-hint: <comment-numbers or keywords>
scope: global
---

# Fix PR Comments

Implement fixes for PR feedback.

**Arguments:** $ARGUMENTS (flexible)

**Formats:**
- Numbers: `1 3 7` - Fix specific comments
- Keywords: `all`, `high`, `medium`, `low`
- Contextual: `above 2`, `the first one`, `john's comment`

---

## Instructions

### Step 1: Get PR & Repo Info

```bash
PR_NUM=$(gh pr list --head "$(git branch --show-current)" --json number -q '.[0].number')
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER=${REPO%%/*}
REPO_NAME=${REPO##*/}

echo "PR: $PR_NUM, Repo: $REPO"
```

### Step 2: Fetch Comments (if not already reviewed)

**If `/review-pr-comments` was just run, use that data. Otherwise fetch fresh:**

```bash
# Helper: Fetch unresolved threads (paginated)
fetch_unresolved_threads() {
  ALL_THREADS="[]"
  CURSOR=""
  while true; do
    if [ -z "$CURSOR" ]; then
      RESULT=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -F prNumber=$PR_NUM -f query='query($owner: String!, $repo: String!, $prNumber: Int!) { repository(owner: $owner, name: $repo) { pullRequest(number: $prNumber) { reviewThreads(first: 100) { pageInfo { hasNextPage endCursor } nodes { id path line isResolved comments(first: 1) { nodes { body author { login } } } } } } } }')
    else
      RESULT=$(gh api graphql -f owner="$OWNER" -f repo="$REPO_NAME" -F prNumber=$PR_NUM -f cursor="$CURSOR" -f query='query($owner: String!, $repo: String!, $prNumber: Int!, $cursor: String!) { repository(owner: $owner, name: $repo) { pullRequest(number: $prNumber) { reviewThreads(first: 100, after: $cursor) { pageInfo { hasNextPage endCursor } nodes { id path line isResolved comments(first: 1) { nodes { body author { login } } } } } } } }')
    fi
    PAGE_THREADS=$(echo "$RESULT" | jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)]')
    ALL_THREADS=$(echo "$ALL_THREADS $PAGE_THREADS" | jq -s 'add')
    HAS_NEXT=$(echo "$RESULT" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage')
    if [ "$HAS_NEXT" != "true" ]; then break; fi
    CURSOR=$(echo "$RESULT" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor')
  done
  echo "$ALL_THREADS"
}

# Fetch threads + batch comments
THREADS=$(fetch_unresolved_threads)
BATCH_COMMENTS=$(gh api "repos/$REPO/pulls/$PR_NUM/comments" --paginate --jq '[.[] | select(.in_reply_to_id == null) | {id, path, line, body, author: .user.login}]')
```

### Step 3: Address Each Comment

For each comment, determine the action and resolve appropriately:

| Action | What to Do | Resolve? |
|--------|------------|----------|
| **FIX** | Implement the suggested change | ✅ Yes |
| **SKIP** | Invalid, already fixed, or not applicable | ✅ Yes |
| **REPLY** | Explain why current approach is correct | ✅ Yes |
| **DEFER** | Genuine future work (create ticket) | ❌ No |

**For FIX actions, use `edit_file`:**

```
for comment in selected_comments:
    if action == FIX:
        mcp__morph-mcp__edit_file({
          path: comment.path,
          code_edit: "// ... existing code ...\n<fixed code>\n// ... existing code ...",
          instruction: "Fix: " + comment.body
        })
    elif action == REPLY:
        # Add reply comment explaining why
    elif action == SKIP:
        # Just resolve the thread
    elif action == DEFER:
        # Create Linear ticket, leave thread open
```

### Step 4: Run Code Check

```
/code-check --quick
```

### Step 5: Commit & Push

```bash
git add .
git commit -m "[TICKET] Fix PR feedback"
git push
```

### Step 6: Resolve Threads

**Resolve ALL addressed threads (fixed, skipped, or replied):**

```bash
MERGE_BASE=$(git merge-base HEAD origin/main)
MODIFIED_FILES=$(git diff --name-only "$MERGE_BASE" HEAD)
UNRESOLVED=$(fetch_unresolved_threads)

# Track which threads to resolve
THREADS_TO_RESOLVE=()  # Thread IDs we should resolve

echo "$UNRESOLVED" | jq -c '.[]' | while read -r THREAD; do
  THREAD_ID=$(echo "$THREAD" | jq -r '.id')
  FILE_PATH=$(echo "$THREAD" | jq -r '.path')
  
  # Resolve if:
  # 1. File was modified (FIX action)
  # 2. Thread was marked SKIP/REPLY (addressed without code change)
  # Do NOT resolve if: DEFER (genuine future work)
  
  if echo "$MODIFIED_FILES" | grep -qF "$FILE_PATH"; then
    gh api graphql -f threadId="$THREAD_ID" -f query='mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } } }'
    echo "✅ Resolved thread in $FILE_PATH (fixed)"
  fi
done

# Also resolve SKIP/REPLY threads (not in modified files but addressed)
for THREAD_ID in ${SKIP_REPLY_THREADS[@]}; do
  gh api graphql -f threadId="$THREAD_ID" -f query='mutation($threadId: ID!) { resolveReviewThread(input: {threadId: $threadId}) { thread { id isResolved } } }'
  echo "✅ Resolved thread (skipped/replied)"
done
```

### Step 7: Output

```markdown
# ✅ Fixed PR Comments

## Addressed
| # | Action | Comment | Result |
|---|--------|---------|--------|
| 1 | FIX | Missing null check | ✅ Resolved |
| 2 | SKIP | Already handled by try-catch | ✅ Resolved |
| 3 | FIX | Magic number | ✅ Resolved |
| 4 | DEFER | Add caching layer | ⏳ Ticket created |

## Summary
- Fixed: 2
- Skipped: 1
- Deferred: 1 (ticket: ENG-456)
- Resolved: 3 threads
- Remaining: 1 thread (deferred)

## Code Check
- Type Check: ✅
- Lint: ✅

{If all resolved:} ✅ READY FOR RE-REVIEW
{If deferred remain:} ⏳ {N} deferred to future tickets
```

---

## Resolution Logic

**RESOLVE the thread if:**
- ✅ **FIX** - Code was changed to address the comment
- ✅ **SKIP** - Comment is invalid, misunderstood, or already addressed
- ✅ **REPLY** - Explained why current approach is correct (no code change needed)

**LEAVE OPEN only if:**
- ⏳ **DEFER** - Genuine future work that should be tracked
  - Create a Linear ticket for the work
  - Reply to the thread with ticket link
  - Leave thread open as reminder

**Why resolve SKIP/REPLY?**
- Keeps PR clean for re-review
- Reviewer can re-open if they disagree
- Resolved ≠ "you're right", it means "addressed"

---

## Notes

- **Simple flow**: Fix → /code-check → commit → resolve threads
- **Calls /code-check**: Type check + lint handled by dedicated command
- **Fresh queries**: Pagination support for >100 comments
- **Merge base compare**: Resolves threads if file modified anywhere in PR
- **Aggressive resolution**: Resolve everything except genuine DEFER items
- Run after `/review-pr-comments` for numbered comment list
- Batch comments (Greptile's "Additional Comments") can't be resolved via API

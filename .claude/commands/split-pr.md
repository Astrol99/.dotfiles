---
description: Split large PR into smaller, reviewable PRs
argument-hint: [PR-NUMBER] [strategy] [dry-run] [stack]
scope: global
---

# Split PR

Split a large PR into smaller, reviewable PRs.

**Arguments:** $ARGUMENTS (LLM interprets)

```
/split-pr                → Split current branch's PR (auto strategy)
/split-pr 123            → Split PR #123
/split-pr by directory   → Split by top-level directory
/split-pr by commit      → Split by commit
/split-pr dry-run        → Analyze only, don't create PRs
/split-pr stack          → Force stacked PRs
```

**Default: Independent PRs from main** (preferred)
**Fallback: Stacked PRs** (only when dependencies require it)

---

## Instructions

### Phase 1: Analyze PR

```bash
# Get PR number (from arg or current branch)
PR_NUM=${1:-$(gh pr list --head "$(git branch --show-current)" --json number -q '.[0].number')}
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
OWNER=${REPO%%/*}
REPO_NAME=${REPO##*/}

# Fetch PR metadata
PR_DATA=$(gh pr view $PR_NUM --json title,headRefName,baseRefName,body,commits)
PR_TITLE=$(echo "$PR_DATA" | jq -r '.title')
PR_BRANCH=$(echo "$PR_DATA" | jq -r '.headRefName')
BASE_BRANCH=$(echo "$PR_DATA" | jq -r '.baseRefName')
TICKET_ID=$(echo "$PR_BRANCH" | grep -oE '[A-Z]+-[0-9]+')

# Detect PR type from branch/title
PR_TYPE="Feat"  # Default
if echo "$PR_BRANCH" | grep -qiE "fix|bug"; then PR_TYPE="Bug Fix"; fi
if echo "$PR_BRANCH" | grep -qiE "refactor"; then PR_TYPE="Refactor"; fi
if echo "$PR_BRANCH" | grep -qiE "chore"; then PR_TYPE="Chore"; fi

# Get changed files
FILES_CHANGED=$(gh pr diff $PR_NUM --name-only)
FILE_COUNT=$(echo "$FILES_CHANGED" | wc -l | tr -d ' ')

# Get commits
COMMITS=$(gh pr view $PR_NUM --json commits -q '.commits[] | "\(.oid[:7]) \(.messageHeadline)"')

echo "PR #$PR_NUM: $PR_TITLE"
echo "Branch: $PR_BRANCH"
echo "Files: $FILE_COUNT"
```

**Fetch UNRESOLVED comments for migration (paginated):**

```bash
fetch_unresolved_comments() {
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

UNRESOLVED_COMMENTS=$(fetch_unresolved_comments)
COMMENT_COUNT=$(echo "$UNRESOLVED_COMMENTS" | jq 'length')
echo "Unresolved comments: $COMMENT_COUNT"
```

---

### Phase 2: Detect Split Strategy

**Based on argument or auto-detect:**

#### Auto Strategy (default)

1. **Check for multi-app changes:**
   ```bash
   APPS=$(echo "$FILES_CHANGED" | grep -E '^apps/' | cut -d'/' -f2 | sort -u)
   PACKAGES=$(echo "$FILES_CHANGED" | grep -E '^packages/' | cut -d'/' -f2 | sort -u)
   ```

2. **If multiple apps/packages → split by directory**

3. **If single app → split by type:**
   - `prisma/`, `migrations/` → Schema group
   - `server/routers/`, `server/services/` → API group
   - `components/`, `pages/` → UI group
   - `*.spec.ts`, `*.test.ts` → Tests group

4. **If well-organized commits → split by commit**

**Present proposed split:**

```markdown
## Proposed Split

Based on analysis, recommend splitting into **3 PRs**:

### Group 1: Database Schema
- `prisma/schema.prisma`
- `prisma/migrations/xxx`
- **2 files** | +50 -0 lines

### Group 2: API Layer
- `apps/evals-web/src/server/routers/feature.ts`
- `apps/evals-web/src/server/services/feature.service.ts`
- **4 files** | +200 -10 lines

### Group 3: UI Components
- `apps/evals-web/src/components/Feature/`
- `apps/evals-web/src/pages/feature.tsx`
- **8 files** | +400 -20 lines

Proceed? [Y/n/modify]
```

---

### Phase 3: Dependency Analysis

**Check if independent PRs are possible:**

```bash
check_dependencies() {
  GROUP_A_FILES=$1
  GROUP_B_FILES=$2

  for file in $GROUP_B_FILES; do
    # Check if file imports from Group A files
    imports=$(grep -E "^import|from ['\"]" "$file" 2>/dev/null || true)

    for a_file in $GROUP_A_FILES; do
      # Extract import path pattern
      import_pattern=$(echo "$a_file" | sed 's|\.tsx\?$||' | sed 's|/index$||')
      if echo "$imports" | grep -q "$import_pattern"; then
        echo "DEPENDENCY: $file imports from $a_file"
        return 0  # Found dependency
      fi
    done
  done
  return 1  # No dependency
}
```

**Determine approach:**

| Scenario | Approach |
|----------|----------|
| No dependencies between groups | ✅ Independent PRs (all from main) |
| Linear dependency (A → B → C) | ⚠️ Stack dependent parts |
| Circular dependency | ❌ Merge affected groups |

---

### Phase 4: Validation (Parallel Agents)

**Launch parallel agents to validate each group compiles from main:**

```
# All Task() calls in ONE message for parallel execution

Task({
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: `Validate Group 1 compiles from main.

## Context
Group: ${GROUP_1_NAME}
Files: ${GROUP_1_FILES}
PR Branch: ${PR_BRANCH}

## Instructions
1. Create temp branch from main
2. Checkout only group files from PR branch
3. Run /code-check --quick
4. Report: compiles (true/false), errors if any
5. Cleanup temp branch`
})

# Launch all validation agents in parallel
Task({ ... for Group 1 })
Task({ ... for Group 2 })
Task({ ... for Group 3 })
```

**Wait for all agents:**
```
TaskOutput({ task_id: "agent-1-id", block: true })
TaskOutput({ task_id: "agent-2-id", block: true })
TaskOutput({ task_id: "agent-3-id", block: true })
```

**If validation fails from main, try stacked approach.**

---

### Phase 5: Create PRs (Parallel Agents)

**Launch parallel agents to create each PR:**

#### Independent PRs (preferred)

```
# All Task() calls in ONE message for parallel execution

Task({
  subagent_type: "general-purpose",
  run_in_background: true,
  prompt: `Create PR for Group 1.

## Context
Group: ${GROUP_1_NAME}
Files: ${GROUP_1_FILES}
PR Branch: ${PR_BRANCH}
Ticket: ${TICKET_ID}
PR Type: ${PR_TYPE}
Part: 1/${TOTAL_GROUPS}
Subtitle: ${GROUP_1_DESC}

## Instructions
1. Create branch from main: ${TICKET_ID}-${GROUP_1_NAME}
2. Checkout files from original PR branch
3. Commit with message: "[${TICKET_ID}] ${GROUP_1_DESC}"
4. Push branch
5. Run /create-pr from ${PR_NUM} 1/${TOTAL_GROUPS} ${GROUP_1_DESC}
6. Report: PR number, URL`
})

# Launch all PR creation agents in parallel
Task({ ... for Group 1 })
Task({ ... for Group 2 })
Task({ ... for Group 3 })
```

**PR Title Format:**
```
[Feat] [ENG-123] Add user auth 1/3: Database schema
[Feat] [ENG-123] Add user auth 2/3: API endpoints
[Feat] [ENG-123] Add user auth 3/3: UI components
```

#### Stacked PRs (when dependencies require)

For stacked parts, pass dependency info:
```
/create-pr from ${PR_NUM} 2/${TOTAL_GROUPS} ${DESC} needs ${PREV_PR} base ${PREV_BRANCH}
```

**Title with dependency:**
```
[Feat] [ENG-123] Add user auth 2/3: API endpoints (needs #201)
```

---

### Phase 5.5: Migrate Unresolved Comments

```bash
# For each unresolved comment
echo "$UNRESOLVED_COMMENTS" | jq -c '.[]' | while read -r COMMENT; do
  FILE_PATH=$(echo "$COMMENT" | jq -r '.path')
  BODY=$(echo "$COMMENT" | jq -r '.comments.nodes[0].body')
  AUTHOR=$(echo "$COMMENT" | jq -r '.comments.nodes[0].author.login')
  LINE=$(echo "$COMMENT" | jq -r '.line')

  # Find which split PR has this file
  for SPLIT_PR in "${SPLIT_PRS[@]}"; do
    PR_FILES=$(gh pr view $SPLIT_PR --json files -q '.files[].path')
    if echo "$PR_FILES" | grep -qF "$FILE_PATH"; then
      # Add comment to split PR
      gh pr comment $SPLIT_PR --body "**Migrated from #$PR_NUM** (by @$AUTHOR)

> File: \`$FILE_PATH:$LINE\`

$BODY"
      echo "Migrated comment to PR #$SPLIT_PR"
      break
    fi
  done
done
```

---

### Phase 6: Cleanup Original PR

```bash
# Build PR table
PR_TABLE=""
for pr in "${SPLIT_PRS[@]}"; do
  TITLE=$(gh pr view $pr --json title -q '.title')
  BASE=$(gh pr view $pr --json baseRefName -q '.baseRefName')
  PR_TABLE="$PR_TABLE| #$pr | $TITLE | $BASE |\n"
done

# Add summary comment to original PR
gh pr comment $PR_NUM --body "## This PR has been split

| PR | Title | Base |
|----|-------|------|
$PR_TABLE

**Approach:** $APPROACH

**Unresolved comments migrated:** $COMMENT_COUNT

*Split by \`/split-pr\`*"

# Close original PR
gh pr close $PR_NUM
echo "Closed original PR #$PR_NUM"
```

---

### Phase 7: Output Summary

```markdown
# ✅ PR Split Complete

## Original PR
- **#${PR_NUM}** - ${PR_TITLE}
- Status: Closed
- Files: ${FILE_COUNT} → Split into ${#SPLIT_PRS[@]} PRs

## Created PRs

| PR | Title | Base | Files | Status |
|----|-------|------|-------|--------|
| #201 | [Feat] [ENG-123] Add user auth 1/3: Database schema | main | 6 | Draft |
| #202 | [Feat] [ENG-123] Add user auth 2/3: API endpoints | main | 8 | Draft |
| #203 | [Feat] [ENG-123] Add user auth 3/3: UI components | main | 12 | Draft |

## Approach
${APPROACH_SUMMARY}

## Comments Migrated
${MIGRATED_COMMENTS_SUMMARY}

## Next Steps
1. Review each PR
2. Run `/code-check` before marking ready
3. ${MERGE_ORDER_NOTE}
```

---

## Dry Run Mode

With `dry-run` argument, output analysis without creating PRs:

```markdown
# 🔍 PR Split Analysis (Dry Run)

## Original PR
- **#123** - [ENG-456] Add new feature
- Files: 26

## Proposed Split

### Group 1: Database Schema (6 files)
- prisma/schema.prisma
- prisma/migrations/xxx
**Can compile independently from main:** ✅

### Group 2: API Layer (8 files)
- apps/evals-web/src/server/routers/...
**Can compile independently from main:** ✅

### Group 3: UI Components (12 files)
- apps/evals-web/src/components/...
**Can compile independently from main:** ✅

## Recommended Approach
✅ **Independent PRs** - No dependencies detected

## Unresolved Comments
- 4 total → will be migrated to relevant PRs

## To Execute
Remove `dry-run` to create PRs
```

---

## Notes

- **Prefers independent PRs** - Easier to review and merge
- **Only stacks when necessary** - Dependencies between groups
- **Only migrates UNRESOLVED comments** - Resolved threads ignored
- **Uses /create-pr** - With natural arguments for split context
- **Parallel validation** - All groups validated simultaneously
- **Parallel PR creation** - All PRs created simultaneously
- **Pagination support** - Handles >100 comments
- **Fresh queries** - No cached data
- **Closes original PR** - After successful split
- **Title format**: `[Type] [TICKET] Title N/M: subtitle`
- Ticket ID extracted from branch name
- Each split PR links back to original

---
description: Codex review → Claude fix alternating loop
argument-hint: [--iterations=4] [--path=<path>]
scope: global
---

# Loop Review

Codex↔Claude alternating review loop. Standalone AND callable by other commands.

**Arguments:** $ARGUMENTS

**Options:**
- `--iterations=N` - Number of iterations (default: 4, meaning 2 Codex + 2 Claude)
- `--path=<path>` - Path to review (default: current directory)

---

## Instructions

### Step 1: Parse Arguments

```bash
MAX_ITERATIONS=4
REVIEW_PATH="$(pwd)"

for arg in $ARGUMENTS; do
  case $arg in
    --iterations=*)
      MAX_ITERATIONS="${arg#*=}"
      ;;
    --path=*)
      REVIEW_PATH="${arg#*=}"
      ;;
  esac
done
```

### Step 2: Run Review Loop

```
ITERATION=1
ISSUES_FOUND=0
ISSUES_FIXED=0

while ITERATION <= MAX_ITERATIONS:

  if ITERATION % 2 == 1:
    #
    # ODD ITERATIONS: Codex Reviews
    #
    
    review = Task({
      subagent_type: "codex-review-agent",
      prompt: `Review the recent changes for issues.

## Context
Path: ${REVIEW_PATH}
Iteration: ${ITERATION} of ${MAX_ITERATIONS}

## Instructions
1. Get the diff against main (all changes in the branch):
   cd ${REVIEW_PATH} && git diff $(git merge-base HEAD origin/main)

2. Analyze the diff for:
   - Logic errors and edge cases
   - Type safety issues (missing types, unsafe casts)
   - Performance concerns (unnecessary re-renders, N+1 queries)
   - Security vulnerabilities (XSS, injection, auth bypasses)
   - Code style violations

3. Return a JSON array of issues:
   [
     {
       "file": "path/to/file.ts",
       "line": 42,
       "severity": "high|medium|low",
       "issue": "Description of the problem",
       "suggestion": "How to fix it"
     }
   ]

4. If no issues found, return: []

Be thorough but practical - focus on real bugs, not style nitpicks.`
    })

    issues = parse_json(review)

    if issues.length == 0:
      print("✅ Clean on iteration ${ITERATION}!")
      break

    ISSUES_FOUND += issues.length
    store_issues(issues)  # For Claude to fix

  else:
    #
    # EVEN ITERATIONS: Claude Fixes (using edit_file for speed)
    #
    
    issues = get_stored_issues()

    for issue in issues:
      # Use edit_file for 10x faster edits
      mcp__morph-mcp__edit_file({
        path: "${REVIEW_PATH}/${issue.file}",
        code_edit: "// ... existing code ...\n<fixed code>\n// ... existing code ...",
        instruction: "Fix: ${issue.issue} - ${issue.suggestion}"
      })

      ISSUES_FIXED++

    # Run code-check to verify fixes
    /code-check --quick

    # Commit the fixes
    (cd ${REVIEW_PATH} && git add . && git commit -m "Fix review feedback (round ${ITERATION/2})")

  ITERATION++
```

### Step 3: Output

```markdown
# ✅ Loop Review Complete

**Path:** {REVIEW_PATH}
**Iterations:** {ITERATION} of {MAX_ITERATIONS}

## Summary
- Issues found by Codex: {ISSUES_FOUND}
- Issues fixed by Claude: {ISSUES_FIXED}
- Final status: {Clean ✅ | {N} remaining ⚠️}

{If early exit:}
**Note:** Exited early - code was clean on iteration {ITERATION}

## Issues Fixed
{For each fixed issue:}
- **{file}:{line}** [{severity}] - {issue}

{If issues remain:}
## Remaining Issues
{List any unfixed issues for manual attention}
```

---

## Usage Examples

```bash
# Review current branch (default 4 iterations)
/loop-review

# Quick review (just 1 Codex + 1 Claude round)
/loop-review --iterations=2

# Review a worktree
/loop-review --path=.worktrees/ENG-123

# Thorough review (3 Codex + 3 Claude rounds)
/loop-review --iterations=6
```

---

## Called by Other Commands

```markdown
# In /start-ticket after implementation:
**Step 7: Self-Review**
/loop-review --path=.worktrees/${TICKET_ID}

# In /fix-pr-comments after fixing:
**Step 5: Self-Review**
/loop-review --iterations=2

# In /start-pr-review for each PR:
**Step 5: Optional Review**
/loop-review --path=.worktrees/pr-${PR_NUM}
```

---

## How It Works

```
Iteration 1: Codex reviews diff (against merge-base)
    └─→ Returns JSON array of issues

Iteration 2: Claude fixes issues (using edit_file)
    └─→ Runs /code-check --quick
    └─→ Commits: "Fix review feedback (round 1)"

Iteration 3: Codex reviews again
    └─→ Checks if fixes introduced new issues
    └─→ If clean: EXIT EARLY ✅

Iteration 4: Claude fixes remaining (using edit_file)
    └─→ Runs /code-check --quick
    └─→ Commits: "Fix review feedback (round 2)"
```

---

## Notes

- **Codex** (odd iterations): Read-only review, returns structured JSON
- **Claude** (even iterations): Implements fixes using `edit_file` (10x faster)
- **Uses merge-base**: Reviews all changes in the branch, not just last commit
- **Uses /code-check**: Consistent verification across all commands
- **Early exit**: If Codex finds no issues, stop immediately
- **Standalone**: Can be called directly by user
- **Composable**: Called by `/start-ticket`, `/fix-pr-comments`, etc.
- **Configurable**: Adjust iterations and path as needed
- Default 4 iterations = up to 2 review/fix cycles

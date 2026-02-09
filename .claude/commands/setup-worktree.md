---
description: Smart worktree creation with conflict resolution
argument-hint: <branch-or-ticket-or-pr> [--force]
scope: global
---

# Setup Worktree

Smart worktree creation with conflict detection and auto-resolution.

**Arguments:** $ARGUMENTS

**Formats:**
- Ticket ID: `ENG-123` → creates `.worktrees/ENG-123` on `feat/ENG-123`
- Branch: `feat/my-feature` → creates `.worktrees/feat-my-feature`
- PR number: `#89` or `89` → creates `.worktrees/pr-89` on PR's branch
- `--force` → Remove existing worktree first

---

## Instructions

### Step 1: Parse Input

```bash
INPUT="$1"
FORCE="${2:-}"

# Detect input type
if [[ "$INPUT" =~ ^#?[0-9]+$ ]]; then
  # PR number
  PR_NUM="${INPUT#\#}"
  BRANCH=$(gh pr view "$PR_NUM" --json headRefName -q '.headRefName')
  WORKTREE_NAME="pr-$PR_NUM"
elif [[ "$INPUT" =~ ^[A-Z]+-[0-9]+$ ]]; then
  # Ticket ID (e.g., ENG-123)
  TICKET_ID="$INPUT"
  BRANCH="feat/$TICKET_ID"
  WORKTREE_NAME="$TICKET_ID"
else
  # Branch name
  BRANCH="$INPUT"
  WORKTREE_NAME="${BRANCH//\//-}"  # Replace / with -
fi

WORKTREE_DIR=".worktrees"
```

### Step 2: Find Available Path (Auto-Naming)

```bash
get_available_path() {
  local BASE_NAME="$1"
  local DIR="$WORKTREE_DIR"

  # Try base name first
  if can_use_worktree "$DIR/$BASE_NAME"; then
    echo "$DIR/$BASE_NAME"
    return
  fi

  # Try numbered versions
  for i in 2 3 4 5; do
    if can_use_worktree "$DIR/$BASE_NAME-$i"; then
      echo "$DIR/$BASE_NAME-$i"
      return
    fi
  done

  echo "ERROR"
}

can_use_worktree() {
  local TARGET_PATH="$1"

  # Doesn't exist → can use
  [ ! -d "$TARGET_PATH" ] && return 0

  # Check if it's a valid git worktree we can update
  if [ -f "$TARGET_PATH/.git" ]; then
    # It's a worktree - check if we can access it
    (cd "$TARGET_PATH" && git status >/dev/null 2>&1) && return 0
  fi

  # Can't use
  return 1
}

WORKTREE_PATH=$(get_available_path "$WORKTREE_NAME")

if [ "$WORKTREE_PATH" = "ERROR" ]; then
  echo "❌ Too many conflicting worktrees for $WORKTREE_NAME"
  exit 1
fi
```

### Step 3: Handle --force

```bash
if [ "$FORCE" = "--force" ] && [ -d "$WORKTREE_DIR/$WORKTREE_NAME" ]; then
  echo "Removing existing worktree..."
  git worktree remove "$WORKTREE_DIR/$WORKTREE_NAME" --force
fi
```

### Step 4: Create or Update Worktree

```bash
mkdir -p "$WORKTREE_DIR"
git fetch origin

if [ -d "$WORKTREE_PATH" ]; then
  # Exists and accessible - update it
  echo "Updating existing worktree at $WORKTREE_PATH..."
  (
    cd "$WORKTREE_PATH" || exit 1
    git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" "origin/$BRANCH"
    git pull --ff-only || git pull --rebase
  )
  STATUS="Updated existing"
else
  # Create new worktree
  echo "Creating new worktree at $WORKTREE_PATH..."
  
  # Check if branch exists on remote
  if git ls-remote --heads origin "$BRANCH" | grep -q "$BRANCH"; then
    # Branch exists - use it
    git worktree add "$WORKTREE_PATH" "origin/$BRANCH"
  else
    # Branch doesn't exist - create from main
    git worktree add -b "$BRANCH" "$WORKTREE_PATH" origin/main
  fi
  STATUS="Created new"
fi
```

### Step 5: Install Dependencies (Optimized)

```bash
echo "Checking dependencies..."
(
  cd "$WORKTREE_PATH" || exit 1

  # Check if node_modules is up-to-date
  if [ -f "node_modules/.package-lock.json" ] && [ -f "package-lock.json" ]; then
    # Compare timestamps - if lock file is newer, need install
    if [ "package-lock.json" -nt "node_modules/.package-lock.json" ]; then
      echo "Lock file changed, running npm ci..."
      npm ci
      DEP_STATUS="Reinstalled (lock changed)"
    else
      echo "Dependencies up-to-date, skipping install"
      DEP_STATUS="Skipped (up-to-date)"
    fi
  elif [ -f "package-lock.json" ]; then
    # Has lock file but no node_modules - use npm ci (faster)
    echo "Installing dependencies with npm ci..."
    npm ci
    DEP_STATUS="Installed (npm ci)"
  else
    # No lock file - use npm install
    echo "Installing dependencies with npm install..."
    npm install
    DEP_STATUS="Installed (npm install)"
  fi
  
  echo "$DEP_STATUS" > /tmp/worktree_dep_status
)

DEP_STATUS=$(cat /tmp/worktree_dep_status 2>/dev/null || echo "Unknown")
```

### Step 6: Validate

```bash
if [ -f "$WORKTREE_PATH/package.json" ]; then
  VALID="✅"
else
  VALID="❌ Missing package.json"
fi
```

### Step 7: Output

```markdown
# ✅ Worktree Ready

**Path:** {WORKTREE_PATH}
**Branch:** {BRANCH}
**Status:** {STATUS}
**Dependencies:** {DEP_STATUS}
**Validation:** {VALID}

{If auto-named:}
**Note:** Original path in use, created {WORKTREE_NAME}-{N} instead
```

---

## Usage Examples

```bash
# For a ticket
/setup-worktree ENG-123
# Creates: .worktrees/ENG-123 on feat/ENG-123

# For a PR
/setup-worktree 89
# Creates: .worktrees/pr-89 on PR's branch

# For a branch
/setup-worktree feat/new-feature
# Creates: .worktrees/feat-new-feature

# Force recreate
/setup-worktree ENG-123 --force
# Removes existing and creates fresh

# When original is in use
/setup-worktree ENG-123
# Creates: .worktrees/ENG-123-2 (if ENG-123 is locked)
```

---

## Conflict Resolution

| Scenario | Action |
|----------|--------|
| Path doesn't exist | Create new worktree |
| Path exists, accessible | Update (pull latest) |
| Path exists, locked/in-use | Create with suffix (-2, -3, etc.) |
| Too many conflicts (>5) | Error out |

---

## Notes

- Auto-detects input type (ticket, PR, branch)
- Auto-names to avoid conflicts (like `file(1).txt`)
- **Uses subshells** for directory changes (prevents working directory issues)
- **Optimized npm install:**
  - Uses `npm ci` when lock file exists (faster, deterministic)
  - Skips install if `node_modules` is up-to-date
  - Falls back to `npm install` only when no lock file
- Validates worktree has package.json
- Use `--force` to remove and recreate
- Returns worktree path for use by other commands

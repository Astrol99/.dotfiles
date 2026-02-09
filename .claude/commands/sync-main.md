---
description: Sync feature branch with latest main
argument-hint: [--rebase]
scope: global
---

# Sync Main

Sync current feature branch with latest main.

**Arguments:** $ARGUMENTS
- (default) - Merge main into branch
- `--rebase` - Rebase branch onto main (cleaner history)

---

## Instructions

### Step 1: Safety Checks

```bash
git branch --show-current
git status --porcelain
```

**If on main:** Error - switch to feature branch
**If uncommitted changes:** Stash or commit first

### Step 2: Fetch Latest

```bash
git fetch origin main
```

### Step 3: Sync (based on argument)

**Default (merge):**
```bash
git merge origin/main
```

**With --rebase:**
```bash
git rebase origin/main
```

### Step 4: Handle Conflicts

**Auto-resolve (safe):**
- Import order changes
- Non-overlapping edits
- Lock file conflicts → regenerate with `npm install`

**Ask user:**
- package.json version conflicts
- Config file conflicts
- Overlapping code changes

**For rebase conflicts:**
```bash
# After resolving each conflict
git add .
git rebase --continue

# If stuck, offer to abort
git rebase --abort
```

### Step 5: Verify with /code-check

```
/code-check --quick
```

### Step 6: Output

```markdown
# ✅ Synced with Main

**Method:** {Merge | Rebase}
**Commits:** {N} commits from main
**Conflicts:** {resolved/none}

Code check: ✅

{If rebased:}
**Note:** Force push required: `git push --force-with-lease`
```

---

## Notes

- Merge (default): Preserves history, no force push needed
- Rebase: Cleaner linear history, requires force push
- Safe conflict auto-resolution for simple cases
- Asks for complex conflicts
- **Uses /code-check --quick** for verification (consistent across commands)

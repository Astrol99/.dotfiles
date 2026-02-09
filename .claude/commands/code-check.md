---
description: Pre-PR verification - type check, lint, tests, code review
argument-hint: [--quick | --build]
scope: global
---

# Code Check

Fast mechanical checks for code quality.

**Arguments:** $ARGUMENTS (optional)

- No args: type-check + lint + tests (if changed)
- `--quick`: type-check + lint only (skip tests)
- `--build`: include build verification

---

## Instructions

### Step 1: Parse Arguments & Get Changes

**Parse mode:**
```
--quick → Skip tests
--build → Include build step
(default) → Type-check + lint + tests
```

**Get changes:**
```
mcp__conductor__GetWorkspaceDiff({ stat: true })
```

**Detect affected app(s):**
```bash
git diff --name-only origin/main | grep -E '^apps/' | cut -d'/' -f2 | sort -u
```

| Path Pattern | App | Type Check | Lint |
|--------------|-----|------------|------|
| `apps/evals-web/` | evals-web | `npm run type-check:web` | `cd apps/evals-web && npx ultracite fix` |
| `apps/evals-queue/` | evals-queue | `npm run type-check:queue` | `cd apps/evals-queue && npx ultracite fix` |
| `apps/livekit-worker/` | livekit-worker | Python type checks | Python linting |
| `packages/` | shared packages | `npm run type-check` (root) | Root ultracite |

---

### Step 2: Run Checks (Parallel)

Execute based on detected app(s):

**Type Check:**
```bash
# Run in parallel for each affected app
npm run type-check:web    # if evals-web changed
npm run type-check:queue  # if evals-queue changed
npm run type-check        # if packages changed
```

**Lint (auto-fix):**
```bash
cd apps/{APP_NAME} && npx ultracite fix
```

---

### Step 3: Tests (Skip if --quick)

```bash
# Only run if test files changed AND not --quick mode
CI=true npm run test        # evals-web
CI=true npm run test:unit   # evals-queue
```

---

### Step 4: Build (Only if --build)

```bash
# Only if --build flag specified
npm run build:web    # or appropriate build command
```

---

### Step 5: Output

```markdown
# ✅ Code Check

**Mode:** {default | quick | build}

## Apps Checked
- evals-web ✅
- evals-queue ✅

## Results
| Check | Status | Details |
|-------|--------|---------|
| Type Check | ✅ | No errors |
| Lint | ✅ | Auto-fixed 3 issues |
| Tests | ✅ | 42 passed | (or ⏭️ Skipped if --quick)
| Build | ✅ | Success | (or ⏭️ Skipped if not --build)

## Next Steps
{If all pass:} Ready for `/quality-check` or `/create-pr`
{If failures:} Fix issues above
```

---

## Notes

- **Fast**: ~30 seconds typical run
- Dynamically detects which apps changed
- Runs correct commands per app
- Run checks in parallel for speed
- Use `--quick` during rapid iteration
- Use `--build` before final PR submission
- **Testing**: When modifying `*.service.ts` or `*.utils.ts` files, read `.cursor/rules/unit-testing-best-practices.mdc` and consider adding tests

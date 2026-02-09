---
description: Run all review and check commands to ensure code quality
argument-hint: [quick]
scope: global
---

# Make Dario Happy

Run all quality checks to ensure your code is production-ready.

**Arguments:** $ARGUMENTS

```
/make-dario-happy         → Full quality pass (with self-review)
/make-dario-happy quick   → Skip self-review
```

---

## Instructions

### Step 1: Self-Review (skip if quick mode)

```
/loop-review --iterations=2
```

Gets Codex review and fixes issues before running checks.

---

### Step 2: Code Check

```
/code-check
```

Type check + lint + tests. **Must pass.**

---

### Step 3: Quality Check

```
/quality-check
```

Runs:
- Security patterns
- Performance issues
- Code patterns
- Documentation check

---

### Step 4: Output

**If all pass:**

```markdown
# 🎉 Dario Will Be Happy

| Check | Status |
|-------|--------|
| Self-Review | ✅ Clean |
| Code Check | ✅ Pass |
| Quality Check | ✅ Pass |

**Ready for:** /create-pr ready
```

**If issues found:**

```markdown
# 😬 Dario Might Not Be Happy

| Check | Status | Issues |
|-------|--------|--------|
| Self-Review | ✅ Clean | - |
| Code Check | ❌ Fail | 3 type errors |
| Quality Check | ⚠️ Warnings | 2 security flags |

## Fix Order
1. Fix type errors first
2. Address security flags
```

---

## Order Rationale

1. **Self-review first** - Codex may catch and fix issues
2. **Code check second** - Verify types/lint after fixes
3. **Quality check last** - Deep analysis on clean code

---

## Notes

- Runs checks in optimal order
- Self-review may auto-fix issues before checks run
- Stops on critical failures (type errors)
- Continues on warnings (quality flags)
- Use before `/create-pr ready`
- `quick` mode skips `/loop-review` only

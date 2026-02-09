---
description: Comprehensive code quality analysis - patterns, security, performance, docs
argument-hint: [--security | --performance | --patterns | --docs]
scope: global
---

# Quality Check

Deep semantic analysis for code quality before PR submission.

**Arguments:** $ARGUMENTS (optional)

- No args: all checks
- `--security`: security checks only
- `--performance`: performance checks only
- `--patterns`: pattern compliance only
- `--docs`: documentation checks only

---

## Instructions

### Step 1: Get Changed Files & Branch Info

```bash
# Get list of changed files for targeted analysis
CHANGED_FILES=$(git diff --name-only origin/main)

# Get branch name for ticket extraction
BRANCH=$(git branch --show-current)
TICKET=$(echo "$BRANCH" | grep -oE 'ENG-[0-9]+')
```

---

### Step 2: Pattern Compliance

**Check for inline functions that should be extracted:**
```bash
# Inline arrow functions in JSX event handlers (should use useCallback)
grep -rn "on[A-Z][a-zA-Z]*={\s*(" --include="*.tsx" $CHANGED_FILES 2>/dev/null | head -20

# tRPC handlers with inline logic (should extract to service)
grep -rn "\.mutation\|\.query" --include="*.ts" -A 5 $CHANGED_FILES 2>/dev/null | grep -E "async.*=>" | head -10
```

**Check for magic numbers/strings:**
```bash
# Hardcoded numbers (excluding 0, 1, common values)
grep -rn "[^a-zA-Z0-9_\"'][2-9][0-9]\{2,\}[^a-zA-Z0-9_\"']" --include="*.ts" --include="*.tsx" $CHANGED_FILES 2>/dev/null | grep -v "test\|spec\|\.d\.ts" | head -10
```

**Check for transaction race conditions:**
```bash
# Reading after transaction (potential race condition)
grep -rn "\$transaction" --include="*.ts" -A 10 $CHANGED_FILES 2>/dev/null | grep -E "findMany|findUnique|findFirst" | head -5
```

---

### Step 3: Security Checks

**Secrets detection:**
```bash
# Potential hardcoded secrets (excluding env references)
grep -rn "API_KEY\|SECRET\|PASSWORD\|PRIVATE_KEY\|TOKEN" --include="*.ts" --include="*.tsx" $CHANGED_FILES 2>/dev/null | grep -v "process\.env\|\.env\|// " | head -10
```

**Dangerous React patterns:**
```bash
# dangerouslySetInnerHTML usage
grep -rn "dangerouslySetInnerHTML" --include="*.tsx" $CHANGED_FILES 2>/dev/null

# External links without noopener
grep -rn 'target="_blank"' --include="*.tsx" $CHANGED_FILES 2>/dev/null | grep -v "noopener" | head -5
```

---

### Step 4: Performance Checks

**N+1 query patterns:**
```bash
# Prisma queries inside loops
grep -rn "for\|forEach\|map" --include="*.ts" -A 3 $CHANGED_FILES 2>/dev/null | grep -E "prisma\." | head -10
```

**Spread in accumulators:**
```bash
# Spread operator in reduce/loop (performance issue)
grep -rn "\.reduce\|\.forEach" --include="*.ts" --include="*.tsx" -A 3 $CHANGED_FILES 2>/dev/null | grep "\.\.\." | head -5
```

---

### Step 5: TypeScript Quality

**No `as any`:**
```bash
# as any usage (should use as unknown as X)
grep -rn "as any" --include="*.ts" --include="*.tsx" $CHANGED_FILES 2>/dev/null | grep -v "test\|spec\|\.d\.ts" | head -10
```

---

### Step 6: React Specific

**Components inside components:**
```bash
# Function components defined inside other components
grep -rn "const [A-Z][a-zA-Z]* = (" --include="*.tsx" $CHANGED_FILES 2>/dev/null | head -10
# (Manual review needed to check if inside render)
```

**Array index as key:**
```bash
# key={index} or key={i} patterns
grep -rn "key={.*index\|key={i}" --include="*.tsx" $CHANGED_FILES 2>/dev/null | head -5
```

---

### Step 7: Testing Coverage

**Check if service/utils files need tests:**
```bash
# New or modified service/utils files (exclude spec files)
SERVICE_FILES=$(echo "$CHANGED_FILES" | grep -E "\.(service|utils)\.ts$" | grep -v "\.spec\.")
if [ -n "$SERVICE_FILES" ]; then
  echo "Service/utils files modified:"
  echo "$SERVICE_FILES"
  # Check for corresponding .spec.ts
fi
```

**No .only or .skip:**
```bash
grep -rn "\.only\|\.skip" --include="*.spec.ts" --include="*.test.ts" $CHANGED_FILES 2>/dev/null
```

---

### Step 8: Documentation & Engineering Spec

**Determine if engineering spec is needed:**

A feature needs an engineering spec if ANY of these are true:
- New API endpoints added (`server/routers/`, `server/rest/`, `server/isc/`)
- Database schema changes (`prisma/schema.prisma`, migrations)
- New services created (`*.service.ts`)
- Significant new components (>200 lines in single component)
- New Temporal workflows (`workflows/`, `activities/`)
- Cross-app changes (changes in multiple `apps/`)

```bash
# Check for changes that warrant an eng spec
NEEDS_SPEC=false
SPEC_REASONS=""

# New API endpoints
if echo "$CHANGED_FILES" | grep -qE "server/routers/|server/rest/|server/isc/"; then
  NEEDS_SPEC=true
  SPEC_REASONS="$SPEC_REASONS\n- New/modified API endpoints"
fi

# Database changes
if echo "$CHANGED_FILES" | grep -qE "prisma/schema\.prisma|prisma/migrations"; then
  NEEDS_SPEC=true
  SPEC_REASONS="$SPEC_REASONS\n- Database schema changes"
fi

# New services (exclude spec files)
NEW_SERVICES=$(echo "$CHANGED_FILES" | grep -E "\.service\.ts$" | grep -v "\.spec\.")
if [ -n "$NEW_SERVICES" ]; then
  NEEDS_SPEC=true
  SPEC_REASONS="$SPEC_REASONS\n- New service files"
fi

# Temporal workflows
if echo "$CHANGED_FILES" | grep -qE "workflows/|activities/"; then
  NEEDS_SPEC=true
  SPEC_REASONS="$SPEC_REASONS\n- Temporal workflow changes"
fi

# Cross-app changes
APPS_CHANGED=$(echo "$CHANGED_FILES" | grep "^apps/" | cut -d'/' -f2 | sort -u | wc -l)
if [ "$APPS_CHANGED" -gt 1 ]; then
  NEEDS_SPEC=true
  SPEC_REASONS="$SPEC_REASONS\n- Cross-app changes ($APPS_CHANGED apps modified)"
fi
```

**Check for existing engineering spec:**
```bash
# Look for eng spec in common locations
if [ "$NEEDS_SPEC" = true ]; then
  # Check docs folder for related spec
  SPEC_EXISTS=false
  
  # Search by ticket number
  if [ -n "$TICKET" ]; then
    find docs/ -name "*$TICKET*" -o -name "*$(echo $TICKET | tr '[:upper:]' '[:lower:]')*" 2>/dev/null | head -1
  fi
  
  # Search by branch keywords (e.g., feat/voice-cloning -> voice-cloning)
  FEATURE_NAME=$(echo "$BRANCH" | sed 's/.*\///' | sed 's/ENG-[0-9]*-//')
  find docs/ -iname "*$FEATURE_NAME*" -type f 2>/dev/null | head -3
  
  # Check openspec/proposals if project uses it
  if [ -d "openspec/proposals" ]; then
    find openspec/proposals/ -iname "*$FEATURE_NAME*" -o -iname "*$TICKET*" 2>/dev/null | head -3
  fi
fi
```

**Engineering spec template (if missing):**
```markdown
If spec needed but not found, suggest creating:

/docs/{feature-name}/
├── engineering-spec.md    # Technical approach, architecture decisions
├── requirements.md        # What we're building and why
└── tasks.md              # Implementation checklist

Or use `/openspec create` if project uses OpenSpec.
```

---

### Step 9: Git Hygiene

**Large files:**
```bash
# Files over 500KB in changes
git diff --stat origin/main | awk '$3 > 500 {print $1, $3"KB"}'
```

**Sensitive files staged:**
```bash
git diff --name-only origin/main | grep -E "\.env|credentials|secrets|\.pem|\.key"
```

**Merge conflict markers:**
```bash
grep -rn "<<<<<<\|>>>>>>" --include="*.ts" --include="*.tsx" $CHANGED_FILES 2>/dev/null
```

---

### Step 10: Output

```markdown
# 🔍 Quality Check

## Summary
| Category | Issues | Status |
|----------|--------|--------|
| Patterns | 0 | ✅ |
| Security | 0 | ✅ |
| Performance | 2 | ⚠️ |
| TypeScript | 0 | ✅ |
| React | 1 | ⚠️ |
| Testing | 0 | ✅ |
| Documentation | 1 | ⚠️ |
| Git Hygiene | 0 | ✅ |

## Issues Found

### ⚠️ Performance (2)
1. **N+1 Query** `src/server/utils/orders.ts:45`
   - `findUnique` called inside `map()` - consider `findMany` with `where: { id: { in: ids } }`

2. **Spread in Accumulator** `src/utils/transform.ts:23`
   - `...acc` in reduce - use `acc.push()` instead

### ⚠️ React (1)
1. **Array Index as Key** `src/components/List.tsx:12`
   - Use unique ID instead of array index

### ⚠️ Documentation (1)
1. **Engineering Spec Missing**
   - Significant changes detected:
     - New API endpoints
     - Database schema changes
   - No engineering spec found for `ENG-123` / `voice-cloning`
   - **Action:** Create spec at `/docs/voice-cloning/engineering-spec.md`
   - See: CLAUDE.md → "Creating New Documentation" section

## Recommendations
- Fix ⚠️ issues before PR
- Consider performance implications
- **Create engineering spec** for architectural changes

---
**Ready:** `/create-pr` (with noted issues) | **Fix first:** Address issues above
```

---

## Notes

- **Comprehensive**: ~2-5 minute analysis
- Uses grep-based pattern detection (fast, no external deps)
- **Documentation check**: Ensures significant features have eng specs
- Some checks require manual review (flagged items)
- Run after `/code-check` passes
- Use specific flags (--security, --performance, --patterns, --docs) for focused checks
- Integrates with `/create-pr` workflow
- Engineering specs should document: approach, architecture, trade-offs, implementation plan

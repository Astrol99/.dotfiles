---
description: Split large ticket/idea into smaller implementation tasks
argument-hint: <TICKET-ID | idea description>
scope: global
---

# Split Task

Split a large ticket or idea into smaller, manageable implementation tasks.

**Arguments:** $ARGUMENTS (LLM interprets)

```
/split-task ENG-123                    → Split existing ticket into subtasks
/split-task Build a full RBAC system   → Split idea into multiple tickets
```

---

## Instructions

### Step 1: Determine Input Type

| Input Pattern | Mode |
|---------------|------|
| `ENG-123`, `HAM-456` (ticket ID) | Split Existing Ticket |
| Free text (idea, feature description) | Split New Idea |

---

### Mode A: Split Existing Ticket

**1. Fetch ticket from Linear:**

```
ticket = mcp__linear__get_issue({ id: "ENG-123" })
```

Extract:
- Title
- Description
- Acceptance criteria
- Labels
- Project (for subtask assignment)

**2. Explore codebase to understand scope:**

```
mcp__morph-mcp__warpgrep_codebase_search({
  search_string: "Find implementation scope for: ${TITLE} - ${DESCRIPTION}",
  repo_path: "${CWD}"
})
```

**3. Analyze and propose split:**

Break down by:
- **Logical layers**: Schema → API → UI → Tests
- **Independent features**: Each can be merged separately
- **Risk isolation**: High-risk changes in separate tickets
- **Review size**: Each ticket = 1-2 day work max

**4. Present proposed split:**

```markdown
## Proposed Split for ENG-123

**Original:** Build user authentication system
**Complexity:** High → Split into 4 tickets

### Ticket 1: Database Schema
- Add User, Session, Role tables
- Migration scripts
- **Estimate:** 0.5 day
- **Dependencies:** None

### Ticket 2: Auth API
- Login/logout endpoints
- Session management
- JWT token handling
- **Estimate:** 1 day
- **Dependencies:** Ticket 1

### Ticket 3: Auth Middleware
- Route protection
- Permission checks
- **Estimate:** 0.5 day
- **Dependencies:** Ticket 2

### Ticket 4: Auth UI
- Login form component
- Protected route wrapper
- User context provider
- **Estimate:** 1 day
- **Dependencies:** Ticket 2

**Total:** 3 days (parallelizable to 2 days)

Proceed? [Y/n/modify]
```

**5. Create subtasks in Linear:**

```
# Create as sub-issues of original ticket
for each SUBTASK:
  mcp__linear__create_issue({
    title: "[${TICKET_ID}] ${SUBTASK_TITLE}",
    team: "${TEAM}",
    description: "${SUBTASK_DESCRIPTION}\n\n---\n\nParent: ${TICKET_ID}",
    parentId: "${ORIGINAL_TICKET_ID}",
    assignee: "me",
    state: "Todo",
    labels: ["${TYPE_LABEL}"]
  })
```

**6. Update original ticket:**

```
mcp__linear__update_issue({
  id: "${TICKET_ID}",
  description: "${ORIGINAL_DESC}\n\n---\n\n## Subtasks\n${SUBTASK_TABLE}"
})
```

---

### Mode B: Split New Idea

**1. Analyze the idea:**

Determine:
- **Type**: Feature / System / Refactor
- **Scope**: How big is this really?
- **Components**: What logical parts does it have?

**2. Explore codebase:**

```
mcp__morph-mcp__warpgrep_codebase_search({
  search_string: "${IDEA_DESCRIPTION}",
  repo_path: "${CWD}"
})
```

**3. Design the split:**

Consider:
- What can be built independently?
- What has dependencies?
- What's the MVP vs nice-to-have?
- What's high-risk vs safe?

**4. Present proposed tickets:**

```markdown
## Proposed Tickets for: "${IDEA}"

**Analysis:** This is a large feature that should be split into 5 tickets

### Epic: User Authentication System

#### Ticket 1: [Feat] Database schema for auth
- **Scope:** Low
- **Description:** Add User, Session, Permission tables
- **Files:** prisma/schema.prisma, migrations/
- **Dependencies:** None (start here)

#### Ticket 2: [Feat] Auth API endpoints
- **Scope:** Medium
- **Description:** Login, logout, refresh token endpoints
- **Files:** server/routers/auth.ts, server/services/auth.service.ts
- **Dependencies:** Ticket 1

#### Ticket 3: [Feat] Auth middleware
- **Scope:** Low
- **Description:** Route protection, permission checks
- **Files:** server/middleware/auth.ts
- **Dependencies:** Ticket 2

#### Ticket 4: [Feat] Login UI
- **Scope:** Medium
- **Description:** Login form, error handling, redirect
- **Files:** components/auth/, pages/login.tsx
- **Dependencies:** Ticket 2

#### Ticket 5: [Feat] Protected routes
- **Scope:** Low
- **Description:** HOC for protected pages, user context
- **Files:** components/auth/ProtectedRoute.tsx
- **Dependencies:** Ticket 3, 4

**Dependency Graph:**
```
1 (Schema)
└─→ 2 (API)
    ├─→ 3 (Middleware) ─→ 5 (Protected Routes)
    └─→ 4 (UI) ─────────┘
```

**Recommended Order:** 1 → 2 → 3 & 4 (parallel) → 5

Proceed? [Y/n/modify]
```

**5. Create tickets in Linear:**

```
# Create parent ticket (epic) first
EPIC_ID = mcp__linear__create_issue({
  title: "[Epic] ${IDEA_TITLE}",
  team: "${TEAM}",
  description: "${EPIC_DESCRIPTION}",
  labels: ["epic"]
})

# Create child tickets
for each TICKET:
  mcp__linear__create_issue({
    title: "${TICKET_TITLE}",
    team: "${TEAM}",
    description: "${TICKET_DESC}",
    parentId: "${EPIC_ID}",
    assignee: "me",
    state: "Todo",
    labels: ["${TYPE_LABEL}"]
  })
```

---

## Split Criteria

**When to split:**
- Ticket touches >3 logical layers (schema, API, UI, tests)
- Estimate >2 days of work
- >15 files would be modified
- Multiple independent features bundled together
- High-risk and low-risk changes mixed

**How to split:**
| Pattern | Split Strategy |
|---------|---------------|
| Full-stack feature | Schema → API → UI → Tests |
| Multi-app change | By app (web, queue, worker) |
| Large refactor | By module/domain |
| New system | MVP → Enhancements → Polish |

**Good subtask characteristics:**
- Can be reviewed independently
- Has clear acceptance criteria
- 0.5-2 days of work
- Minimal dependencies
- Clear scope boundary

---

## Output

```markdown
# ✅ Task Split Complete

## Original
- **{TICKET_ID}** - {Title}
- **Complexity:** High → Split into {N} subtasks

## Created Tickets

| # | Ticket | Title | Scope | Dependencies |
|---|--------|-------|-------|--------------|
| 1 | ENG-124 | Database schema | Low | None |
| 2 | ENG-125 | Auth API | Medium | ENG-124 |
| 3 | ENG-126 | Auth middleware | Low | ENG-125 |
| 4 | ENG-127 | Login UI | Medium | ENG-125 |
| 5 | ENG-128 | Protected routes | Low | ENG-126, 127 |

## Dependency Graph
{Visual representation}

## Recommended Order
1. ENG-124 (start here)
2. ENG-125
3. ENG-126 & ENG-127 (parallel)
4. ENG-128

## Next Steps
- `/start-ticket ENG-124` to begin
- Or `/start-ticket ENG-124 ENG-125 ENG-126` for parallel work
```

---

## Notes

- **Creates subtasks** as child issues in Linear
- **Preserves context** - links back to parent ticket
- **Dependency tracking** - identifies blocked-by relationships
- **Scope estimation** - Low/Medium/High based on file count
- **Parallelization** - identifies what can be worked on simultaneously
- **Uses WarpGrep** to understand codebase before splitting
- **Integrates with `/start-ticket`** for implementation
- **Called by `/spec-ticket`** when scope is too large

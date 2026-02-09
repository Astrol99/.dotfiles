# Claude Commands

Custom commands for streamlined development workflow. All commands use natural language arguments - no rigid flags needed.

---

## Quick Reference

| Command | Purpose | Example |
|---------|---------|---------|
| `/start-ticket` | Start work on tickets | `/start-ticket ENG-123` |
| `/blitz-tickets` | High-volume parallel plan → execute | `/blitz-tickets ENG-1 ENG-2 ENG-3` |
| `/create-pr` | Create PR with smart title | `/create-pr ready` |
| `/code-check` | Type check + lint + tests | `/code-check` |
| `/quality-check` | Deep code analysis | `/quality-check` |
| `/loop-review` | Codex review loop | `/loop-review` |
| `/review-pr-comments` | Fetch PR feedback | `/review-pr-comments 89` |
| `/fix-pr-comments` | Fix and resolve comments | `/fix-pr-comments 1 3` |
| `/start-pr-review` | Auto-fix all PRs | `/start-pr-review` |
| `/split-pr` | Split large PR | `/split-pr 123` |
| `/spec-ticket` | Spec out or create ticket | `/spec-ticket ENG-123` |
| `/sync-main` | Sync with main branch | `/sync-main` |
| `/setup-worktree` | Create isolated worktree | `/setup-worktree ENG-123` |
| `/make-dario-happy` | Run all quality checks | `/make-dario-happy` |

---

## Command Flows

### `/start-ticket`

Start work on tickets - single or multiple in parallel.

```
No args      → Show ticket summary (your assigned tickets)
ENG-123      → Plan and implement in current workspace
ENG-123 ENG-124 ENG-125 → Parallel agents via worktrees
```

**Flow:**
```
/start-ticket ENG-123
    ↓
Fetch ticket from Linear (with relations)
    ↓
Explore codebase with WarpGrep
    ↓
Create implementation plan
    ↓
Implement (using edit_file)
    ↓
/code-check
    ↓
/loop-review
    ↓
/create-pr
```

**Multiple tickets:** Creates worktrees, spawns parallel agents, each creates draft PR.

---

### `/blitz-tickets`

High-volume parallel planning → sequential execution. Own branch + PR per ticket, no worktrees.

```
ENG-1 ENG-2 ENG-3 ENG-4 ENG-5 → Blitz 5 tickets
todo                            → Blitz all unstarted tickets
ENG-1 ENG-2 --dry-run           → Plan only, don't execute
```

**Flow:**
```
/blitz-tickets ENG-1 ENG-2 ENG-3
    ↓
Fetch all tickets from Linear
    ↓
5 parallel planning agents (race!)
    ↓
As each plan finishes: checkout -b → implement → push → draft PR
    ↓
Summary: N branches, N draft PRs, CI running on all
```

**vs `/start-ticket` multiple:** No worktrees (just branch switching), parallel planning instead of parallel execution. Zero disk overhead, faster setup.

---

### `/create-pr`

Create PR with smart title generation and auto-assignment.

```
/create-pr                → Draft PR (default)
/create-pr ready          → Ready for review
/create-pr 1/3 schema     → Part 1 of 3, subtitle "schema"
/create-pr from 456       → Split from PR #456
/create-pr needs 201      → Depends on PR #201
/create-pr base feat/X    → Custom base branch
```

**PR Title Format:**
```
[Feat] [ENG-123] Add user authentication
[Bug Fix] [ENG-456] Fix timeout issue
[Feat] [ENG-124] Chart explanations 1/5: Types and definitions
```

**Auto-detects:**
- PR type from branch name (feat/, fix/, refactor/, chore/)
- Subtasks from Linear parent → adds N/M part info
- Generates summary from diff

---

### `/code-check`

Pre-PR verification - type check, lint, and tests.

```
/code-check           → Full check
/code-check quick     → Skip tests
/code-check path/     → Specific directory
```

**Flow:**
```
/code-check
    ↓
npm run type-check (parallel)
npm run lint        (parallel)
    ↓
npm run test (unless quick mode)
    ↓
Report: ✅ All passed or ❌ N issues
```

---

### `/quality-check`

Deep code analysis - patterns, security, performance, docs.

```
/quality-check            → Full analysis
/quality-check security   → Security focus
/quality-check path/      → Specific directory
```

**Analyzes:**
- Code patterns and anti-patterns
- Security vulnerabilities (OWASP)
- Performance issues
- Documentation gaps
- Test coverage

---

### `/loop-review`

Codex review and fix loop - alternates between review and fixes.

```
/loop-review                    → Default 4 iterations
/loop-review --iterations=2     → Custom iteration count
/loop-review --path=.worktrees/X → Specific path
```

**Flow:**
```
/loop-review
    ↓
Codex reviews code
    ↓
Claude fixes issues
    ↓
Repeat until clean or max iterations
    ↓
Report: Clean on iteration N or issues remaining
```

---

### `/review-pr-comments`

Fetch and categorize PR feedback.

```
/review-pr-comments       → Show summary for all your PRs
/review-pr-comments 89    → Review specific PR
/review-pr-comments latest → Most recent PR
```

**Categorizes:**
- 🔴 High: Security, bugs, human comments
- 🟡 Medium: Code quality, bot suggestions
- 🟢 Nice to Have: Style, docs, nits

**Recommends action:** FIX, REPLY, ASK, or SKIP

---

### `/fix-pr-comments`

Fix specific comments and resolve threads.

```
/fix-pr-comments 1 3      → Fix comments #1 and #3
/fix-pr-comments all      → Fix all recommended
/fix-pr-comments high     → Fix high priority only
```

**Flow:**
```
/fix-pr-comments 1 3
    ↓
Read file context for each comment
    ↓
Apply fix (edit_file)
    ↓
/code-check --quick
    ↓
Commit and push
    ↓
Resolve threads via GitHub API
```

---

### `/start-pr-review`

Auto-fix all PRs with feedback using parallel agents.

```
/start-pr-review          → Fix all PRs with feedback
/start-pr-review high     → Only high priority
/start-pr-review 89       → Fix specific PR
```

**Flow:**
```
/start-pr-review
    ↓
/review-pr-comments (for each PR)
    ↓
/setup-worktree (for each PR - sequential)
    ↓
Parallel agents call /fix-pr-comments all
    ↓
/loop-review (optional)
    ↓
Cleanup worktrees
```

---

### `/split-pr`

Split large PR into smaller, reviewable PRs.

```
/split-pr                 → Split current branch's PR
/split-pr 123             → Split PR #123
/split-pr by directory    → Split by top-level directory
/split-pr by commit       → Split by commit
/split-pr dry-run         → Analyze only
```

**Flow:**
```
/split-pr 123
    ↓
Analyze PR (files, commits, dependencies)
    ↓
Propose split groups
    ↓
Validate each group compiles (parallel agents)
    ↓
Create PRs (parallel agents, /create-pr)
    ↓
Migrate unresolved comments
    ↓
Close original PR
```

---

### `/spec-ticket`

Spec out existing ticket or create new from description.

```
/spec-ticket ENG-123              → Spec existing ticket
/spec-ticket Fix the timeout...   → Create new ticket
/spec-ticket pr 456               → Create from PR
```

**Flow:**
```
/spec-ticket ENG-123
    ↓
Fetch ticket from Linear
    ↓
Explore codebase with WarpGrep
    ↓
Identify affected files
    ↓
Generate engineering spec
    ↓
Update Linear ticket
```

---

### `/sync-main`

Sync feature branch with latest main.

```
/sync-main                → Merge main (default)
/sync-main rebase         → Rebase onto main
```

**Flow:**
```
/sync-main
    ↓
git fetch origin main
    ↓
git merge origin/main (or rebase)
    ↓
Handle conflicts if any
    ↓
/code-check --quick
```

---

### `/setup-worktree`

Create isolated worktree for parallel work.

```
/setup-worktree ENG-123   → From ticket ID
/setup-worktree pr-89     → From PR number
```

**Creates:** `.worktrees/ENG-123/` with correct branch

---

### `/make-dario-happy`

Run all quality checks before PR review.

```
/make-dario-happy         → Full check (loop-review + code-check + quality-check)
/make-dario-happy quick   → Skip loop-review
```

**Flow:**
```
/make-dario-happy
    ↓
/loop-review --iterations=2 (unless quick)
    ↓
/code-check
    ↓
/quality-check
    ↓
Output: "Dario Will Be Happy" or "Dario Might Not Be Happy"
```

---

## Conventions

### PR Title Format
```
[Type] [TICKET] Title
[Type] [TICKET] Parent Title N/M: Subtask Title
```

Types: `Feat`, `Bug Fix`, `Refactor`, `Chore`

### Natural Arguments

Commands use natural language - Claude interprets intent:
- `ready` → not draft
- `quick` → skip slow steps
- `high` → priority filter
- `1/3 schema` → part info

### Parallel Agents

Multiple tickets/PRs spawn parallel agents in isolated worktrees:
```
/start-ticket ENG-1 ENG-2 ENG-3
    ↓
Agent 1 → .worktrees/ENG-1/
Agent 2 → .worktrees/ENG-2/
Agent 3 → .worktrees/ENG-3/
```

### Worktrees

Isolated git worktrees at `.worktrees/`:
- Each has its own branch
- Enables parallel work without conflicts
- Cleaned up after completion

---

## Typical Workflows

### New Feature
```
/start-ticket ENG-123
# ... implement ...
/make-dario-happy
/create-pr
```

### Fix PR Feedback
```
/review-pr-comments 89
/fix-pr-comments 1 3 5
```

### Batch PR Review
```
/start-pr-review
```

### Large PR
```
/split-pr dry-run
/split-pr
```

### High-Volume Blitz
```
/blitz-tickets ENG-1 ENG-2 ENG-3 ENG-4 ENG-5
# Plans in parallel, executes as each finishes
# Selective commits on single branch, CI verifies
```

### Spec First
```
/spec-ticket ENG-123
# ... review spec ...
/start-ticket ENG-123
```

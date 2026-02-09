---
description: Start tickets on Claude Code Web (async, runs without laptop)
argument-hint: <TICKET-IDs or keywords>
scope: global
---

# Start Ticket (Web)

Launch tickets as Claude Code Web sessions that run async on Anthropic's servers.
Pre-fetches all MCP data locally since web sessions don't support MCPs yet.

**Arguments:** $ARGUMENTS

**Formats:**
- Single: `ENG-123` → One web session
- Multiple: `ENG-123 ENG-124 ENG-125` → Multiple parallel web sessions
- Keywords: `todo`, `not-started` → Fetch matching tickets, then launch

---

## Instructions

### Phase 1: Pre-fetch All MCP Data (Local)

Fetch everything the web agent will need. MCP tools are only available locally.

**All data fetching is done via Bash — Claude does NOT process any ticket data as tokens.**

**Requires:** `LINEAR_API_KEY` environment variable (create at Linear Settings > API).

**For each ticket ID, run in parallel via Bash:**

**1. Fetch Linear ticket data (curl → file):**
```bash
curl -s https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d '{"query":"{ issue(id: \"TICKET_ID\") { identifier title description url priorityLabel state { name } labels { nodes { name } } assignee { name } parent { id identifier title } children { nodes { identifier title state { name } } } relations { nodes { type relatedIssue { identifier title } } } } }"}' \
  -o ${SCRATCHPAD}/linear-{TICKET_ID}.txt
```

**2. Check for Jam links and fetch (Bash grep + MCP only if needed):**
```bash
grep -oP 'jam\.dev/\K[a-zA-Z0-9]+' ${SCRATCHPAD}/linear-{TICKET_ID}.txt
```
If Jam IDs found, use Jam MCP to fetch bug report data and save to `${SCRATCHPAD}/jam-{TICKET_ID}.txt`.
Jam links are rare — most tickets skip this step entirely.

**3. Capture git identity + check existing PRs (Bash):**
```bash
GIT_USER_NAME=$(git config user.name)
GIT_USER_EMAIL=$(git config user.email)
gh pr list --json headRefName,number,url -q '.[] | select(.headRefName | contains("TICKET_ID"))'
```
If PR already exists, warn the user and skip.

---

### Phase 2: Assemble Prompt Files

Assemble prompt files mechanically — do NOT read or process the MCP output. Write raw responses directly to disk.

**For each ticket, use Bash to build `${SCRATCHPAD}/web-ticket-{TICKET_ID}.md`:**

Phase 1 already saved data to:
- `${SCRATCHPAD}/linear-{TICKET_ID}.txt` — raw JSON from Linear API
- `${SCRATCHPAD}/jam-{TICKET_ID}.txt` — raw Jam MCP output (if Jam links found)

Then concatenate with a static instructions header using Bash:

```bash
cat > ${SCRATCHPAD}/web-ticket-{TICKET_ID}.md << 'HEADER'
Implement the following Linear ticket.

## Linear Ticket
HEADER

cat ${SCRATCHPAD}/linear-{TICKET_ID}.txt >> ${SCRATCHPAD}/web-ticket-{TICKET_ID}.md

# Append Jam data if exists
if [ -f ${SCRATCHPAD}/jam-{TICKET_ID}.txt ]; then
  echo -e "\n## Bug Report (from Jam)\n" >> ${SCRATCHPAD}/web-ticket-{TICKET_ID}.md
  cat ${SCRATCHPAD}/jam-{TICKET_ID}.txt >> ${SCRATCHPAD}/web-ticket-{TICKET_ID}.md
fi

cat >> ${SCRATCHPAD}/web-ticket-{TICKET_ID}.md << 'FOOTER'

## Git Author

IMPORTANT: All commits and branches must be authored by the repo owner, not by Claude.
Run this BEFORE making any commits:
```
git config user.name "{GIT_USER_NAME}"
git config user.email "{GIT_USER_EMAIL}"
```

## Instructions

1. Configure git author (see above).
2. Use the branch you are already on. Claude Code Web automatically creates a `claude/...` branch — do NOT create a new branch. Run `git branch --show-current` to confirm.
3. Implement the ticket. Follow existing code patterns.
4. Verify: run type checking and linting. Fix errors before proceeding.
5. Commit: `git add -A && git commit -m "[{TICKET_ID}] {title}"`
6. Push to the current branch: `git push`
7. Output: files changed, branch name, any decisions made. Do NOT create a PR — `gh` CLI is not available on this environment.
FOOTER
```

This avoids Claude processing the MCP output as tokens — it's just file I/O.

---

### Phase 3: Launch Web Sessions

**For each ticket, launch a web session via `claude --remote`:**

**`claude --remote` requires a TTY which the Bash tool doesn't provide.** Use a wrapper script with `script` to provide a pseudo-TTY:

1. Write a launcher script to `${SCRATCHPAD}/launch-{TICKET_ID}.sh`:
```bash
#!/bin/bash
PROMPT="$(cat ${SCRATCHPAD}/web-ticket-{TICKET_ID}.md)"
claude --remote "$PROMPT"
```

2. Make it executable and run via `script`:
```bash
chmod +x ${SCRATCHPAD}/launch-{TICKET_ID}.sh
script -q /dev/null ${SCRATCHPAD}/launch-{TICKET_ID}.sh 2>&1
```

**Important:** Do NOT inline `$(cat ...)` directly in the `script` command — variable expansion breaks through nested quoting. Always use a separate script file.

Write ALL launcher scripts first, then launch them **in parallel** using multiple Bash tool calls in a single message (one per ticket). Use `run_in_background: true` for each so they execute concurrently.

After all launches complete, read their output to capture the **session URLs** (e.g. `https://claude.ai/code/...`) for the report.

---

### Phase 4: Report & Notify

**Output summary:**

```markdown
# Web Tasks Launched

| Ticket | Title | Part | Session URL |
|--------|-------|------|-------------|
| ENG-123 | Fix timeout | - | https://claude.ai/code/{session_id_1} |
| ENG-124 | Add service | 2/5 | https://claude.ai/code/{session_id_2} |
| ENG-125 | Add endpoints | 3/5 | https://claude.ai/code/{session_id_3} |

## Pre-fetched Context
- Linear ticket data (title, description, criteria, relations)
- Jam bug reports: {N found / none}

## Monitor
- Run `/tasks` to check status of all web sessions
- Visit https://claude.ai/code to see sessions
- Use `claude --teleport` to pull any session back locally

## When Complete
- Create PRs locally: `gh pr create --draft` for each pushed branch
- Or run `/create-pr` from each branch
- Run `/start-pr-review` if needed
- Use `claude --teleport <session-id>` to continue locally
```

**Send notification:**
```bash
/Users/david/.claude/notify.sh "Claude Code" "Web tasks launched for {TICKET_IDS}. Check /tasks for status."
```

---

## Execution Flow

```
/start-ticket-web ENG-123 ENG-124 ENG-125

Phase 1: Pre-fetch (Local — uses MCPs)
├─→ Linear API: ticket data + relations (parallel per ticket)
├─→ Jam API: bug reports if linked (parallel per jam)
└─→ Git identity: user.name + user.email

Phase 2: Build Prompts (Local)
├─→ Write web-ticket-ENG-123.md  (self-contained)
├─→ Write web-ticket-ENG-124.md  (self-contained)
└─→ Write web-ticket-ENG-125.md  (self-contained)

Phase 3: Launch (Parallel — all at once)
├─→ claude --remote < ENG-123 prompt → Web Session 1 ─┐
├─→ claude --remote < ENG-124 prompt → Web Session 2 ─┤ concurrent
└─→ claude --remote < ENG-125 prompt → Web Session 3 ─┘

Phase 4: Report
└─→ Summary table + notify

All sessions now run in parallel on Anthropic's servers.
Close your laptop.
```

---

## Keyword Arguments

When arguments are keywords instead of ticket IDs:

**`todo` or `not-started`:**
```
mcp__linear__list_issues({ assignee: "me", state: "todo" })
```
Then display the list and ask which tickets to launch on web.

**`in-progress` or `started`:**
```
mcp__linear__list_issues({ assignee: "me", state: "started" })
```
Show list, ask which to launch.

---

## PR Title Format

Same as `/start-ticket`:

**Standard:** `[Type] [TICKET_ID] Title`
**Subtask:** `[Type] [TICKET_ID] Parent Title N/M: Subtask Title`

| Branch/Title Pattern | Type |
|---------------------|------|
| `fix/`, `bugfix/`, contains "fix" | Bug Fix |
| `feat/`, `feature/`, contains "add", "implement" | Feat |
| `refactor/` | Refactor |
| `chore/` | Chore |
| Other | Feat |

---

## Differences from `/start-ticket`

| Aspect | `/start-ticket` | `/start-ticket-web` |
|--------|-----------------|---------------------|
| Execution | Local (your machine) | Anthropic's servers |
| MCP access | Full (Linear, Jam, etc.) | None — pre-fetched |
| Laptop needed | Yes, entire duration | Only for launch |
| Multiple tickets | Worktrees + local agents | Independent web sessions |
| Code review | `/loop-review` locally | Review PRs after |
| Self-review | Built-in | Not available on web |
| Worktrees | Yes (`.worktrees/`) | No (web clones repo) |
| Best for | Complex tickets needing review | Batch of straightforward tickets |

---

## Notes

- **No MCP on web** — ALL Linear/Jam/codebase context must be pre-fetched and baked into the prompt
- **Prompts must be self-contained** — the web agent has zero context beyond what's in the prompt
- **GitHub required** — repo must be on GitHub with Claude Code app installed
- **Web sessions are independent** — each gets a fresh repo clone
- **Branches created by web agents** — they create and push their own branches
- **Monitor with `/tasks`** or visit claude.ai/code
- **Teleport back** with `claude --teleport` to continue any session locally
- **Auto-detects subtasks** and includes part info (N/M) from Linear parent
- **Jam integration** — extracts console errors, failed requests, and repro steps locally before launch
- **Prompt size** — keep codebase context focused; include only the most relevant files to avoid prompt bloat
- **Testing rules** — include testing instructions in prompt when modifying `*.service.ts` or `*.utils.ts`
- Single ticket = one web session
- Multiple tickets = multiple parallel web sessions (all async)

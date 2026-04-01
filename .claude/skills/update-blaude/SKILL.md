---
name: update-blaude
description: Audit and update blaude's Claude Code environment variable passthrough list, managed settings, and file/path auto-mounts against official documentation. Use when checking if blaude is up-to-date with the latest Claude Code env vars, when a new Claude Code version is released, or when asked to sync/audit/update blaude's env var list. Fetches official docs, diffs against current script, checks if new vars need file mounts, and outputs prioritized recommendations.
---

# Update blaude

Audit the `blaude` script against official Claude Code documentation and recommend updates.

## Workflow

### 1. Gather current state

Run the extraction script and read the reference files:

```bash
bash .claude/skills/update-blaude/scripts/extract-vars.sh blaude
```

Then read:
- [references/hardcoded-vars.md](references/hardcoded-vars.md) — vars that must NOT be added to passthrough
- [references/passthrough-categories.md](references/passthrough-categories.md) — array categories and intentional non-official vars
- [references/auto-mount-vars.md](references/auto-mount-vars.md) — vars that need file/dir bind-mounts

### 2. Fetch official documentation

The env-vars page is long and WebFetch often truncates it. Use this multi-fetch strategy:

1. Fetch https://code.claude.com/docs/en/env-vars.md (the `.md` URL returns raw markdown, easier to parse)
2. Note the LAST variable in the output — the page likely truncated there
3. Fetch again asking specifically for vars AFTER that last variable
4. Repeat until no new vars appear

Optionally also fetch https://code.claude.com/docs/en/settings for managed settings overlap, but the env-vars page is the primary authoritative source.

### 3. Diff and classify

For each official var, classify as one of:

| Classification | Action |
|---|---|
| Already in passthrough | No action |
| Already hardcoded | No action (see [hardcoded-vars.md](references/hardcoded-vars.md)) |
| Missing from blaude | Recommend adding — assign to correct category per [passthrough-categories.md](references/passthrough-categories.md) |
| Linux-irrelevant (e.g. `CLAUDE_CODE_USE_POWERSHELL_TOOL`) | Skip |

For each blaude var NOT in official docs, classify as:

| Classification | Action |
|---|---|
| Intentional extra (see [passthrough-categories.md](references/passthrough-categories.md)) | No action |
| Possibly deprecated/renamed | Flag for user review |

### 4. Check for mount requirements

For each new var recommended for addition, check if it points to a file, directory, or socket (see [auto-mount-vars.md](references/auto-mount-vars.md) for patterns). If so, passing through the env var alone is insufficient — the path must also be bind-mounted into the sandbox.

Flag these in the report with mount instructions.

### 5. Output report

```markdown
## Recommended additions

| Variable | Purpose | Category | Priority |
|---|---|---|---|
| ... | ... | ... | High/Medium/Low |

## Possibly deprecated (in blaude, not in docs)

| Variable | Current category | Notes |
|---|---|---|
| ... | ... | ... |

## Needs file mount (not just passthrough)

| Variable | Path type | Mount mode | Notes |
|---|---|---|---|
| ... | file/dir/socket | ro-bind/bind | ... |

## Already hardcoded (confirmed)

| Variable | Still in docs? |
|---|---|
| ... | Yes/No |
```

**Priority**: High = security/auth/proxy/connectivity. Medium = model config, execution. Low = UI/cosmetic.

If blaude is fully up-to-date (no missing vars), say so clearly at the top of the report. Still include the "Possibly deprecated" and "Already hardcoded" sections for completeness.

### 6. Apply changes (if user approves)

Add approved vars to the `claude_env_vars` array in the correct category section. Match the existing formatting style (space-separated on lines, grouped under comment headers).

For vars that need mounts, add both the passthrough AND the bind-mount logic. Follow the existing pattern in blaude (e.g., the `CLAUDE_ENV_FILE` auto-mount block) — check if the var is set and the path exists before mounting.

---
name: update-blaude
description: Audit and update blaude's Claude Code environment variable passthrough list, managed settings, and file/path auto-mounts against official documentation and changelog. Use when checking if blaude is up-to-date with the latest Claude Code release, when a new version is released, or when asked to sync/audit/update blaude. Fetches the env-vars page and changelog, diffs against the current script, identifies new env vars, managed settings, sandbox-relevant changes, and deprecations, then outputs prioritized recommendations.
---

# Update blaude

Audit the `blaude` script against official Claude Code documentation and changelog, then recommend updates.

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
- [references/changelog-analysis.md](references/changelog-analysis.md) — what to look for in the changelog

### 2. Fetch official documentation

Fetch both the env-vars page and the changelog. These can be fetched in parallel.

#### 2a. Env-vars page

The env-vars page is long and WebFetch often truncates it. Use this multi-fetch strategy:

1. Fetch https://code.claude.com/docs/en/env-vars.md (the `.md` URL returns raw markdown, easier to parse)
2. Note the LAST variable in the output — the page likely truncated there
3. Fetch again asking specifically for vars AFTER that last variable
4. Repeat until no new vars appear

#### 2b. Changelog

Fetch https://code.claude.com/docs/en/changelog.md and extract (see [changelog-analysis.md](references/changelog-analysis.md) for detailed patterns):

1. **New env vars** — entries like "Added `VAR_NAME` env var..." Cross-reference with env-vars page results.
2. **Managed settings changes** — new settings, setting directories, or policy changes.
3. **Sandbox-relevant changes** — new tools, hook events, file paths, protocol handlers, plugin/MCP changes.
4. **Deprecations and removals** — vars or features removed that blaude may still reference.
5. **Security changes** — credential scrubbing, permission hardening, auth flow changes.

The changelog is the `.md` URL and returns raw markdown. It is long — focus the prompt on extracting items relevant to blaude (env vars, settings, sandbox, filesystem, security). Note the latest version number for the audit report.

#### 2c. Settings page (optional)

Fetch https://code.claude.com/docs/en/settings for managed settings overlap, but the env-vars page is the primary authoritative source.

### 3. Diff and classify

blaude auto-passes any host env var matching `ANTHROPIC_*` or `CLAUDE_*` via prefix match in the passthrough loop. The `claude_env_vars` array only covers non-prefix vars (third-party LLM keys, cloud auth, OTEL/MCP standards, `VERTEX_REGION_CLAUDE_*`, and bare names like `CLAUDECODE`, `AI_AGENT`, `DEBUG`, etc.).

For each official var, classify as one of:

| Classification | Action |
|---|---|
| Matches `ANTHROPIC_*` or `CLAUDE_*` prefix | No action — auto-passed |
| Already in `claude_env_vars` (non-prefix) | No action |
| Already hardcoded | No action (see [hardcoded-vars.md](references/hardcoded-vars.md)) |
| Missing from blaude AND not prefix-covered | Recommend adding — assign to correct category per [passthrough-categories.md](references/passthrough-categories.md) |
| Linux-irrelevant (e.g. `CLAUDE_CODE_USE_POWERSHELL_TOOL`) | Skip |
| Set BY Claude Code in subprocesses (e.g. `CLAUDE_PROJECT_DIR`, `CLAUDECODE`) | Skip if not also consumed by claude itself |

Since `ANTHROPIC_*`/`CLAUDE_*` coverage is automatic, the diff should focus on:
- **Hardcoded interactions**: any new official `CLAUDE_*` var that blocks bypass-permissions, force-scrubs env, or otherwise needs to land in `_hardcoded_env_vars` / `_hardcoded_unsetenv_vars` instead of plain passthrough.
- **Auto-mount needs**: any new `CLAUDE_*` var that points to a file/dir/socket — the prefix passes the value, but the mount loop still needs a separate entry (see [auto-mount-vars.md](references/auto-mount-vars.md)).
- **Non-prefix additions**: new official vars *not* starting with `ANTHROPIC_` or `CLAUDE_` (e.g. new `OTEL_*`, `MCP_*`, `MAX_*`, `DISABLE_*` toggles, third-party cloud namespaces).

For each blaude var NOT in official docs, classify as:

| Classification | Action |
|---|---|
| Intentional extra (see [passthrough-categories.md](references/passthrough-categories.md)) | No action |
| Possibly deprecated/renamed | Flag for user review |

### 4. Check for mount requirements

For each new var recommended for addition, check if it points to a file, directory, or socket (see [auto-mount-vars.md](references/auto-mount-vars.md) for patterns). If so, passing through the env var alone is insufficient — the path must also be bind-mounted into the sandbox.

Flag these in the report with mount instructions.

### 5. Output report

Start with a summary line: "Audited against Claude Code v{version} (changelog) and env-vars page as of {date}."

```markdown
## Recommended additions

| Variable | Purpose | Category | Priority | Source |
|---|---|---|---|---|
| ... | ... | ... | High/Medium/Low | env-vars/changelog v{X} |

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

## Sandbox-relevant changelog items (non-env-var)

| Version | Change | Impact on blaude |
|---|---|---|
| ... | ... | Action needed / informational |
```

**Priority**: High = security/auth/proxy/connectivity. Medium = model config, execution. Low = UI/cosmetic.

If blaude is fully up-to-date (no missing vars), say so clearly at the top of the report. Still include the other sections for completeness. The "Sandbox-relevant changelog items" section captures non-env-var changes from the changelog that may require blaude updates (new managed settings, new tools, filesystem changes, etc.).

### 6. Apply changes (if user approves)

For new vars that match `ANTHROPIC_*` or `CLAUDE_*`: no change is needed unless the var needs special handling (hardcode, deny, or mount).

For new non-prefix vars: add to `claude_env_vars` in the correct category section. Match the existing formatting style (space-separated on lines, grouped under comment headers).

For vars that need mounts (even prefix-covered ones), add the bind-mount logic. Follow the existing pattern in blaude (e.g., the `CLAUDE_ENV_FILE` auto-mount block) — check if the var is set and the path exists before mounting.

For vars that need to be hardcoded or force-unset (e.g., new permission-mode blockers), add to `_hardcoded_env_vars` (with `=VALUE`) or `_hardcoded_unsetenv_vars` (bare name). The passthrough loop's deny-set will then protect them from the prefix match.

### 7. Update README.md and CLAUDE.md

After applying changes to the blaude script, update documentation to stay in sync:

#### README.md — Environment Variables table

The `## Environment Variables` section in README.md contains a summary table. The first two rows (`Anthropic namespace (prefix-matched)` and `Claude Code namespace (prefix-matched)`) cover everything under those prefixes via wildcards — no edit needed for routine `CLAUDE_CODE_*` / `ANTHROPIC_*` additions. Refresh the examples in those rows only when a notably new sub-pattern appears (e.g. a new `CLAUDE_CODE_NEWFEATURE_*` family).

For non-prefix additions:

1. Find the matching category row in the table (e.g., `| **Other LLM APIs** | ... |`)
2. Add/remove the var name from the appropriate row
3. If a new category was added to blaude, add a new row to the table
4. Keep table entries concise

#### CLAUDE.md — Environment Variable Passthrough section

The `## Environment Variable Passthrough` section in CLAUDE.md describes the prefix-matching behavior and lists:
- **Hardcoded vars**: Update if a new var is hardcoded via `--setenv` in the Claude Code config block
- **Hardcoded unsets**: Update if a new var must be force-unset
- **Auto-mounted file/path vars**: Update the list if a new var triggers a bind-mount

The "Glob patterns" bullet already covers `ANTHROPIC_*` and `CLAUDE_*` — no edit needed for routine prefix-covered additions.

Only update these docs for changes that were actually applied to the blaude script — do not update docs for recommendations the user declined.

#### Scope of doc updates

- Do NOT rewrite or restructure docs beyond the specific sections affected by the change
- Match the existing formatting style in each file
- For README.md, keep the env var table concise (wildcards over exhaustive lists)
- For CLAUDE.md, keep the auto-mount list in the same inline format

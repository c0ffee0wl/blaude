---
name: update-blaude
description: Audit and update blaude's Claude Code environment variable passthrough list, managed settings, and file/path auto-mounts against official documentation and changelog. Use when checking if blaude is up-to-date with the latest Claude Code release, when a new version is released, or when asked to sync/audit/update blaude. Fetches the env-vars page and changelog, diffs against the current script, identifies new env vars, managed settings, sandbox-relevant changes, and deprecations, then outputs prioritized recommendations.
---

# Update blaude

Audit the `blaude` script against official Claude Code documentation and changelog, then recommend updates.

## Workflow

### 1. Gather current state

Run the extraction script once, keeping its output for the diffs in step 2, and read the reference files:

```bash
bash .claude/skills/update-blaude/scripts/extract-vars.sh blaude | tee "$SCRATCHPAD/blaude-extract.txt"
```

Then read:
- [references/hardcoded-vars.md](references/hardcoded-vars.md) — vars that must NOT be added to passthrough
- [references/passthrough-categories.md](references/passthrough-categories.md) — array categories and intentional non-official vars
- [references/auto-mount-vars.md](references/auto-mount-vars.md) — vars that need file/dir bind-mounts
- [references/changelog-analysis.md](references/changelog-analysis.md) — what to look for in the changelog
- [references/managed-command-keys.md](references/managed-command-keys.md) — settings keys whose executable paths get bind-mounted

### 2. Fetch official documentation

Download with `curl` into the scratchpad and grep locally. **Do not use WebFetch for the env-vars page, the changelog, or the settings reference**: it truncates long pages and caches per URL for 15 minutes, so a follow-up "list the vars after X" returns the same truncated text. One `curl` call fetches everything in parallel with connection reuse:

```bash
cd "$SCRATCHPAD"
curl -sSL -Z \
  -o env-vars.md       https://code.claude.com/docs/en/env-vars.md \
  -o docs-changelog.md https://code.claude.com/docs/en/changelog.md \
  -o settings-ref.md   https://code.claude.com/docs/en/settings-reference.md \
  -o gh-changelog.md   https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \
  -o latest.json       https://api.github.com/repos/anthropics/claude-code/releases/latest
grep -oE '"(tag_name|published_at)": *"[^"]*"' latest.json
```

#### 2a. Env-vars page

Extract every backticked name from the variables table and diff it against the step-1 extraction, matching the passthrough loop's own glob list (the `PASSTHROUGH GLOBS` section) so the recipe can't drift from blaude. The heredoc pins bash: the Bash tool's shell may be zsh, where `[[ $v == $g ]]` does not glob-match:

```bash
bash <<'SH'
grep -oP '^\s*\|?\s*`\K[A-Z][A-Z0-9_]{2,}(?=`)' env-vars.md | sort -u > docs-vars.txt
grep -oE '^[A-Za-z][A-Za-z0-9_]*$' blaude-extract.txt | sort -u > blaude-vars.txt
mapfile -t globs < <(sed -n '/=== PASSTHROUGH GLOBS/,/^$/p' blaude-extract.txt | grep '\*')
comm -23 docs-vars.txt blaude-vars.txt | while read -r v; do
  for g in "${globs[@]}"; do [[ $v == $g ]] && continue 2; done; echo "$v"
done
SH
```

An empty result means no uncovered non-prefix var. Then, for the prefix-covered names, grep the table for path-shaped vars (the naming patterns in [auto-mount-vars.md](references/auto-mount-vars.md)) and for "Set by Claude Code" marker vars, and compare with the auto-mount and force-unset sections (see step 3). Also re-read the "Features that need feature-flag fetching" section at the bottom of the page — CLAUDE.md quotes that list, and it changes between releases.

#### 2b. Changelog — docs *and* GitHub

The docs changelog lags the GitHub release, sometimes by several versions, so audit both:

1. Take the latest version header from `docs-changelog.md` and the `tag_name` from the GitHub API call above.
2. If GitHub is newer, the gap versions live only in `gh-changelog.md`. Print each `## <version>` block between the two versions (they are plain markdown; `grep -nE '^## 2\.'` gives the line ranges).
3. Read every entry in the gap versions in full, plus the docs changelog entries since the last audit (the previous audit's version is in the latest `git log` commit that references a Claude Code version).

From each entry extract (see [changelog-analysis.md](references/changelog-analysis.md) for patterns):

1. **New env vars** — entries like "Added `VAR_NAME` env var..." Cross-reference with the env-vars table.
2. **Managed settings changes** — new settings, setting directories, or policy changes; especially any key whose value is a program Claude Code runs.
3. **Sandbox-relevant changes** — new tools, hook events, file paths, protocol handlers, plugin/MCP changes.
4. **Deprecations and removals** — vars or features removed that blaude may still reference.
5. **Security changes** — credential scrubbing, permission hardening, auth flow changes.

Report both version numbers in the summary line.

#### 2c. Settings reference — executable-valued keys

Filter the settings-reference index for keys whose value is a program Claude Code runs, and diff against the `MANAGED COMMAND KEYS` section of `blaude-extract.txt`:

```bash
awk -F'|' '/^\| \[`/ && tolower($2 $3) ~ /executable|helper|command to|script|binary|program|path to/ {print $2 "|" $3}' settings-ref.md
```

Classify each candidate not in the baseline per [managed-command-keys.md](references/managed-command-keys.md).

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

Start with a summary line: "Audited against Claude Code v{github tag} (GitHub release, {published date}; docs changelog at v{docs version}) and env-vars page as of {date}."

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

## Managed settings executable keys

| Key | Value type | Scope | In blaude jq set? | Failure when dangling |
|---|---|---|---|---|
| ... | path / command string / object.command | Managed / User or managed | Yes/No | ... |

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

For a new executable-valued managed settings key, follow the checklist at the end of [managed-command-keys.md](references/managed-command-keys.md).

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

The "Hardcoded vars" bullet also quotes the docs' feature-flag casualty list (what `DO_NOT_TRACK`/`DISABLE_TELEMETRY`/`DISABLE_GROWTHBOOK` cost). When the "Features that need feature-flag fetching" section on the env-vars page changes, refresh the list, re-stamp the version, and check that the items tied to blaude mechanisms (Remote Control, cross-machine messaging, the v2 MCP runtime opt-in) still hold.

The managed-settings executable key list lives in the CLAUDE.md bullet "Executables named by managed settings are bound" and the README section "Managed settings executables"; the checklist in [managed-command-keys.md](references/managed-command-keys.md) covers both.

Only update these docs for changes that were actually applied to the blaude script — do not update docs for recommendations the user declined.

#### Scope of doc updates

- Do NOT rewrite or restructure docs beyond the specific sections affected by the change
- Match the existing formatting style in each file
- For README.md, keep the env var table concise (wildcards over exhaustive lists)
- For CLAUDE.md, keep the auto-mount list in the same inline format

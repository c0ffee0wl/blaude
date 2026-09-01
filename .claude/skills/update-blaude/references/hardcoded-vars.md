# Hardcoded Environment Variables

These vars are set unconditionally via `--setenv` in the `_hardcoded_env_vars` array (stored as `KEY=VALUE` pairs). They override host values even under `--keep-env`, and the passthrough loop explicitly removes them from the whitelist. They must NEVER be added to the passthrough list — they are hardcoded by design.

| Variable | Value | Rationale |
|---|---|---|
| `DO_NOT_TRACK` | `1` | Privacy: universal opt-out signal (de facto standard). **RC-conditional** — appended only when not in Remote Control mode (RC needs GrowthBook; force-unset there instead) |
| `DISABLE_TELEMETRY` | `1` | Privacy: no telemetry from sandbox. **RC-conditional** (same as above) |
| `DISABLE_GROWTHBOOK` | `1` | Privacy: no feature-flag fetches. **RC-conditional** (same as above) |
| `DISABLE_AUTOUPDATER` | `1` | System dirs are read-only; updates would fail |
| `DISABLE_ERROR_REPORTING` | `1` | Privacy: no error reporting from sandbox |
| `DISABLE_BUG_COMMAND` | `1` | Bug reporting not useful inside sandbox |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | `1` | Survey not useful inside sandbox |
| `DISABLE_INSTALL_GITHUB_APP_COMMAND` | `1` | GitHub App install impossible from sandbox |
| `CLAUDE_DISABLE_CONFIG_WATCH` | `1` | Prevents inotify ENOSPC crashes in sandbox |

## Force-unset vars (`_hardcoded_unsetenv_vars`)

Forced absent via `--unsetenv` and included in the same passthrough deny-set. Report these as "already handled" too — never recommend them for passthrough.

- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` — the hardening predicate fires whenever the var is *defined* (even `=0`), overriding `--dangerously-skip-permissions` (symptom: `Permission mode forced to default — CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set …`). blaude matches the documented default of "unset = disabled". It was previously hardcoded `=0` in `_hardcoded_env_vars`; that did NOT suppress the banner, hence the move to force-unset.
- `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_BRIDGE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_TEAM_NAME`, `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_REMOTE_SESSION_ID`, `CLAUDE_EFFORT`, `CLAUDE_PROJECT_DIR` — markers an outer claude sets automatically; unset so a nested blaude launch starts the inner claude with clean identity. If the docs add a new "Set automatically in subprocesses" marker var, recommend adding it here.
- In Remote Control mode only: `DO_NOT_TRACK`, `DISABLE_TELEMETRY`, `DISABLE_GROWTHBOOK`, `ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`.

## Rules

- If an official env var matches one of these, report it as "already hardcoded" — do not recommend adding it as a passthrough.
- If a new official var serves a similar privacy/sandbox purpose (e.g., a new telemetry toggle), consider recommending it be hardcoded here instead of passthrough.
- If a new official var blocks/downgrades `--dangerously-skip-permissions` or otherwise breaks the auto-skip behaviour, recommend adding it to `_hardcoded_env_vars` with the value that disables the block (often `=0`).

## Related: settings.json blocker detection

An inline startup scan (not a function — search blaude for `_disable_re`; the scanned files are listed in the CLAUDE.md bullet "Bypass-permissions blocker detection") warns when any settings scope sets `permissions.disableBypassPermissionsMode: "disable"`. This is a JSON setting, not an env var — but it's a parallel mechanism for blocking bypass mode. If a new audit reveals additional JSON keys (or env vars) that block bypass mode, extend that scan or add a new hardcoded entry above.

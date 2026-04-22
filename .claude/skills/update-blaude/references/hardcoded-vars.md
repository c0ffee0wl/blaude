# Hardcoded Environment Variables

These vars are set unconditionally via `--setenv` in the `_hardcoded_env_vars` array (stored as `KEY=VALUE` pairs). They override host values even under `--keep-env`, and the passthrough loop explicitly removes them from the whitelist. They must NEVER be added to the passthrough list — they are hardcoded by design.

| Variable | Value | Rationale |
|---|---|---|
| `DO_NOT_TRACK` | `1` | Privacy: universal opt-out signal (de facto standard) |
| `DISABLE_TELEMETRY` | `1` | Privacy: no telemetry from sandbox |
| `DISABLE_AUTOUPDATER` | `1` | System dirs are read-only; updates would fail |
| `DISABLE_ERROR_REPORTING` | `1` | Privacy: no error reporting from sandbox |
| `DISABLE_BUG_COMMAND` | `1` | Bug reporting not useful inside sandbox |
| `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY` | `1` | Survey not useful inside sandbox |
| `DISABLE_INSTALL_GITHUB_APP_COMMAND` | `1` | GitHub App install impossible from sandbox |
| `CLAUDE_DISABLE_CONFIG_WATCH` | `1` | Prevents inotify ENOSPC crashes in sandbox |
| `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` | **`0`** | `=1` triggers permission-mode hardening that overrides `--dangerously-skip-permissions` (which blaude always passes). Symptom on host: `Permission mode forced to default — CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set …`. The only `=0` entry in the array. |

## Rules

- If an official env var matches one of these, report it as "already hardcoded" — do not recommend adding it as a passthrough.
- If a new official var serves a similar privacy/sandbox purpose (e.g., a new telemetry toggle), consider recommending it be hardcoded here instead of passthrough.
- If a new official var blocks/downgrades `--dangerously-skip-permissions` or otherwise breaks the auto-skip behaviour, recommend adding it to `_hardcoded_env_vars` with the value that disables the block (often `=0`).

## Related: settings.json blocker detection

`_warn_if_bypass_disabled` (~line 277) scans `settings.json`/`managed-settings.json` for `permissions.disableBypassPermissionsMode: "disable"` and warns at startup. This is a JSON setting, not an env var — but it's a parallel mechanism for blocking bypass mode. If a new audit reveals additional JSON keys (or env vars) that block bypass mode, extend this function or add a new hardcoded entry above.

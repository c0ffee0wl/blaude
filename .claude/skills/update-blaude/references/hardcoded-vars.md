# Hardcoded Environment Variables

These vars are set unconditionally via `--setenv` in the `bwrap_args` block (~line 679). They must NEVER be added to the passthrough list — they are hardcoded by design.

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

## Rules

- If an official env var matches one of these, report it as "already hardcoded" — do not recommend adding it as a passthrough.
- If a new official var serves a similar privacy/sandbox purpose (e.g., a new telemetry toggle), consider recommending it be hardcoded here instead of passthrough.

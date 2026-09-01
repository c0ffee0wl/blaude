# Changelog Analysis Guide

The changelog at https://code.claude.com/docs/en/changelog.md lists changes per version. It complements the env-vars page by revealing *when* vars were added, *why*, and what else changed that may affect blaude.

## What to extract from the changelog

### 1. New environment variables

Look for entries matching patterns like:
- "Added `SOME_ENV_VAR` env var..."
- "Added `SOME_ENV_VAR` environment variable..."

Cross-reference each against the env-vars page and blaude's current passthrough list.

### 2. Managed settings changes

Look for:
- "Added `settingName` managed setting..."
- "Added `managed-settings.d/`..." (directory-based policy)
- Settings that affect sandbox behavior (e.g., `sandbox.failIfUnavailable`)

These may need blaude to pre-configure `.claude.json` or `managed-settings.json`.

### 3. Sandbox-relevant changes

Look for:
- New tools (e.g., PowerShell tool) that may need sandbox permissions
- New hook events that fire shell commands
- Changes to file paths Claude Code reads/writes
- Protocol handler registration (`claude-cli://`)
- New MCP transport or authentication flows
- Changes to how Claude Code discovers/loads plugins

### 4. Breaking changes and deprecations

Look for:
- "Deprecated `OLD_VAR`..." — check if blaude still passes it
- "Changed `VAR` to..." — may need passthrough or mount updates
- "Removed..." — clean up from blaude if present

### 5. Security-relevant changes

Look for:
- Credential scrubbing (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` — already force-unset; see [hardcoded-vars.md](hardcoded-vars.md))
- Permission hardening — any new env var or settings.json key that downgrades/blocks bypass mode (extend `_hardcoded_unsetenv_vars` / `_hardcoded_env_vars`, or the inline `_disable_re` settings scan)
- New managed settings keys whose value is an executable path or command — see [managed-command-keys.md](managed-command-keys.md)
- Sandbox-related fixes
- New authentication flows

## Version tracking

After each audit, note the latest version checked so future audits can start from where the last one left off. Report this in the audit output.

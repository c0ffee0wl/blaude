# CLAUDE.md

Repository: https://github.com/c0ffee0wl/blaude

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

blaude is a bash script that runs Claude Code inside a bubblewrap (bwrap) sandbox for security isolation. It provides filesystem, namespace, and capability isolation while allowing Claude Code to function normally within constrained boundaries.

## Running and Testing

```bash
# Make script executable (if needed)
chmod +x blaude

# Run with defaults (launches Claude Code in sandbox)
./blaude

# Test with debug output to see the bwrap command
./blaude --debug

# Dry run (show command without executing)
./blaude --dry-run

# Run bash inside sandbox for debugging
./blaude --exec bash

# Pass claude options directly
./blaude -c              # continue conversation
./blaude -p "hello"      # prompt mode
./blaude --resume        # resume picker

# Mount additional paths
./blaude -m /path/to/dir          # read-only
./blaude -m /path/to/dir:rw       # read-write

# Keep entire host environment (skip --clearenv)
./blaude --keep-env

# Use isolated tmpfs for /tmp instead of host's /tmp
./blaude --clear-tmp
```

## Key Architecture

The script builds a complex `bwrap` command with these isolation layers:

1. **Namespace isolation**: PID, IPC, cgroup, UTS namespaces with custom hostname "blaude"
2. **Capability dropping**: All capabilities dropped via `--cap-drop ALL`
3. **Filesystem sandboxing**:
   - System dirs (`/usr`, `/lib`, `/bin`, `/etc`) mounted read-only
   - Host's `/tmp` mounted read-write by default (use `--clear-tmp` for isolated tmpfs)
   - Current working directory mounted at `/workspaces/<dirname>` read-write
   - `~/.claude` mounted read-write for config persistence
   - Ephemeral writable dirs for package managers (`~/.cache`, `~/go`, `~/.cargo`, `~/.npm`)
   - uv tools and managed Python versions (`~/.local/share/uv/tools`, `~/.local/share/uv/python`)
4. **Environment sanitization**: `--clearenv` with selective passthrough of LLM API keys and essential vars (use `--keep-env` to preserve host environment)

## Important Implementation Details

- **Line 25**: Commands that bypass sandbox (`update`, `install`, `install-github-app`) - these need write access outside sandbox
- **Lines 93-116**: Auto-configures `~/.claude/.claude.json` with required flags for `--dangerously-skip-permissions`
- **Lines 120-140**: Core bwrap security options (note: `--new-session` intentionally removed for MCP server signal propagation)
- **Lines 399-415**: Additional mount handling with `:rw` suffix parsing for read-write mounts
- **Lines 496-547**: Claude Code environment variable passthrough array - all official env vars from https://code.claude.com/docs/en/settings are included

## WSL2/systemd resolv.conf Handling

Lines 148-228 handle a tricky issue where `/etc/resolv.conf` is a symlink (common in WSL2 with systemd or systemd-resolved):

- bwrap's `--file` and bind mounts follow symlinks
- If `/etc/resolv.conf` -> `/run/systemd/resolve/stub-resolv.conf`, bwrap tries to create the file at the symlink target
- Since `/run` doesn't exist yet when `/etc` is mounted, this fails

**Solution**: Two-phase approach:
1. Early detection: save symlink target info
2. Deferred mount: after `--tmpfs /run` is created, create the target directory and mount resolv.conf content there

Reference: https://github.com/containers/bubblewrap/issues/390

## npm-linked Packages Auto-detection

Lines 320-347 automatically detect and mount npm-linked packages:

- Scans `~/.nvm/versions/*/node_modules/` for symlinks pointing outside `~/.nvm`
- Resolves symlinks to find package root (directory with `package.json`)
- Mounts package directories read-only
- Safety: never mounts `$HOME` itself

This enables MCP servers installed via `npm link` to work inside the sandbox.

## MCP Server Token File Persistence

Lines 336-350 handle token storage for npm-linked MCP servers:

- Token files (`.token-cache.json`, `.selected-account.json`) are at **package root**, not `$HOME`
- For npm-linked packages, these files are mounted read-write over the read-only package mount
- Files are created if they don't exist

**Why file-based by default?**
- D-Bus/keytar requires GNOME Keyring to be properly configured and unlocked
- In headless environments (WSL2, containers), this is often not set up
- File-based storage is more reliable and works everywhere

## D-Bus and GNOME Keyring Support (optional)

Enabled with `--keyring` flag. Lines 204-222 and 263-271 handle D-Bus/keyring:

| Component | Lines | Purpose |
|-----------|-------|---------|
| D-Bus socket | 204-222 | Parses `DBUS_SESSION_BUS_ADDRESS`, binds session socket |
| Keyrings dir | 263-271 | Binds `~/.local/share/keyrings` read-write |
| Env passthrough | 558-560 | Passes `DBUS_SESSION_BUS_ADDRESS` to sandbox |

**When to use `--keyring`**:
- You have GNOME Keyring properly configured
- The keyring is unlocked at login
- You prefer encrypted credential storage

**D-Bus address parsing**:
- Supports `unix:path=/run/user/$UID/bus` format
- Warns about abstract sockets (don't work with namespaces)
- Falls back to standard systemd path

## claudechic Support

The `--chic` flag runs [claudechic](https://github.com/c0ffee0wl/claudechic) (a Python-based TUI wrapper) instead of bare Claude Code:

```bash
./blaude --chic              # Run claudechic in sandbox
./blaude --chic -c           # Continue conversation via claudechic
```

**Mounts:**
- `~/.claude/.claudechic.yaml` - Config file (already writable via `~/.claude` mount)
- `~/claudechic.log` - Debug log (only if `CLAUDECHIC_DEBUG=1`)

**Environment variables passed through:**
- `CLAUDECHIC_DEBUG` - Enable debug logging
- `CLAUDECHIC_REMOTE_PORT` - HTTP server for remote control
- `CHIC_PROFILE` - CPU profiling toggle
- `CHIC_SAMPLE_THRESHOLD` - CPU sampling threshold

## notebooklm-mcp Support

The [notebooklm-mcp-cli](https://github.com/jacob-bd/notebooklm-mcp-cli) MCP server is supported with auth persistence:

**Mounts:**
- `~/.notebooklm-mcp/` - Auth directory (read-write, created if missing)
- `~/.notebooklm-mcp-cli/` - Auth directory (read-write, created if missing)

**Environment variables passed through:**
- `NOTEBOOKLM_COOKIES`, `NOTEBOOKLM_CSRF_TOKEN`, `NOTEBOOKLM_SESSION_ID` - Override cached auth
- `NOTEBOOKLM_MCP_TRANSPORT`, `NOTEBOOKLM_MCP_HOST`, `NOTEBOOKLM_MCP_PORT` - Server config
- `NOTEBOOKLM_MCP_DEBUG`, `NOTEBOOKLM_QUERY_TIMEOUT`, `NOTEBOOKLM_BL` - Debug/tuning

**Usage:**
```bash
# Authenticate outside sandbox first (requires browser)
nlm login                      # Default profile
nlm login --profile work       # Named profile

# Then use normally inside sandbox - MCP server reads cached tokens
./blaude
```

## WSL2 Support

WSL2 is auto-detected via `/proc/sys/kernel/osrelease` or `/proc/version` (checks for "microsoft").

**Known issues:**
- WSL2's 9P filesystem (drvfs) can have race conditions with bind mounts
- File operations may fail with `ENOENT: no such file or directory, statx`
- This is a [known WSL2 issue](https://github.com/microsoft/WSL/issues/2780) with concurrent file operations

**Workarounds applied:**
- `sync` is called before and after sandbox execution to flush pending filesystem operations

**If issues persist:**
- Try running `sync` manually before blaude
- Ensure your WSL2 is up to date (`wsl --update`)
- Consider storing your workspace on the Linux filesystem (`/home/...`) instead of Windows (`/mnt/c/...`)

## Prerequisites

- bubblewrap (`apt install bubblewrap` or `dnf install bubblewrap`)
- Claude Code installed and in PATH
- Optional: `jq` for config file merging
- Optional: GNOME Keyring / D-Bus session for `--keyring` support
- Optional: [claudechic](https://github.com/c0ffee0wl/claudechic) for `--chic` mode
- Optional: [notebooklm-mcp-cli](https://github.com/jacob-bd/notebooklm-mcp-cli) for NotebookLM integration

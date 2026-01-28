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
```

## Key Architecture

The script builds a complex `bwrap` command with these isolation layers:

1. **Namespace isolation**: PID, IPC, cgroup, UTS namespaces with custom hostname "blaude"
2. **Capability dropping**: All capabilities dropped via `--cap-drop ALL`
3. **Filesystem sandboxing**:
   - System dirs (`/usr`, `/lib`, `/bin`, `/etc`) mounted read-only
   - Current working directory mounted at `/workspaces/<dirname>` read-write
   - `~/.claude` mounted read-write for config persistence
   - Ephemeral writable dirs for package managers (`~/.cache`, `~/go`, `~/.cargo`, `~/.npm`)
4. **Environment sanitization**: `--clearenv` with selective passthrough of LLM API keys and essential vars

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

## D-Bus and GNOME Keyring Support (for keytar)

Lines 199-219, 259-268, and 554-557 enable secure credential storage via keytar/libsecret:

| Component | Lines | Purpose |
|-----------|-------|---------|
| D-Bus socket | 199-219 | Parses `DBUS_SESSION_BUS_ADDRESS`, binds session socket |
| Keyrings dir | 259-268 | Binds `~/.local/share/keyrings` read-write |
| Env passthrough | 554-557 | Passes `DBUS_SESSION_BUS_ADDRESS` to sandbox |

**D-Bus address parsing**:
- Supports `unix:path=/run/user/$UID/bus` format
- Warns about abstract sockets (don't work with namespaces)
- Falls back to standard systemd path

This enables MCP servers like ms-365-mcp-server to store credentials securely in GNOME Keyring.

## MCP Server Token File Persistence

Lines 271-280 handle fallback token storage for MCP servers (when keytar unavailable):

- Binds `~/.token-cache.json` and `~/.selected-account.json` read-write
- Creates files if they don't exist
- Overlays the `$HOME` tmpfs so tokens persist across sessions

Used by ms-365-mcp-server when GNOME Keyring is not available.

## Prerequisites

- bubblewrap (`apt install bubblewrap` or `dnf install bubblewrap`)
- Claude Code installed and in PATH
- Optional: `jq` for config file merging
- Optional: GNOME Keyring / D-Bus session for keytar support

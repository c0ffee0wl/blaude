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

1. **Namespace isolation**: PID, IPC, UTS, user namespaces with custom hostname "blaude"; optional network namespace with `--no-network`
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
- **Lines 29-62**: `fix-apparmor` subcommand - installs AppArmor profile for bwrap on Ubuntu 24.04+ (requires sudo)
- **Lines 121-143**: Auto-configures `~/.claude/.claude.json` with required flags for `--dangerously-skip-permissions`
- **Lines 147-156**: Core bwrap security options (note: `--new-session` intentionally removed for MCP server signal propagation)
- **Git mode** (`--git`): mounts `.gitconfig`/`.git-credentials` AND passes `GH_TOKEN`/`GITHUB_TOKEN`
- **AWS mode** (`--aws`): mounts `~/.aws/` read-only for Bedrock authentication (SSO, credentials, config); also mounts `GOOGLE_APPLICATION_CREDENTIALS` file if set
- **Additional mount handling**: `:rw` suffix parsing for read-write mounts
- **Claude Code environment variable passthrough array**: all official env vars from https://code.claude.com/docs/en/settings are included, plus OpenTelemetry, Vertex AI, and LLM gateway vars (GitHub tokens require `--git`; AWS config dir requires `--aws`)

## AppArmor User Namespace Restriction (Ubuntu 24.04+)

Ubuntu 24.04+ enables `apparmor_restrict_unprivileged_userns` by default, which blocks bwrap from creating user namespaces. blaude handles this in two ways:

1. **Startup detection**: Before executing bwrap, checks if AppArmor restriction is active and no bwrap profile exists. Prints a warning with fix instructions.
2. **`fix-apparmor` subcommand**: Installs a minimal AppArmor profile at `/etc/apparmor.d/bwrap` that grants bwrap the `userns` permission. Runs with `sudo`, idempotent.

**Detection conditions** (all must be true to trigger warning):
- `apparmor_parser` command exists
- `/sys/module/apparmor` directory exists (AppArmor loaded)
- `/proc/sys/kernel/apparmor_restrict_unprivileged_userns` is "1"
- `/etc/apparmor.d/bwrap` does NOT exist

## WSL2/systemd resolv.conf Handling

Lines 180-262 handle a tricky issue where `/etc/resolv.conf` is a symlink (common in WSL2 with systemd or systemd-resolved):

- bwrap's `--file` and bind mounts follow symlinks
- If `/etc/resolv.conf` -> `/run/systemd/resolve/stub-resolv.conf`, bwrap tries to create the file at the symlink target
- Since `/run` doesn't exist yet when `/etc` is mounted, this fails

**Solution**: Two-phase approach:
1. Early detection: save symlink target info
2. Deferred mount: after `--tmpfs /run` is created, create the target directory and mount resolv.conf content there

Reference: https://github.com/containers/bubblewrap/issues/390

## npm-linked Packages Auto-detection

Lines 353-386 automatically detect and mount npm-linked packages:

- Scans `~/.nvm/versions/*/node_modules/` for symlinks pointing outside `~/.nvm`
- Resolves symlinks to find package root (directory with `package.json`)
- Mounts package directories read-only
- Safety: never mounts `$HOME` itself

This enables MCP servers installed via `npm link` to work inside the sandbox.

## MCP Server Token File Persistence

Lines 376-384 handle token storage for npm-linked MCP servers:

- Token files (`.token-cache.json`, `.selected-account.json`) are at **package root**, not `$HOME`
- For npm-linked packages, these files are mounted read-write over the read-only package mount
- Files are created if they don't exist

**Why file-based by default?**
- D-Bus/keytar requires GNOME Keyring to be properly configured and unlocked
- In headless environments (WSL2, containers), this is often not set up
- File-based storage is more reliable and works everywhere

## D-Bus and GNOME Keyring Support (optional)

Enabled with `--keyring` flag. Lines 236-252 and 294-302 handle D-Bus/keyring:

| Component | Lines | Purpose |
|-----------|-------|---------|
| D-Bus socket | 236-252 | Parses `DBUS_SESSION_BUS_ADDRESS`, binds session socket |
| Keyrings dir | 294-302 | Binds `~/.local/share/keyrings` read-write |
| Env passthrough | 641-644 | Passes `DBUS_SESSION_BUS_ADDRESS` to sandbox |

**When to use `--keyring`**:
- You have GNOME Keyring properly configured
- The keyring is unlocked at login
- You prefer encrypted credential storage

**D-Bus address parsing**:
- Supports `unix:path=/run/user/$UID/bus` format
- Warns about abstract sockets (don't work with namespaces)
- Falls back to standard systemd path

## AWS/Cloud Mode

The `--aws` flag mounts cloud provider credentials into the sandbox:

```bash
./blaude --aws              # Mount ~/.aws/ for Bedrock authentication
```

**Mounts:**
- `~/.aws/` - AWS config and credentials directory (read-only)
- `GOOGLE_APPLICATION_CREDENTIALS` file - GCP service account key (read-only, if env var is set)

**When to use `--aws`**:
- Using Amazon Bedrock with `aws configure` or `aws sso login` credentials
- Using `AWS_PROFILE` that references `~/.aws/config`
- Using a GCP service account key file for Vertex AI

**Note**: AWS environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_PROFILE`, `AWS_REGION`, etc.) are always passed through when set, regardless of `--aws`. The flag is only needed for file-based credentials in `~/.aws/`.

## claudechic Support

The `--chic` flag runs [claudechic](https://github.com/mrocklin/claudechic) (a Python-based TUI wrapper) instead of bare Claude Code:

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

**Auto-passthrough patterns (Lines 636-639):**
- `*_WEBHOOK` - Any variable ending in `_WEBHOOK` (e.g., `SLACK_WEBHOOK`)
- `WEBSHARE_*` - Any variable starting with `WEBSHARE_` (e.g., `WEBSHARE_API_KEY`, `WEBSHARE_PROXY`)

## User Config Directory

The entire `~/.config/` directory is mounted read-write if it exists. This consolidates configuration access for multiple tools:

**Key configs included:**
- `~/.config/uv/uv.toml` - uv Python preference (e.g., `python-preference = "system"`)
- `~/.config/fabric/` - Fabric patterns, sessions, contexts, strategies, extensions, `.env`, OAuth tokens
- `~/.config/google-chrome/` - Chrome profile for browser automation (Puppeteer, Playwright, OAuth flows)

Not created automatically - only mounted if already present on host.

## arxiv-storage Directory

The `~/arxiv-storage/` directory is mounted read-write if it exists. This is for research paper management tools that download and organize arxiv papers.

Not created automatically - only mounted if already present on host.

## Claude Memory Directory

The `~/.claude-mem/` directory is mounted read-write if it exists. This provides persistent memory storage across sandbox sessions.

Not created automatically - only mounted if already present on host.

## Bun Runtime

The `~/.bun/` directory is mounted read-only if it exists. This provides access to the Bun JavaScript runtime and packages installed via `bun`. `~/.bun/bin` is included in the sandbox PATH.

Not created automatically - only mounted if already present on host.

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

**Session caching:**
- WSL detection is cached in `/tmp/blaude-wsl-$UID` to avoid repeated proc checks
- `/mnt/*` warning is shown once per session (tracked via `/tmp/blaude-mnt-warned-$UID`)
- Caches are cleared on reboot (tmpfs)

**Known issues:**
- WSL2's 9P filesystem (drvfs) has unfixed bugs causing `ENOENT` errors after `rename()`/`fstat()`
- Related issues: [#8443](https://github.com/microsoft/WSL/issues/8443), [#13105](https://github.com/microsoft/WSL/issues/13105) (still open)
- Only affects `/mnt/*` paths (9P); native ext4 filesystem (`/home/...`) is not affected

**Workarounds applied:**
- Warning shown (once per session) when workspace is on `/mnt/*`
- `sync` is called before sandbox execution to flush pending filesystem operations
- `sync` is called on exit via trap

**If issues persist:**
- Ensure your WSL2 is up to date (`wsl --update`)
- Store your workspace on the Linux filesystem (`/home/...`) instead of Windows (`/mnt/c/...`) - this avoids 9P entirely and is much faster

## Prerequisites

- bubblewrap (`apt install bubblewrap` or `dnf install bubblewrap`)
- Claude Code installed and in PATH
- Optional: `jq` for config file merging
- Optional: GNOME Keyring / D-Bus session for `--keyring` support
- Optional: [claudechic](https://github.com/mrocklin/claudechic) for `--chic` mode
- Optional: [notebooklm-mcp-cli](https://github.com/jacob-bd/notebooklm-mcp-cli) for NotebookLM integration

# CLAUDE.md

Repository: https://github.com/c0ffee0wl/blaude

## Overview

blaude is a bash script that runs Claude Code inside a bubblewrap (bwrap) sandbox for security isolation. It provides filesystem, namespace, and capability isolation while allowing Claude Code to function normally within constrained boundaries.

## Running and Testing

```bash
./blaude                         # Run with defaults
./blaude --debug                 # Show bwrap command before executing
./blaude --dry-run               # Show command without executing
./blaude --exec bash             # Run bash inside sandbox for debugging
./blaude -c                      # Continue conversation
./blaude -p "hello"              # Prompt mode
./blaude -m /path/to/dir         # Mount read-only
./blaude -m /path/to/dir:rw      # Mount read-write
./blaude --keep-env              # Keep entire host environment
./blaude --clear-tmp             # Isolated tmpfs for /tmp
```

## Key Architecture

The script builds a `bwrap` command with these isolation layers:

1. **Namespace isolation**: PID, IPC, UTS, user namespaces with hostname "blaude"; optional network namespace with `--no-network`
2. **Capability dropping**: All capabilities dropped via `--cap-drop ALL`
3. **Filesystem sandboxing**: System dirs read-only, working dir + config read-write, ephemeral caches
4. **Environment sanitization**: `--clearenv` with selective passthrough of LLM API keys and essential vars

## Non-Obvious Design Decisions

- **`--new-session` intentionally omitted** from bwrap args — required for MCP server signal propagation. PID namespace provides equivalent process isolation.
- **Sandbox bypass commands**: `update`, `install`, `install-github-app` exec claude directly (need write access outside sandbox). Checked both as `$1` and after flag parsing (e.g., `./blaude --debug install`).
- **Auto-configures `~/.claude/.claude.json`** with `hasCompletedOnboarding` and `bypassPermissionsModeAccepted` flags. Uses `jq` if available for merging, otherwise overwrites. Updates both `$CLAUDE_CONFIG_DIR/.claude.json` and `~/.claude.json`.
- **UID mapping**: Root users get mapped to UID 1000 inside sandbox; non-root keeps their UID. Required for `--dangerously-skip-permissions`.
- **D-Bus/keytar disabled by default** — file-based token storage is more reliable in headless environments (WSL2, containers). Use `--keyring` only if GNOME Keyring is properly configured and unlocked.
- **npm-linked package auto-detection**: Scans `~/.nvm/versions/*/node_modules/` for symlinks pointing outside `~/.nvm`, resolves to package root (directory with `package.json`), mounts read-only. Safety: never mounts `$HOME` itself.
- **MCP token files mounted read-write** over read-only package mounts — token files (`.token-cache.json`, `.selected-account.json`) live at package root, not `$HOME`.
- **claudechic config**: Do NOT bind-mount `~/.claude/.claudechic.yaml` directly — claudechic uses atomic writes (`os.replace`) which fail on bind-mounted files. It's already accessible via the `~/.claude` mount.
- **CLAUDE_CODE_TMPDIR**: If set to something other than `/tmp`, a tmpfs is created at that path inside the sandbox.

## WSL2/systemd resolv.conf Handling

This is a tricky two-phase workaround for bwrap following symlinks:

- If `/etc/resolv.conf` → `/run/systemd/resolve/stub-resolv.conf`, bwrap tries to create the file at the symlink target, but `/run` doesn't exist yet when `/etc` is mounted.
- **Solution**: Save symlink target and content early, then after `--tmpfs /run` is added, create the target directory and mount resolv.conf content there.
- Reference: https://github.com/containers/bubblewrap/issues/390

## Environment Variable Passthrough

The `claude_env_vars` array contains all official Claude Code env vars from https://code.claude.com/docs/en/env-vars plus third-party keys. Organized under comment headers by category. Key rules:

- **Hardcoded vars** (set unconditionally via `--setenv`): `DO_NOT_TRACK`, `DISABLE_TELEMETRY`, `DISABLE_AUTOUPDATER`, `DISABLE_ERROR_REPORTING`, `DISABLE_BUG_COMMAND`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY`, `DISABLE_INSTALL_GITHUB_APP_COMMAND`, `CLAUDE_DISABLE_CONFIG_WATCH` — never add these to passthrough.
- **GitHub tokens** (`GH_TOKEN`, `GITHUB_TOKEN`): Only passed with `--git` flag.
- **Glob patterns**: `*_WEBHOOK` and `WEBSHARE_*` are auto-passed via env scanning loop (not in the array).
- **Auto-mounted file/path vars**: Vars pointing to files/dirs need both passthrough AND a bind-mount. Currently: `CLAUDE_ENV_FILE`, `CLAUDE_CODE_PLUGIN_SEED_DIR`, `CLAUDE_CODE_PLUGIN_CACHE_DIR`, `CLAUDE_CODE_DEBUG_LOGS_DIR`, `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_CLIENT_KEY`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `NODE_EXTRA_CA_CERTS`. When adding new vars, check if they reference paths.

## AppArmor (Ubuntu 24.04+)

Ubuntu 24.04+ blocks bwrap's user namespaces via `apparmor_restrict_unprivileged_userns`. blaude detects this at startup and warns. Fix with `blaude fix-apparmor` (installs minimal AppArmor profile, requires sudo, idempotent).

## WSL2 Support

Auto-detected via `/proc/sys/kernel/osrelease` or `/proc/version`. Session-cached in `/tmp/blaude-wsl-$UID`.

- **9P filesystem bugs**: WSL2's drvfs has unfixed `ENOENT` bugs after `rename()`/`fstat()` — only affects `/mnt/*` paths. `sync` is called before/after sandbox execution as mitigation.
- **Warning**: Shown once per session when workspace is on `/mnt/*`. Best fix: use native ext4 (`/home/...`).

## Optional Directory Mounts

These directories are mounted only if they exist on the host (not created automatically):

| Directory | Access | Purpose |
|-----------|--------|---------|
| `~/.config/` | read-write | User config (uv, fabric, google-chrome, etc.) |
| `~/.bun/` | read-only | Bun runtime (`~/.bun/bin` added to PATH) |
| `~/arxiv-storage/` | read-write | Research paper management |
| `~/.claude-mem/` | read-write | Persistent memory across sessions |
| `~/.notebooklm-mcp/` | read-write | notebooklm-mcp auth (created if missing) |

## Prerequisites

- bubblewrap (`apt install bubblewrap` or `dnf install bubblewrap`)
- Claude Code installed and in PATH
- Optional: `jq` for config file merging
- Optional: GNOME Keyring / D-Bus session for `--keyring` support
- Optional: [claudechic](https://github.com/mrocklin/claudechic) for `--chic` mode
- Optional: [notebooklm-mcp-cli](https://github.com/jacob-bd/notebooklm-mcp-cli) for NotebookLM integration

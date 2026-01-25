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

- Lines 24-27: Commands that bypass sandbox (`update`, `install`, `install-github-app`) - these need write access outside sandbox
- Lines 93-106: Auto-configures `~/.claude/.claude.json` with required flags for `--dangerously-skip-permissions`
- Lines 110-119: Core bwrap security options (note: `--new-session` intentionally removed for MCP server signal propagation)
- Lines 251-270: Additional mount handling with `:rw` suffix parsing for read-write mounts
- Lines 318-333: LLM API key passthrough loop - add new API keys here if needed

## Prerequisites

- bubblewrap (`apt install bubblewrap` or `dnf install bubblewrap`)
- Claude Code installed and in PATH
- Optional: `jq` for config file merging

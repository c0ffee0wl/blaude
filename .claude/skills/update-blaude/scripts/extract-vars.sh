#!/usr/bin/env bash
# Extract environment variables from the blaude script.
# Usage: extract-vars.sh <path-to-blaude>
# Outputs two sections: HARDCODED (Claude Code config block) and PASSTHROUGH (claude_env_vars array).

set -euo pipefail
BLAUDE="${1:-blaude}"

echo "=== HARDCODED (Claude Code config block) ==="
# Only extract from the "Claude Code configuration" bwrap_args block
sed -n '/# Claude Code configuration/,/^)/p' "$BLAUDE" \
  | grep -oP '(?<=--setenv )\S+' \
  | sort -u

echo ""
echo "=== PASSTHROUGH (claude_env_vars array) ==="
sed -n '/^claude_env_vars=(/,/^)/p' "$BLAUDE" \
  | grep -v '^\s*#' \
  | grep -oP '[A-Z][A-Z0-9_*]+' \
  | sort -u

echo ""
echo "=== AUTO-MOUNTED FILE VARS ==="
# Vars that trigger auto-mounting of files/dirs into the sandbox
grep -oP '(?<=\$\{)[A-Z_]+(?=\b)' "$BLAUDE" \
  | sort -u \
  | while read -r var; do
      grep -q "$var.*--ro-bind\|--bind.*$var\|auto.*mount.*$var\|$var.*mount" "$BLAUDE" 2>/dev/null && echo "$var" || true
    done

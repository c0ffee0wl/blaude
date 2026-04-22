#!/usr/bin/env bash
# Extract environment variables from the blaude script.
# Usage: extract-vars.sh <path-to-blaude>
# Outputs two sections: HARDCODED (Claude Code config block) and PASSTHROUGH (claude_env_vars array).

set -euo pipefail
BLAUDE="${1:-blaude}"

echo "=== HARDCODED (forced via _hardcoded_env_vars KEY=VALUE pairs) ==="
# Stored as KEY=VALUE pairs since the SCRUB=0 fix; extract the KEY part only.
sed -n '/^_hardcoded_env_vars=(/,/^)/p' "$BLAUDE" \
  | grep -v '^\s*#' \
  | grep -oE '[A-Z_][A-Z0-9_]*=' \
  | tr -d '=' \
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

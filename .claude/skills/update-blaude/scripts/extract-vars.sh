#!/usr/bin/env bash
# Extract environment variables from the blaude script.
# Usage: extract-vars.sh <path-to-blaude>
# Outputs one section per mechanism: hardcoded, passthrough, force-unset,
# auto-mounted paths, passthrough globs, and the managed-settings command keys.

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
# //!p drops the `claude_env_vars=(` and `)` delimiters, which would otherwise
# match the name pattern themselves now that it accepts lowercase — needed for
# the both-case proxy entries (https_proxy et al.), which an uppercase-only
# pattern silently dropped, making the audit re-report them as missing.
sed -n '/^claude_env_vars=(/,/^)/{//!p}' "$BLAUDE" \
  | grep -v '^\s*#' \
  | grep -oP '[A-Za-z][A-Za-z0-9_*]+' \
  | sort -u

echo ""
echo "=== FORCE-UNSET (_hardcoded_unsetenv_vars, incl. RC-mode conditionals) ==="
awk '/_hardcoded_unsetenv_vars\+?=\(/{f=1} f{print} f&&/\)/{f=0}' "$BLAUDE" \
  | grep -v '^\s*#' \
  | grep -oE '\b[A-Z][A-Z0-9_]+\b' \
  | sort -u

echo ""
echo "=== AUTO-MOUNTED FILE/PATH VARS ==="
# Env vars whose paths get bind-mounted into the sandbox:
#  - direct `_bind_env_path VAR` calls
#  - `for var in ...; do _bind_env_path "$var"` loops
#  - special cases that dereference the var inline (parent-dir binds like
#    "${VAR%/*}", colon-separated lists split via <<< "$VAR")
{
  grep -oE '_bind_env_path +[A-Z][A-Z0-9_]+' "$BLAUDE" | grep -oE '[A-Z][A-Z0-9_]+' || true
  awk '/^for var in/{blk=""; f=1} f{blk=blk" "$0} f&&/^done/{f=0; if (blk ~ /_bind_env_path/) print blk}' "$BLAUDE" \
    | grep -oE '\b[A-Z][A-Z0-9_]+\b' || true
  grep -oE '(_bind_if_exists|<<<) +"\$\{?[A-Z][A-Z0-9_]+' "$BLAUDE" | grep -oE '[A-Z][A-Z0-9_]+$' || true
} | grep -vE '^(HOME|UID)$' | sort -u

echo ""
echo "=== PASSTHROUGH GLOBS (prefix/suffix patterns in the env loop) ==="
# The `"$name" == PATTERN` alternatives of the passthrough `if`, one per line,
# so an audit can match documented names against them instead of hand-copying
# the list (which drifted every time a glob family was added).
sed -n '/^\s*if \[\[ -n "\${_env_whitelist/,/\]\]; then/p' "$BLAUDE" \
  | grep -oE '"\$name" == [A-Za-z_*]+' \
  | grep -oE '[A-Za-z_*]+$' \
  | sort -u

echo ""
echo "=== MANAGED COMMAND KEYS (jq in _mount_managed_config_paths) ==="
# The enumerated settings keys whose executable paths get their directory
# ro-bound. Prints the jq key paths with the `?` guards stripped, e.g.
# `.policyHelper.path`; `(.hooks | .. | objects | .command)` covers every hook
# event. Diff against the settings reference's executable-valued keys.
sed -n "/^_mount_managed_config_paths()/,/^}/{/jq -r '\[/,/\] | \.\[\]/{s/?//g;p}}" "$BLAUDE" \
  | grep -oE '\(\.hooks[^)]*\)|\.[A-Za-z][A-Za-z0-9_.]*' \
  | sort -u

# Managed Settings Executable Keys

`_mount_managed_config_paths` in blaude reads `/etc/claude-code/managed-settings.json` and `managed-settings.d/*.json`, extracts the absolute paths named by an **enumerated** jq set of command-valued keys, and ro-binds the directory holding each one. A new upstream key is silently ignored until it is added to that set. The set itself is printed by `extract-vars.sh` (`MANAGED COMMAND KEYS` section); the rationale for enumerating, managed-scope-only reading, the `?` guards and the `_root_owned` gates is in the function's header comment and the CLAUDE.md bullet "Executables named by managed settings are bound" — not repeated here.

## Per-key facts the audit needs

| jq path | Value shape | Upstream scope | Failure when dangling |
|---|---|---|---|
| `(.hooks \| .. \| objects \| .command)` | command string | any | Non-blocking hook error on every tool call; the hook enforces nothing. Recursive over the hooks subtree, so new hook events need no change |
| `.statusLine.command` | command string | any | Status line blank |
| `.apiKeyHelper` | command string | any | No credential at all |
| `.awsCredentialExport`, `.awsAuthRefresh` | command string | any | Bedrock auth fails |
| `.otelHeadersHelper` | command string | any | OTEL export loses its dynamic headers |
| `.policyHelper.path` | absolute path | Managed only | **Claude Code refuses to start.** Sharpest of the set |
| `.sandbox.bwrapPath`, `.sandbox.socatPath` | absolute path | Managed only | Claude Code's own sandbox fails its dependency check / network proxy |
| `.sandbox.ripgrep.command` | absolute path (object with optional `args`) | User or managed | Sandboxed search tools lose ripgrep. `args` is not read |

## Classifying a candidate from the settings reference

Read the candidate's `### \`key\`` section for **Type** and **Scope**, then:

- Discard values that are a URL, number, boolean, or list of arguments. Only the executable is read — never an `args` sibling.
- A key documented as "User or managed" is still read from the managed files only (the user/project files are rw-mounted into the sandbox).
- Never widen to a subtree. `.sandbox` also holds `sandbox.credentials.files`, `sandbox.filesystem.denyRead` and `sandbox.filesystem.denyWrite` — the paths an admin listed precisely to keep hidden — so reading it whole would mount their directories, the same trap as `permissions.deny[]`.
- Bare paths and full command strings both go through the existing token loop; no second input class is needed.

## Checklist when adding a key

1. Add a `?`-guarded access (e.g. `.policyHelper?.path?`) to the jq array in `_mount_managed_config_paths`, and mention the key's failure mode in the function's header comment.
2. Extend the key list in the CLAUDE.md bullet "Executables named by managed settings are bound" and the README section "Managed settings executables".
3. Add a row to the table above.
4. Re-run `extract-vars.sh` and confirm the new path appears.

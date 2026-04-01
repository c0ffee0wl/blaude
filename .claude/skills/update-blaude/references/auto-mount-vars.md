# Auto-Mounted File/Path Variables

Some env vars point to files or directories that must be bind-mounted into the sandbox for Claude Code to access them. Simply passing through the env var is not enough — the file must also exist inside the sandbox.

## Currently auto-mounted

| Variable | Mount type | Condition |
|---|---|---|
| `CLAUDE_ENV_FILE` | `--ro-bind` (read-only) | File exists on host |
| `CLAUDE_CODE_PLUGIN_SEED_DIR` | `--ro-bind` (read-only) | Directory exists on host |
| `CLAUDE_CODE_PLUGIN_CACHE_DIR` | `--bind` (read-write) | Directory exists on host |
| `CLAUDE_CODE_DEBUG_LOGS_DIR` | `--bind` (read-write) | Directory exists on host |
| `CLAUDE_CODE_CLIENT_CERT` | `--ro-bind` (read-only) | File exists on host |
| `CLAUDE_CODE_CLIENT_KEY` | `--ro-bind` (read-only) | File exists on host |
| `AWS_WEB_IDENTITY_TOKEN_FILE` | `--ro-bind` (read-only) | File exists on host |
| `NODE_EXTRA_CA_CERTS` | `--ro-bind` (read-only) | File exists on host |
| `SSH_AUTH_SOCK` | `--bind` (read-write) | Socket exists, `--git` flag |
| `GOOGLE_APPLICATION_CREDENTIALS` | `--ro-bind` (read-only) | File exists, `--aws` flag |

## How to identify new vars that need mounting

When auditing new official env vars, check if any of them:

1. **Point to a file path** (cert, key, token file, config file)
2. **Point to a directory** (plugin dirs, cache dirs)
3. **Point to a socket** (D-Bus, SSH agent)

These need both:
- Passthrough of the env var value
- A `--ro-bind` or `--bind` mount of the path into the sandbox

### Naming patterns that suggest file/path vars

- `*_FILE` (e.g., `AWS_WEB_IDENTITY_TOKEN_FILE`)
- `*_CERT`, `*_KEY`, `*_CERTIFICATE` (mTLS/TLS files)
- `*_DIR` (directories)
- `*_PATH` (file or directory paths)
- `*_SOCK`, `*_SOCKET` (Unix sockets)
- `*_CREDENTIALS` (credential files like GCP service account JSON)

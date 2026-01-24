# blaude

Run [Claude Code](https://claude.ai/code) in a [bubblewrap](https://github.com/containers/bubblewrap) sandbox for security isolation.

## Why?

Claude Code with `--dangerously-skip-permissions` can execute arbitrary commands. blaude wraps it in a Linux sandbox that:

- Isolates filesystem access (only your project directory is writable)
- Drops all Linux capabilities
- Uses separate namespaces (PID, IPC, cgroup, UTS)
- Sanitizes environment variables
- Optionally disables network access

## Installation

```bash
# Install bubblewrap
sudo apt install bubblewrap  # Debian/Ubuntu
sudo dnf install bubblewrap  # Fedora/RHEL

# Install blaude
curl -o ~/.local/bin/blaude https://raw.githubusercontent.com/c0ffee0wl/blaude/main/blaude
chmod +x ~/.local/bin/blaude
```

Requires Claude Code installed and in PATH.

## Usage

```bash
# Run Claude Code in sandbox (current directory)
blaude

# Prompt mode
blaude -p "explain this codebase"

# Mount additional directories
blaude -m ~/shared-libs              # read-only
blaude -m ~/shared-libs:rw           # read-write

# Enable git commits from sandbox
blaude --git

# Enable SSH for GitHub auth
blaude --ssh

# Disable network access
blaude --no-network

# Run isolated (no workspace, workdir /tmp)
blaude --tmp

# Pass flags to claude
blaude -- --resume
blaude -- -c

# Run different command in sandbox
blaude -- bash
```

## Options

| Option | Description |
|--------|-------------|
| `-e KEY=VALUE` | Set environment variable in sandbox |
| `-m, --mount PATH` | Mount directory (append `:rw` for read-write) |
| `-p, --prompt TEXT` | Run claude with `-p` (prompt mode) |
| `--git` | Mount git config for committing |
| `--ssh` | Mount SSH keys and forward agent |
| `--no-network` | Disable network access |
| `--tmp` | Run isolated in /tmp |
| `-v, --verbose` | Show bwrap command before executing |
| `--dry-run` | Show command without executing |

## What's Mounted

| Path | Access | Purpose |
|------|--------|---------|
| `/usr`, `/lib*`, `/bin`, `/etc` | read-only | System binaries and libraries |
| `/workspaces/<dir>` | read-write | Your project (current directory) |
| `~/.claude` | read-write | Claude Code config |
| `~/.local/bin`, `~/.local/share/claude` | read-only | Claude binary and data |
| `~/.cache`, `~/go`, `~/.cargo`, `~/.npm` | ephemeral | Package manager caches (cleared on exit) |

## Environment Variables

LLM API keys are automatically passed through if set:

- `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`
- `OPENAI_API_KEY`, `AZURE_OPENAI_API_KEY`
- `GOOGLE_API_KEY`, `GEMINI_API_KEY`
- `AWS_*` (for Bedrock)
- And others (Mistral, Groq, Together, etc.)

## License

GPL-3.0

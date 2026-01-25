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

## Drop-in Replacement

blaude is a drop-in replacement for `claude`. All arguments not recognized by blaude are passed directly to the Claude Code CLI:

```bash
# These are equivalent (but blaude runs in a sandbox)
claude -p "hello"
blaude -p "hello"

claude --resume
blaude --resume

claude mcp list
blaude mcp list
```

To always run Claude Code in a sandbox, add an alias to your shell config:

```bash
# Add to ~/.bashrc or ~/.zshrc
alias claude=blaude
```

Commands that need to modify system files automatically bypass the sandbox:

| Command | Reason |
|---------|--------|
| `update` | Updates claude binary in `~/.local/bin` |
| `install` | Installs shell integration |
| `install-github-app` | Configures GitHub integration |

## Usage

```bash
# Run Claude Code in sandbox (current directory)
blaude

# Pass any claude options directly
blaude -p "explain this codebase"    # prompt mode
blaude -c                            # continue conversation
blaude -v                            # show claude version
blaude --resume                      # resume picker
blaude mcp list                      # MCP commands

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

# Mix blaude and claude options freely
blaude --git --ssh -c
blaude -c --git --ssh

# Run different command in sandbox
blaude --exec bash
```

## Options

| Option | Description |
|--------|-------------|
| `--env KEY=VALUE` | Set environment variable in sandbox |
| `-m, --mount PATH` | Mount directory (append `:rw` for read-write) |
| `--git` | Mount git config for committing |
| `--ssh` | Mount SSH keys and forward agent |
| `--no-network` | Disable network access |
| `--tmp` | Run isolated in /tmp |
| `--debug` | Show bwrap command before executing |
| `--dry-run` | Show command without executing |
| `--exec CMD` | Run CMD instead of claude |

All other options (like `-p`, `-c`, `-v`, `--resume`, etc.) pass directly to claude.

## What's Mounted

| Path | Access | Purpose |
|------|--------|---------|
| `/usr`, `/lib*`, `/bin`, `/etc` | read-only | System binaries and libraries |
| `/workspaces/<dir>` | read-write | Your project (current directory) |
| `~/.claude` | read-write | Claude Code config |
| `~/.local/bin`, `~/.local/share/claude` | read-only | Claude binary and data |
| `~/.cache`, `~/go`, `~/.cargo`, `~/.npm` | ephemeral | Package manager caches (cleared on exit) |

## Environment Variables

All [Claude Code environment variables](https://code.claude.com/docs/en/settings) are automatically passed through if set:

| Category | Variables |
|----------|-----------|
| **Authentication** | `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_CUSTOM_HEADERS`, `ANTHROPIC_FOUNDRY_*`, `AWS_BEARER_TOKEN_BEDROCK` |
| **Model Config** | `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL`, `CLAUDE_CODE_SUBAGENT_MODEL`, `MAX_THINKING_TOKENS`, `VERTEX_REGION_*` |
| **Bash/Commands** | `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_*`, `CLAUDE_CODE_SHELL`, `CLAUDE_CODE_SHELL_PREFIX`, `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS` |
| **Token Limits** | `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS`, `MAX_MCP_OUTPUT_TOKENS` |
| **Cloud Providers** | `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`, `CLAUDE_CODE_SKIP_*_AUTH`, `AWS_*` |
| **MCP** | `MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `ENABLE_TOOL_SEARCH` |
| **UI/Display** | `CLAUDE_CODE_HIDE_ACCOUNT_INFO`, `CLAUDE_CODE_DISABLE_TERMINAL_TITLE`, `IS_DEMO`, `DISABLE_COST_WARNINGS` |
| **Advanced** | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `DISABLE_PROMPT_CACHING*`, `SLASH_COMMAND_TOOL_CHAR_BUDGET` |
| **Proxy** | `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `CLAUDE_CODE_PROXY_RESOLVES_HOSTS` |
| **Other LLM APIs** | `OPENAI_API_KEY`, `AZURE_OPENAI_*`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, etc. |

Use `--env KEY=VALUE` to pass additional variables not in this list.

## License

GPL-3.0

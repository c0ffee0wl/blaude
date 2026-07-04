# blaude

Run [Claude Code](https://claude.ai/code) in a [bubblewrap](https://github.com/containers/bubblewrap) sandbox for security isolation.

## Why?

Claude Code with `--dangerously-skip-permissions` can execute arbitrary commands. blaude automatically runs Claude with this flag inside a Linux sandbox, so you get full autonomous operation without (most of) the risk.

> **What "most of" means**: bwrap is not a security boundary against kernel exploits, `/tmp` is shared with the host by default (use `--clear-tmp` for an isolated tmpfs), and MCP servers plus any directories you bind-mount still have host reach. Treat this as attack-surface reduction, not a zero-trust container.

The sandbox provides:

- Isolates filesystem access (tmpfs `$HOME` with writable access to project dir, `~/.claude`, `~/.config`, and package caches; system directories read-only)
- Protects dangerous files from writes (shell rc files, `.gitconfig`, `.git/hooks/`, `.git/config`, `.vscode/`, `.idea/`, `.mcp.json`, `.ripgreprc` — in the workspace only; override with `--allow-protected-writes`)
- Drops all Linux capabilities (`--cap-drop ALL`)
- Uses separate namespaces (PID, IPC, UTS, user; plus optional network namespace with `--no-network`)
- Sanitizes environment variables (`--clearenv` with an explicit passthrough allowlist; disable with `--keep-env`)

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
| `--git` | Mount git config, GPG agent socket (for signed commits), and pass `GH_TOKEN`/`GITHUB_TOKEN` |
| `--ssh` | Mount SSH keys and forward agent (binds the socket's parent dir for systemd-tmpfile rotation) |
| `--aws` | Mount `~/.aws` read-only (for Bedrock auth) |
| `--no-network` | Disable network access |
| `--keyring` | Enable GNOME Keyring access (for keytar) |
| `--keep-env` | Keep the entire host environment instead of clearing it |
| `--chic` | Run [claudechic](https://github.com/mrocklin/claudechic) TUI instead of claude |
| `--tmp` | Run isolated in /tmp |
| `--clear-tmp` | Use empty tmpfs for /tmp instead of mounting host's /tmp |
| `--allow-protected-writes` | Allow writes to [protected files](#protected-workspace-paths) |
| `--debug` | Show bwrap command before executing |
| `--dry-run` | Show command without executing |
| `--exec CMD` | Run CMD instead of claude |
| `--no-clipboard` | Disable OSC 52 clipboard interception |
| `fix-apparmor` | Install AppArmor profile for bwrap (Ubuntu 24.04+, requires sudo) |

All other options (like `-p`, `-c`, `-v`, `--resume`, etc.) pass directly to claude.

## What's Mounted

| Path | Access | Purpose |
|------|--------|---------|
| `/usr`, `/lib*`, `/bin`, `/etc` | read-only | System binaries and libraries |
| `/run/user/<uid>` | tmpfs | Empty XDG runtime dir; `XDG_RUNTIME_DIR` set accordingly. Wayland/PipeWire/D-Bus sockets only appear via opt-in (`--keyring` for D-Bus). |
| `/tmp` | read-write | Host's /tmp (use `--clear-tmp` for isolated tmpfs) |
| `/workspaces/<dir>` | read-write | Your project (current directory) |
| `~/.claude` | read-write | Claude Code config (includes claudechic config) |
| `~/.config/` | read-write | User config (uv, fabric, google-chrome, etc.) |
| `~/.notebooklm-mcp/`, `~/.notebooklm-mcp-cli/` | read-write | notebooklm-mcp auth and Chrome profile |
| `~/.claude-mem/` | read-write | Persistent memory across sessions (auto-created if claude-mem plugin is installed) |
| `~/arxiv-storage/` | read-write | Research paper management tools |
| `~/.nvm/` | read-only | Node Version Manager (if installed; current node bin added to PATH) |
| `~/.bun/` | read-only | Bun runtime and packages (`~/.bun/bin` in PATH; `install/cache` gets a tmpfs overlay) |
| `~/.npm/` | read-write | npm cache bound from host if it exists, otherwise ephemeral scaffold |
| `~/.local/share/claude`, `~/.local/share/pipx`, `~/.local/share/uv/{tools,python}` | read-only | Claude data and tool-manager venvs |
| `~/.local/bin` → `/opt/host-bin` | read-only | Host user binaries re-mounted under `/opt/` and added to PATH (the `claude` binary is also bound at its original path) |
| `~/.cargo/bin` → `/opt/host-cargo-bin`, `~/go/bin` → `/opt/host-go-bin` | read-only | Cargo/Go bins re-mounted under `/opt/` and added to PATH |
| `/opt/<vendor>/…` (pwsh, Chrome, Chromium, Edge, Brave, dotnet) | read-only | Tools whose `/usr/bin` launcher is a symlink into `/opt` — the install dir is auto-bound so the symlink resolves in-sandbox (the empty `--dir /opt` otherwise shadows it). Only for tools present on the host. Chrome/Chromium need `--no-sandbox` under bwrap; snap installs (resolving to `/snap`) are skipped. |
| `~/.cache/uv` | read-write | uv cache bound from host if it exists |
| `~/.cache`, `~/go`, `~/.cargo` | ephemeral | Scaffolded on a tmpfs `$HOME` — cleared on exit |

## MCP Server Token Storage

MCP servers like [ms-365-mcp](https://github.com/softeria/ms-365-mcp-server) need to persist authentication tokens. blaude handles this automatically:

- **npm-linked packages**: Token files (`.token-cache.json`, `.selected-account.json`) at package root are mounted read-write
- **By default**: D-Bus/keytar disabled, forcing file-based storage (more reliable in containers)
- **With `--keyring`**: Enables GNOME Keyring access for keytar-based storage

If you have GNOME Keyring properly configured (unlocked at login), use `--keyring` for secure credential storage.

## claudechic Support

[claudechic](https://github.com/mrocklin/claudechic) is a Python-based TUI wrapper for Claude Code. Use `--chic` to run it inside the sandbox:

```bash
blaude --chic              # Run claudechic in sandbox
blaude --chic -c           # Continue conversation via claudechic
```

Config file (`~/.claude/.claudechic.yaml`) is writable via the `~/.claude` mount.

## User Config Directory

The entire `~/.config/` directory is mounted read-write if it exists. This includes:

- **uv config** (`~/.config/uv/uv.toml`) - Python preference settings (e.g., `python-preference = "system"`)
- **Fabric** (`~/.config/fabric/`) - Patterns, sessions, contexts, strategies, extensions, OAuth tokens, `.env`
- **Google Chrome** (`~/.config/google-chrome/`) - Browser profile for automation (Puppeteer, Playwright, OAuth flows)
- Other tool configurations as needed

> **Note:** `~/.config/git/` (the XDG global git config) is the one exception — it is re-shadowed read-only (or as an ephemeral tmpfs if absent) on top of the read-write mount. git settings there (aliases, `core.pager`/`editor`/`fsmonitor`, `core.sshCommand`) execute on the *host* at the next git run outside the sandbox, so the sandbox cannot write them. Override with `--allow-protected-writes`.

```bash
# Setup fabric outside sandbox first
fabric --setup

# Then use normally inside sandbox
blaude --exec fabric -p "summarize"
```

## notebooklm-mcp Support

[notebooklm-mcp](https://github.com/c0ffee0wl/notebooklm-mcp) is an MCP server for NotebookLM. blaude automatically mounts `~/.notebooklm-mcp/` for auth persistence:

```bash
# Authenticate outside sandbox first (requires browser)
notebooklm-mcp-auth

# Then use normally - MCP server reads cached tokens inside sandbox
blaude
```

The directory stores `auth.json` (cookies/CSRF/session) and `chrome-profile/` for automatic re-authentication.

## Environment Variables

All [Claude Code environment variables](https://code.claude.com/docs/en/env-vars) are automatically passed through if set:

> **Prefix passthrough**: every `ANTHROPIC_*` and `CLAUDE_*` host env var is auto-passed via the env scanning loop. No matching against a hard-coded list — the Anthropic namespace is owned, so new upstream env vars are picked up automatically. The table below lists representative examples for those rows, not an exhaustive set.

> **Non-prefix passthrough**: rows that don't start with `ANTHROPIC_`/`CLAUDE_` come from blaude's explicit `claude_env_vars` allowlist. Here `*` is a shorthand for a specific enumerated list — e.g. `AWS_*` means `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_BEARER_TOKEN_BEDROCK` — not a wildcard. Variables not in the allowlist won't pass through; use `--env KEY=VALUE` for those.

> **Forced env-vars**: a small set of variables is hardcoded in the sandbox and overrides the host value (also under `--keep-env`) to keep blaude's auto-skip behaviour working: `DO_NOT_TRACK=1`, `DISABLE_TELEMETRY=1`, `DISABLE_AUTOUPDATER=1`, `DISABLE_ERROR_REPORTING=1`, `DISABLE_BUG_COMMAND=1`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1`, `DISABLE_INSTALL_GITHUB_APP_COMMAND=1`, `CLAUDE_DISABLE_CONFIG_WATCH=1`, `DISABLE_GROWTHBOOK=1`. These are kept in a deny-set so the `CLAUDE_*` prefix match cannot resurrect their host values. Additionally, the following are force-*unset* inside the sandbox (via `--unsetenv`): **`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`** — any defined value, even `=0`, triggers permission-mode hardening that overrides `--dangerously-skip-permissions` (`"Permission mode forced to default — CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set …"`), so blaude drops it to match the documented default (unset = disabled); and **`CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_BRIDGE_SESSION_ID`, `CLAUDE_PROJECT_DIR`** — outer-claude subprocess markers (parent binary identity, parent session UUID, parent Remote Control session ID, parent cwd) that would otherwise leak into the sandboxed inner claude when blaude is invoked from inside another claude session.

> **Settings-file blocker detection**: at startup, blaude scans `~/.claude/settings.json`, `$CLAUDE_CONFIG_DIR/settings.json`, `/etc/claude-code/managed-settings.json`, and `/etc/claude-code/managed-settings.d/*.json` for `permissions.disableBypassPermissionsMode: "disable"`. That key blocks `--dangerously-skip-permissions` independently of any env var — and managed (enterprise) settings cannot be overridden by blaude. If detected, a clear warning is printed; remove the key (or change the value) to restore bypass mode.

| Category | Variables |
|----------|-----------|
| **Anthropic namespace (prefix-matched)** | Any variable starting with `ANTHROPIC_` (e.g., `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_BETAS`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL*`, `ANTHROPIC_BEDROCK_*`, `ANTHROPIC_FOUNDRY_*`, `ANTHROPIC_VERTEX_*`, `ANTHROPIC_WORKSPACE_ID`, …) |
| **Claude Code namespace (prefix-matched)** | Any variable starting with `CLAUDE_` (e.g., `CLAUDE_CODE_OAUTH_*`, `CLAUDE_CODE_USE_BEDROCK`/`_VERTEX`/`_FOUNDRY`/`_MANTLE`, `CLAUDE_CODE_MAX_*_TOKENS`, `CLAUDE_CODE_DISABLE_*`, `CLAUDE_CODE_ENABLE_*`, `CLAUDE_CODE_PLUGIN_*`, `CLAUDE_CODE_DEBUG_*`, `CLAUDE_CODE_OTEL_*`, `CLAUDE_CODE_CLIENT_*`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`, `CLAUDE_ENV_FILE`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_SKILL_DIR`, `CLAUDE_AGENT_SDK_*`, `CLAUDE_EFFORT`, …) |
| **VERTEX_REGION_CLAUDE_*** | Region overrides for each Claude model on Vertex AI (`VERTEX_REGION_CLAUDE_3_5_HAIKU`, `VERTEX_REGION_CLAUDE_3_5_SONNET`, `VERTEX_REGION_CLAUDE_4_5_OPUS`, … through `VERTEX_REGION_CLAUDE_4_8_OPUS`, `VERTEX_REGION_CLAUDE_HAIKU_4_5`, `VERTEX_REGION_CLAUDE_FABLE_5`, `VERTEX_REGION_CLAUDE_5_SONNET`, `VERTEX_REGION_DEFAULT`, `VERTEX_REGION_SMALL_FAST_MODEL`) |
| **AWS** | `AWS_BEARER_TOKEN_BEDROCK`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` |
| **Google Cloud** | `GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`, `VERTEX_AI_PROJECT_ID`, `VERTEX_AI_API_ENDPOINT`, `CLOUD_RUN_JOB_ATTEMPT`, `CLOUD_ML_REGION` |
| **GitHub** (requires `--git`) | `GH_TOKEN`, `GITHUB_TOKEN` |
| **GPG** (socket bound under `--git`) | `GPG_TTY`, `GNUPGHOME` |
| **MCP standards** | `MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `MCP_CONNECT_TIMEOUT_MS`, `MCP_ENABLED`, `MCP_OAUTH_CALLBACK_PORT`, `MCP_CLIENT_SECRET`, `MCP_SSE_URL`, `ENABLE_TOOL_SEARCH`, `ENABLE_CLAUDEAI_MCP_SERVERS`, `MCP_CONNECTION_NONBLOCKING`, `MCP_SERVER_*` (glob; covers env-based `MCP_SERVER_<ID>` server config and `MCP_SERVER_CONNECTION_BATCH_SIZE`), `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE` |
| **OpenTelemetry** | `OTEL_*` (full set: exporter config, OTLP endpoints/protocols for metrics/logs/traces, client cert/key, log level toggles incl. `OTEL_LOG_RAW_API_BODIES`, resource attributes, etc.), `TRACEPARENT`, `TRACESTATE` |
| **Bash / shell** | `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_OUTPUT_LENGTH`, `BASH_MAX_TIMEOUT_MS` |
| **Tokens & retries** | `MAX_THINKING_TOKENS`, `MAX_MCP_OUTPUT_TOKENS`, `MAX_STRUCTURED_OUTPUT_RETRIES`, `TASK_MAX_OUTPUT_LENGTH`, `SLASH_COMMAND_TOOL_CHAR_BUDGET`, `API_TIMEOUT_MS`, `API_FORCE_IDLE_TIMEOUT`, `FALLBACK_FOR_ALL_PRIMARY_MODELS` |
| **Network/TLS** | `HTTP_PROXY`, `HTTPS_PROXY`, `SOCKS_PROXY`, `NO_PROXY`, `NODE_EXTRA_CA_CERTS`, `USE_BUILTIN_CA_BUNDLE`, `USE_SYSTEM_CA`, `NODE_TLS_REJECT_UNAUTHORIZED` |
| **Updates/Installation** | `FORCE_AUTOUPDATE_PLUGINS`, `DISABLE_INSTALLATION_CHECKS`, `DISABLE_UPDATES`, `DISABLE_UPGRADE_COMMAND`, `DISABLE_DOCTOR_COMMAND`, `DISABLE_EXTRA_USAGE_COMMAND`, `DISABLE_LOGIN_COMMAND`, `DISABLE_LOGOUT_COMMAND`, `DISABLE_FEEDBACK_COMMAND` |
| **Caching & compaction** | `DISABLE_PROMPT_CACHING*`, `DISABLE_NON_ESSENTIAL_MODEL_CALLS`, `DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`, `DISABLE_INTERLEAVED_THINKING`, `ENABLE_PROMPT_CACHING_1H`, `ENABLE_PROMPT_CACHING_1H_BEDROCK`, `FORCE_PROMPT_CACHING_5M` |
| **Runtime indicators / misc** | `IS_DEMO`, `FORCE_HYPERLINK`, `USE_BUILTIN_RIPGREP`, `CCR_FORCE_BUNDLE`, `CLAUDECODE`, `AI_AGENT`, `DEBUG`, `DISABLE_COST_WARNINGS`, `CI`, `NO_COLOR`, `FORCE_COLOR` |
| **Other LLM APIs** | `OPENAI_API_KEY`, `OPENAI_API_BASE`, `OPENAI_ORG_ID`, `AZURE_OPENAI_*`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, `COHERE_API_KEY`, `HUGGINGFACE_API_KEY`, `HF_TOKEN`, `GROQ_API_KEY`, `TOGETHER_API_KEY`, `REPLICATE_API_TOKEN`, `PERPLEXITY_API_KEY`, `FIREWORKS_API_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY`, `JINA_API_KEY`, `EXA_API_KEY` |
| **Third-party Services** | `FEEDLY_ACCESS_TOKEN`, `RAINDROP_ACCESS_TOKEN` |
| **claudechic** | `CLAUDECHIC_DEBUG`, `CLAUDECHIC_REMOTE_PORT`, `CHIC_PROFILE`, `CHIC_SAMPLE_THRESHOLD` |
| **notebooklm-mcp** | `NOTEBOOKLM_COOKIES`, `NOTEBOOKLM_CSRF_TOKEN`, `NOTEBOOKLM_SESSION_ID`, `NOTEBOOKLM_MCP_*` |
| **claude-mem** | Any variable starting with `CLAUDE_MEM_` (covered by the `CLAUDE_*` prefix match — e.g., `CLAUDE_MEM_DATA_DIR`, `CLAUDE_MEM_WORKER_PORT`) |
| **Webhooks** | Any variable ending in `_WEBHOOK` (e.g., `SLACK_WEBHOOK`, `DISCORD_WEBHOOK`) |
| **Webshare** | Any variable starting with `WEBSHARE_` (e.g., `WEBSHARE_API_KEY`, `WEBSHARE_PROXY`) |

Use `--env KEY=VALUE` to pass additional variables not covered above.

## Protected Workspace Paths

Inspired by Anthropic's [sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime), blaude write-protects files and directories inside the workspace that could be used to execute code *outside* the sandbox. A sandboxed agent running with `--dangerously-skip-permissions` has full write access to the workspace — without this protection, it could plant a malicious `.git/hooks/pre-commit` or `.bashrc` that runs the next time you open a shell or make a commit on the host.

sandbox-runtime enforces this using ripgrep-based scanning with `/dev/null` overlays and symlink neutralization. blaude uses a similar technique adapted for its bash/bwrap architecture, with zero host filesystem artifacts:

- **Existing files**: `--ro-bind` from host (preserves content, blocks writes)
- **Existing directories**: `--tmp-overlay` (content readable, writes succeed but are ephemeral — never reach host). Requires bwrap ≥ 0.8.0; older bwrap falls back to `--ro-bind`, which still blocks writes but may create host stubs for non-existent targets.
- **Non-existent directories**: parent directory is overlaid instead (e.g., if `.git/hooks/` is missing, `.git/` is overlaid to prevent hooks creation)
- **Root-level dotfiles** (`.bashrc` etc.): only protected if they exist (no parent to overlay; low risk since uncommon in project directories)
- **Git worktrees**: `.git/*` paths are only protected when `.git` is a directory (not a file, as in worktrees)
- **Nested paths** (monorepos, git submodules, vendored deps): the same protection is applied to matches found by a `find` scan up to depth 3 (e.g. `packages/app/.git/hooks/`, `packages/lib/.bashrc`)
- **Workspace symlinks**: a pre-flight scan (`find -maxdepth 4 -type l`) warns about symlinks pointing outside the workspace tree and outside known-safe system paths (`/usr`, `/lib*`, `/bin`, `/sbin`, `/etc`, `/proc`, `/sys`, `/dev`). bwrap mounts don't follow these, but combined with `-m ...:rw` they could expose unintended host paths.

### Protected files

| Path | Risk |
|------|------|
| `.bashrc`, `.bash_profile`, `.bash_login`, `.profile` | Execute on shell open |
| `.zshrc`, `.zprofile`, `.zshenv`, `.zlogin` | Execute on zsh open |
| `.gitconfig`, `.gitmodules` | Git config manipulation, submodule URL hijacking |
| `.git/config` | Can set `core.hooksPath`, `core.fsmonitor` for code execution |
| `.ripgreprc` | Alters search tool behavior |
| `.mcp.json` | MCP server configuration |

### Protected directories

| Path | Risk |
|------|------|
| `.git/hooks/` | Arbitrary code execution on git operations |
| `.vscode/` | VS Code tasks and launch configs can execute commands |
| `.idea/` | JetBrains run configurations can execute commands |

Use `--allow-protected-writes` if you need full workspace access (e.g., developing git hooks). This also bypasses the `$HOME` workspace/mount rejection:

```bash
blaude --allow-protected-writes
```

## Clipboard Support

VTE-based terminals (Terminator, GNOME Terminal, XFCE Terminal) don't support OSC 52 clipboard sequences. Claude Code uses OSC 52 for clipboard operations, so copying silently fails on these terminals.

blaude ships `osc52-clipboard`, a companion script that intercepts OSC 52 sequences and copies to the system clipboard via `xclip`, `xsel`, or `wl-copy`. It activates automatically when `osc52-clipboard` is found (same directory as blaude, or on PATH). Disable with `--no-clipboard` or `OSC52_NO_CLIPBOARD=1`.

Requires one of: `xclip`, `xsel` (X11), or `wl-copy` (Wayland).

## Asciinema Support

When running inside [asciinema](https://asciinema.org/) (`ASCIINEMA_REC=1`), blaude pauses the recording for the duration of the Claude session. The asciinema process is stopped (SIGSTOP) before the sandbox starts and resumed (SIGCONT) when it exits. The recording continues seamlessly after Claude exits.

blaude finds the asciinema process by walking the `/proc` ancestor chain. If detection fails, the sandbox runs normally without pausing.

## Troubleshooting

### Ubuntu 24.04+: "Operation not permitted"

Ubuntu 24.04+ restricts unprivileged user namespaces via AppArmor by default. Since bwrap relies on user namespaces, blaude will fail with `Operation not permitted` or similar errors.

blaude detects this automatically and prints a warning. To fix:

```bash
blaude fix-apparmor
```

This installs an AppArmor profile at `/etc/apparmor.d/bwrap` that allows bwrap to create user namespaces (requires sudo). The profile is minimal:

```
abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,

  include if exists <local/bwrap>
}
```

You only need to run this once. The fix is idempotent — running it again is a no-op.

## License

Apache-2.0 — see [LICENSE](LICENSE).

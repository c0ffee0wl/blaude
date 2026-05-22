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

> **Note on `*` below**: except for the three rows explicitly called out as glob patterns (**claude-mem**, **Webhooks**, **Webshare**), the `*` is a shorthand for a specific enumerated list — e.g. `AWS_*` means `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` — not a wildcard. Variables not enumerated in blaude's `claude_env_vars` array won't pass through; use `--env KEY=VALUE` for those.

> **Forced env-vars**: a small set of variables is hardcoded in the sandbox and overrides the host value (also under `--keep-env`) to keep blaude's auto-skip behaviour working: `DO_NOT_TRACK=1`, `DISABLE_TELEMETRY=1`, `DISABLE_AUTOUPDATER=1`, `DISABLE_ERROR_REPORTING=1`, `DISABLE_BUG_COMMAND=1`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1`, `DISABLE_INSTALL_GITHUB_APP_COMMAND=1`, `CLAUDE_DISABLE_CONFIG_WATCH=1`, `DISABLE_GROWTHBOOK=1`. Additionally, **`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is force-*unset*** inside the sandbox (via `--unsetenv`): any defined value — even `=0` — triggers permission-mode hardening that overrides `--dangerously-skip-permissions` and prints *"Permission mode forced to default — CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set …"*, so blaude drops it entirely to match the documented default (unset = disabled).

> **Settings-file blocker detection**: at startup, blaude scans `~/.claude/settings.json`, `$CLAUDE_CONFIG_DIR/settings.json`, `/etc/claude-code/managed-settings.json`, and `/etc/claude-code/managed-settings.d/*.json` for `permissions.disableBypassPermissionsMode: "disable"`. That key blocks `--dangerously-skip-permissions` independently of any env var — and managed (enterprise) settings cannot be overridden by blaude. If detected, a clear warning is printed; remove the key (or change the value) to restore bypass mode.

| Category | Variables |
|----------|-----------|
| **Authentication** | `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_BETAS`, `ANTHROPIC_CUSTOM_HEADERS`, `ANTHROPIC_FOUNDRY_*`, `ANTHROPIC_BEDROCK_BASE_URL`, `ANTHROPIC_BEDROCK_MANTLE_BASE_URL`, `ANTHROPIC_BEDROCK_SERVICE_TIER`, `ANTHROPIC_AWS_API_KEY`, `ANTHROPIC_AWS_BASE_URL`, `ANTHROPIC_AWS_WORKSPACE_ID`, `ANTHROPIC_VERTEX_BASE_URL`, `ANTHROPIC_WORKSPACE_ID`, `AWS_BEARER_TOKEN_BEDROCK`, `CLAUDE_CODE_OAUTH_*`, `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY`, `CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST` |
| **Model Config** | `ANTHROPIC_MODEL`, `ANTHROPIC_SMALL_FAST_MODEL`, `ANTHROPIC_CUSTOM_MODEL_OPTION*`, `ANTHROPIC_DEFAULT_*_MODEL*`, `CLAUDE_CODE_SUBAGENT_MODEL`, `CLAUDE_CODE_EFFORT_LEVEL`, `CLAUDE_CODE_ENABLE_OPUS_4_7_FAST_MODE`, `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE`, `MAX_THINKING_TOKENS`, `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`, `CLAUDE_CODE_DISABLE_FAST_MODE`, `CLAUDE_CODE_DISABLE_1M_CONTEXT`, `API_TIMEOUT_MS`, `CLAUDE_CODE_MAX_RETRIES`, `CLAUDE_CODE_RETRY_BACKOFF_BASE_MS`, `CLAUDE_CODE_RETRY_BACKOFF_MAX_MS`, `VERTEX_REGION_*` |
| **Bash/Commands** | `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_*`, `CLAUDE_CODE_SHELL`, `CLAUDE_CODE_SHELL_PREFIX`, `CLAUDE_EFFORT`, `CLAUDE_CODE_SCRIPT_CAPS`, `CLAUDE_CODE_PERFORCE_MODE`, `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS`, `CLAUDE_BASH_NO_LOGIN`, `CLAUDE_CODE_GLOB_*` |
| **Token Limits** | `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, `CLAUDE_CODE_FILE_READ_MAX_OUTPUT_TOKENS`, `MAX_MCP_OUTPUT_TOKENS`, `CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY`, `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, `CLAUDE_CODE_MAX_TURNS`, `CLAUDE_ASYNC_AGENT_STALL_TIMEOUT_MS`, `MAX_STRUCTURED_OUTPUT_RETRIES`, `TASK_MAX_OUTPUT_LENGTH`, `CLAUDE_CODE_TASK_COMPRESSION_TOKEN_THRESHOLD` |
| **Cloud Providers** | `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY`, `CLAUDE_CODE_USE_MANTLE`, `CLAUDE_CODE_USE_ANTHROPIC_AWS`, `CLAUDE_CODE_SKIP_*_AUTH`, `CLAUDE_CODE_ACCOUNT_UUID`, `CLAUDE_CODE_USER_EMAIL`, `CLAUDE_CODE_ORGANIZATION_UUID`, `AWS_*`, `CLOUD_ML_REGION`, `CLAUDE_CODE_VERTEX_REGION` |
| **Google Cloud** | `GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`, `CLOUD_RUN_JOB_ATTEMPT` |
| **MCP** | `MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `MCP_CONNECT_TIMEOUT_MS`, `MCP_OAUTH_CALLBACK_PORT`, `MCP_CLIENT_SECRET`, `MCP_SSE_URL`, `ENABLE_TOOL_SEARCH`, `ENABLE_CLAUDEAI_MCP_SERVERS`, `MCP_CONNECTION_NONBLOCKING`, `MCP_SERVER_CONNECTION_BATCH_SIZE`, `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE`, `CLAUDE_CODE_MCP_SERVER_NAME`, `CLAUDE_CODE_MCP_SERVER_URL`, `CLAUDE_CODE_MCP_ALLOWLIST_ENV` |
| **Telemetry** | `CLAUDE_CODE_ENABLE_TELEMETRY`, `CLAUDE_CODE_ENABLE_FEEDBACK_SURVEY_FOR_OTEL`, `CLAUDE_CODE_OTEL_*`, `OTEL_*` (metrics, logs, exporter config, `OTEL_LOG_RAW_API_BODIES`), `TRACEPARENT`, `TRACESTATE`, `DISABLE_COST_WARNINGS` |
| **UI/Display** | `CLAUDE_CODE_HIDE_ACCOUNT_INFO`, `CLAUDE_CODE_HIDE_CWD`, `CLAUDE_CODE_DISABLE_TERMINAL_TITLE`, `CLAUDE_CODE_DISABLE_MOUSE`, `CLAUDE_CODE_DISABLE_VIRTUAL_SCROLL`, `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN`, `CLAUDE_CODE_ALT_SCREEN_FULL_REPAINT`, `CLAUDE_CODE_FORCE_SYNC_OUTPUT`, `CLAUDE_CODE_NATIVE_CURSOR`, `CLAUDE_CODE_NO_FLICKER`, `CLAUDE_CODE_SCROLL_SPEED`, `CLAUDE_CODE_ACCESSIBILITY`, `CLAUDE_CODE_SYNTAX_HIGHLIGHT`, `CLAUDE_CODE_ATTRIBUTION_HEADER`, `CLAUDE_CODE_TMUX_TRUECOLOR`, `CLAUDE_CODE_SKIP_PROMPT_HISTORY`, `CLAUDE_CODE_AUTO_CONNECT_IDE`, `FORCE_HYPERLINK`, `IS_DEMO` |
| **Development** | `CLAUDECODE`, `CLAUDE_CODE_DEBUG_LOGS_DIR`, `CLAUDE_CODE_DEBUG_LOG_LEVEL`, `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_REMOTE_SESSION_ID`, `CLAUDE_CODE_SESSION_ID`, `AI_AGENT` |
| **File/Directory Config** | `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`, `USE_BUILTIN_RIPGREP`, `CLAUDE_ENV_FILE`, `CLAUDE_CODE_PLUGIN_SEED_DIR`, `CLAUDE_CODE_PLUGIN_CACHE_DIR`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_SKILL_DIR`, `CLAUDE_CODE_WORKSPACE_DIR`, `CCR_FORCE_BUNDLE` |
| **Credential/mTLS** | `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`, `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_CLIENT_KEY`, `CLAUDE_CODE_CLIENT_KEY_PASSPHRASE` |
| **Network/TLS** | `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `CLAUDE_CODE_PROXY_RESOLVES_HOSTS`, `NODE_EXTRA_CA_CERTS`, `CLAUDE_CODE_CERT_STORE`, `CLAUDE_CODE_TLS_MIN_VERSION` |
| **Updates/Installation** | `FORCE_AUTOUPDATE_PLUGINS`, `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE`, `CLAUDE_CODE_PLUGIN_GIT_TIMEOUT_MS`, `CLAUDE_CODE_PLUGIN_PREFER_HTTPS`, `DISABLE_INSTALLATION_CHECKS`, `DISABLE_UPGRADE_COMMAND`, `DISABLE_DOCTOR_COMMAND`, `DISABLE_UPDATES`, `CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE`, `CLAUDE_CODE_SYNC_PLUGIN_INSTALL*` |
| **Memory** | `CLAUDE_CODE_DISABLE_AUTO_MEMORY` |
| **Features** | `CLAUDE_CODE_SIMPLE`, `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT`, `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`, `CLAUDE_CODE_DISABLE_CRON`, `CLAUDE_CODE_DISABLE_POLICY_SKILLS`, `CLAUDE_CODE_DISABLE_AGENT_VIEW`, `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, `CLAUDE_CODE_ENABLE_TASKS`, `CLAUDE_CODE_PLAN_MODE_REQUIRED`, `CLAUDE_CODE_TEAM_NAME`, `CLAUDE_CODE_DISABLE_ATTACHMENTS`, `CLAUDE_CODE_DISABLE_CLAUDE_MDS`, `CLAUDE_CODE_RESUME_PROMPT`, `CLAUDE_CODE_USE_NATIVE_FILE_SEARCH`, `CLAUDE_CODE_ENABLE_AWAY_SUMMARY`, `CLAUDE_CODE_ENABLE_BACKGROUND_PLUGIN_REFRESH`, `CLAUDE_CODE_USE_POWERSHELL_TOOL`, `CLAUDE_CODE_FORK_SUBAGENT`, `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, `CLAUDE_CODE_SYNC_TOOL_CALL_RESULTS`, `CLAUDE_CODE_SPAWN_SUBAGENT_KEEP_INTERRUPTED_CONTEXT`, `CLAUDE_AUTO_BACKGROUND_TASKS`, `CLAUDE_AGENT_SDK_*`, `CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX` |
| **Advanced** | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_CODE_EXTRA_BODY`, `DISABLE_PROMPT_CACHING*`, `SLASH_COMMAND_TOOL_CHAR_BUDGET`, `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD`, `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS`, `CLAUDE_ENABLE_BYTE_WATCHDOG`, `CLAUDE_ENABLE_BYTE_WATCHDOG_BEDROCK`, `DISABLE_AUTO_COMPACT`, `DISABLE_INTERLEAVED_THINKING`, `ENABLE_PROMPT_CACHING_1H`, `ENABLE_PROMPT_CACHING_1H_BEDROCK`, `FORCE_PROMPT_CACHING_5M` |
| **GitHub** (requires `--git`) | `GH_TOKEN`, `GITHUB_TOKEN` |
| **GPG** (socket bound under `--git`) | `GPG_TTY`, `GNUPGHOME` |
| **Other LLM APIs** | `OPENAI_API_KEY`, `AZURE_OPENAI_*`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY`, `JINA_API_KEY`, `EXA_API_KEY`, `GROQ_API_KEY`, `HF_TOKEN`, etc. |
| **Third-party Services** | `FEEDLY_ACCESS_TOKEN`, `RAINDROP_ACCESS_TOKEN` |
| **claudechic** | `CLAUDECHIC_DEBUG`, `CLAUDECHIC_REMOTE_PORT`, `CHIC_PROFILE`, `CHIC_SAMPLE_THRESHOLD` |
| **notebooklm-mcp** | `NOTEBOOKLM_COOKIES`, `NOTEBOOKLM_CSRF_TOKEN`, `NOTEBOOKLM_SESSION_ID`, `NOTEBOOKLM_MCP_*` |
| **claude-mem** | Any variable starting with `CLAUDE_MEM_` (e.g., `CLAUDE_MEM_DATA_DIR`, `CLAUDE_MEM_WORKER_PORT`) |
| **Webhooks** | Any variable ending in `_WEBHOOK` (e.g., `SLACK_WEBHOOK`, `DISCORD_WEBHOOK`) |
| **Webshare** | Any variable starting with `WEBSHARE_` (e.g., `WEBSHARE_API_KEY`, `WEBSHARE_PROXY`) |

Use `--env KEY=VALUE` to pass additional variables not in this list.

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
| `.bashrc`, `.bash_profile`, `.profile` | Execute on shell open |
| `.zshrc`, `.zprofile` | Execute on zsh open |
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

# blaude

Run [Claude Code](https://claude.ai/code) in a [bubblewrap](https://github.com/containers/bubblewrap) sandbox for security isolation.

## Why?

Claude Code with `--dangerously-skip-permissions` can execute arbitrary commands. blaude automatically runs Claude with this flag inside a Linux sandbox, so you get full autonomous operation without (most of) the risk.

> **What "most of" means**: bwrap is not a security boundary against kernel exploits, `/tmp` is shared with the host by default (use `--clear-tmp` for an isolated tmpfs), and MCP servers plus any directories you bind-mount still have host reach. Treat this as attack-surface reduction, not a zero-trust container.

The sandbox:

- Isolates filesystem access (tmpfs `$HOME`; the project dir and `~/.claude` stay writable, `~/.config` and the package caches become write-discarding overlays, system directories are read-only)
- Protects dangerous files from writes (shell rc files, `.gitconfig`, `.git/hooks/`, `.git/config`, `.vscode/`, `.idea/`, `.mcp.json`, `.ripgreprc`, in the workspace only; override with `--allow-protected-writes`)
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

## Drop-in replacement

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
| `--remote-control` | Prepare the session for [Remote Control](#remote-control), so `/remote-control` works on demand |
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

## What's mounted

| Path | Access | Purpose |
|------|--------|---------|
| `/usr`, `/lib*`, `/bin`, `/etc` | read-only | System binaries and libraries |
| `/run/user/<uid>` | tmpfs | Empty XDG runtime dir; `XDG_RUNTIME_DIR` set accordingly. Wayland/PipeWire/D-Bus sockets only appear via opt-in (`--keyring` for D-Bus). |
| `/tmp` | read-write | Host's /tmp, minus its IPC socket dirs (see [Host /tmp sockets](#host-tmp-sockets)); use `--clear-tmp` for a fully isolated tmpfs |
| `/workspaces/<dir>` | read-write | Your project (current directory) |
| `~/.claude` | read-write | Claude Code config (includes claudechic config) |
| `~/.config/` | overlay | User config (uv, fabric, google-chrome, etc.): readable, writes discarded on exit |
| `~/.notebooklm-mcp/`, `~/.notebooklm-mcp-cli/` | read-write | notebooklm-mcp auth and Chrome profile |
| `~/.claude-mem/` | read-write | Persistent memory across sessions (auto-created if claude-mem plugin is installed) |
| `~/arxiv-storage/` | read-write | Research paper management tools |
| `~/.nvm/` | read-only | Node Version Manager (if installed; current node bin added to PATH) |
| `~/.bun/` | read-only | Bun runtime and packages (`~/.bun/bin` in PATH; `install/cache` is overlaid: readable, writes discarded) |
| `~/.npm/` | overlay | npm cache overlaid from host if it exists (readable, writes discarded), otherwise ephemeral scaffold |
| `~/.local/share/claude`, `~/.local/share/pipx`, `~/.local/share/uv/{tools,python}` | read-only | Claude data and tool-manager venvs |
| `~/.local/bin` → `/opt/host-bin` | read-only | Host user binaries re-mounted under `/opt/` and added to PATH (the `claude` binary is also bound at its original path) |
| `~/.cargo/bin` → `/opt/host-cargo-bin`, `~/go/bin` → `/opt/host-go-bin` | read-only | Cargo/Go bins re-mounted under `/opt/` and added to PATH |
| `/opt/<vendor>/…` (pwsh, Chrome, Chromium, Edge, Brave, dotnet) | read-only | Tools whose `/usr/bin` launcher is a symlink into `/opt`. The install dir is auto-bound so the symlink resolves in-sandbox (the empty `--dir /opt` otherwise shadows it). Only for tools present on the host. Chrome/Chromium need `--no-sandbox` under bwrap; snap installs (resolving to `/snap`) are skipped. |
| `~/.cache/uv` | overlay | uv cache overlaid from host if it exists: readable, writes discarded |
| `~/.cache`, `~/go`, `~/.cargo` | ephemeral | Scaffolded on a tmpfs `$HOME`, cleared on exit |

## MCP server token storage

MCP servers like [ms-365-mcp](https://github.com/softeria/ms-365-mcp-server) need to persist authentication tokens, and blaude arranges that without any setup from you.

For npm-linked packages, the token files at the package root (`.token-cache.json`, `.selected-account.json`) are mounted read-write. D-Bus and keytar stay disabled by default, which pushes the servers onto file-based storage; that is the more reliable path in containers.

If you have GNOME Keyring configured and unlocked at login, `--keyring` turns keytar-based storage back on and gives you the more secure option.

## claudechic support

[claudechic](https://github.com/mrocklin/claudechic) is a Python-based TUI wrapper for Claude Code. Use `--chic` to run it inside the sandbox:

```bash
blaude --chic              # Run claudechic in sandbox
blaude --chic -c           # Continue conversation via claudechic
```

Config file (`~/.claude/.claudechic.yaml`) is writable via the `~/.claude` mount.

## Remote Control

[Remote Control](https://code.claude.com/docs/en/remote-control) lets you drive a local Claude Code session from your phone or a browser. It needs a flag from blaude, because blaude's usual privacy settings switch it off by accident.

Claude Code asks the GrowthBook feature-flag service whether your account may use Remote Control. blaude normally sets `DO_NOT_TRACK=1`, `DISABLE_TELEMETRY=1` and `DISABLE_GROWTHBOOK=1`, so that request never goes out, and the feature reports `Remote Control is not yet enabled for your account` even on accounts that have it. The flag drops those three opt-outs for one session.

```bash
blaude --remote-control     # normal session; run /remote-control when you want it
blaude remote-control       # server mode (claude's own subcommand, passed through)
```

The two forms behave differently. blaude consumes `--remote-control` instead of passing it on, so claude starts as usual with `--dangerously-skip-permissions` and you switch Remote Control on from inside using `/remote-control`. The bare `remote-control` subcommand reaches claude untouched and without `--dangerously-skip-permissions`, which claude rejects alongside that subcommand. Both run inside the sandbox.

Either form also unsets `ANTHROPIC_API_KEY` and `CLAUDE_CODE_OAUTH_TOKEN` for the session. Remote Control needs a full-scope claude.ai OAuth session, and a host API key or a narrower token produces the same misleading "not yet enabled" message. claude falls back to your `/login` session, and blaude tells you at startup when it drops either variable.

Two limits come from Claude Code itself, so blaude prints them as notices instead of working around them:

- Telemetry and feature-flag traffic flows while Remote Control is on. You cannot have the feature without it.
- Remote-driven actions still ask for permission, even though blaude passes `--dangerously-skip-permissions`.

Don't combine this with `--no-network`. Remote Control needs outbound network, and blaude warns if you ask for both.

## User config directory

The entire `~/.config/` directory is mounted as a **write-discarding overlay** if it exists: everything stays readable, and anything the sandbox writes disappears when the session ends. This includes:

- uv keeps Python preference settings in `~/.config/uv/uv.toml`, such as `python-preference = "system"`
- Fabric keeps its patterns, sessions, contexts, strategies, extensions, OAuth tokens and `.env` in `~/.config/fabric/`
- Chrome's automation profile sits in `~/.config/google-chrome/`, where Puppeteer, Playwright and OAuth flows find it
- anything else your tools keep in `~/.config/`

> **Why an overlay, not read-write**: the tree also holds `autostart/`, `systemd/user/`, `environment.d/`, `Code/User/settings.json` and `nvim/init.lua`, each of which executes on the *host* at your next login or next app launch. Read-only isn't an option either: Chrome can't start against a read-only profile and yarn's global installs live in `~/.config/yarn`. An overlay keeps all of those working inside the session while leaving nothing behind. Trade-off: config changes made *by the sandbox* don't persist across runs. Override with `--allow-protected-writes`.
>
> `~/.config/git/` (the XDG global git config) is additionally re-shadowed read-only (or as an ephemeral tmpfs if absent) on top. That's redundant under the overlay, but it's what protects you if your `bwrap` is older than 0.8.0 and can't overlay: git settings there (aliases, `core.pager`/`editor`/`fsmonitor`, `core.sshCommand`) execute on the host at the next git run outside the sandbox.

```bash
# Setup fabric outside sandbox first
fabric --setup

# Then use normally inside sandbox
blaude --exec fabric -p "summarize"
```

## notebooklm-mcp support

[notebooklm-mcp](https://github.com/c0ffee0wl/notebooklm-mcp) is an MCP server for NotebookLM. blaude automatically mounts `~/.notebooklm-mcp/` for auth persistence:

```bash
# Authenticate outside sandbox first (requires browser)
notebooklm-mcp-auth

# Then use normally - MCP server reads cached tokens inside sandbox
blaude
```

The directory stores `auth.json` (cookies/CSRF/session) and `chrome-profile/` for automatic re-authentication.

## Environment variables

All [Claude Code environment variables](https://code.claude.com/docs/en/env-vars) are automatically passed through if set:

> **Prefix passthrough**: every `ANTHROPIC_*` and `CLAUDE_*` host env var is auto-passed via the env scanning loop. No matching against a hard-coded list. The Anthropic namespace is owned, so new upstream env vars are picked up automatically. The table below lists representative examples for those rows, not an exhaustive set.

> **Non-prefix passthrough**: rows that don't start with `ANTHROPIC_`/`CLAUDE_` come from blaude's explicit `claude_env_vars` allowlist. Here `*` is a shorthand for a specific enumerated list, not a wildcard. For example, `AWS_*` means `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE`, `AWS_BEARER_TOKEN_BEDROCK`. Variables not in the allowlist won't pass through; use `--env KEY=VALUE` for those.

> **Forced env-vars**: a small set of variables is hardcoded in the sandbox and overrides the host value (also under `--keep-env`) to keep blaude's auto-skip behaviour working: `DO_NOT_TRACK=1`, `DISABLE_TELEMETRY=1`, `DISABLE_AUTOUPDATER=1`, `DISABLE_ERROR_REPORTING=1`, `DISABLE_BUG_COMMAND=1`, `CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY=1`, `DISABLE_INSTALL_GITHUB_APP_COMMAND=1`, `CLAUDE_DISABLE_CONFIG_WATCH=1`, `DISABLE_GROWTHBOOK=1`. These are kept in a deny-set so the `CLAUDE_*` prefix match cannot resurrect their host values. Additionally, the following are force-*unset* inside the sandbox (via `--unsetenv`): **`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`**: any defined value, even `=0`, triggers permission-mode hardening that overrides `--dangerously-skip-permissions` (`"Permission mode forced to default — CLAUDE_CODE_SUBPROCESS_ENV_SCRUB is set …"`), so blaude drops it to match the documented default (unset = disabled); and **`CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_SESSION_ID`, `CLAUDE_CODE_BRIDGE_SESSION_ID`, `CLAUDE_CODE_CHILD_SESSION`, `CLAUDE_CODE_TEAM_NAME`, `CLAUDE_CODE_REMOTE`, `CLAUDE_CODE_REMOTE_SESSION_ID`, `CLAUDE_EFFORT`, `CLAUDE_PROJECT_DIR`, `CLAUDE_CODE_MESSAGING_SOCKET`, `CLAUDE_PID`**: markers an outer claude sets automatically (parent binary identity, parent session UUID, parent Remote Control session ID, nested-session flag, agent-team membership, cloud-session identity, parent turn's effort level, parent cwd, parent's cross-session inbox socket, parent's PID) that would otherwise leak into the sandboxed inner claude when blaude is invoked from inside another claude session; an inherited `CLAUDE_CODE_CHILD_SESSION=1` would even exclude the session from `--resume`/`--continue`, breaking `blaude -c`. The last two matter beyond hygiene: `CLAUDE_CODE_MESSAGING_SOCKET` stays *live* across the boundary (the socket sits under the bind-mounted `/tmp`), handing sandboxed hooks and Bash commands a writable pointer into the **host** session's inbox, and `CLAUDE_PID` names an unrelated process once inside the PID namespace, where the Bash tool's `pkill` self-protection guard reads it.

> **Settings-file blocker detection**: at startup, blaude scans `~/.claude/settings.json`, `$CLAUDE_CONFIG_DIR/settings.json`, `/etc/claude-code/managed-settings.json`, `/etc/claude-code/managed-settings.d/*.json`, and the workspace's own `.claude/settings.json` / `.claude/settings.local.json` (the key works from any scope, so a repo can disable bypass mode too; skipped under `--tmp`, where the workspace is never mounted) for `permissions.disableBypassPermissionsMode: "disable"`. That key blocks `--dangerously-skip-permissions` independently of any env var, and managed (enterprise) settings cannot be overridden by blaude. If detected, a clear warning is printed; remove the key (or change the value) to restore bypass mode.

| Category | Variables |
|----------|-----------|
| **Anthropic namespace (prefix-matched)** | Any variable starting with `ANTHROPIC_` (e.g., `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_BETAS`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL*`, `ANTHROPIC_BEDROCK_*`, `ANTHROPIC_FOUNDRY_*`, `ANTHROPIC_VERTEX_*`, `ANTHROPIC_WORKSPACE_ID`, …) |
| **Claude Code namespace (prefix-matched)** | Any variable starting with `CLAUDE_` (e.g., `CLAUDE_CODE_OAUTH_*`, `CLAUDE_CODE_USE_BEDROCK`/`_VERTEX`/`_FOUNDRY`/`_MANTLE`, `CLAUDE_CODE_MAX_*_TOKENS`, `CLAUDE_CODE_DISABLE_*`, `CLAUDE_CODE_ENABLE_*`, `CLAUDE_CODE_PLUGIN_*`, `CLAUDE_CODE_DEBUG_*`, `CLAUDE_CODE_OTEL_*`, `CLAUDE_CODE_CLIENT_*`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_TMPDIR`, `CLAUDE_ENV_FILE`, `CLAUDE_PLUGIN_DATA`, `CLAUDE_SKILL_DIR`, `CLAUDE_AGENT_SDK_*`, `CLAUDE_EFFORT`, …) |
| **VERTEX_REGION_* (prefix-matched)** | Region overrides for Claude models on Vertex AI. The whole namespace passes through (`VERTEX_REGION_CLAUDE_<MODEL>`, `VERTEX_REGION_DEFAULT`, `VERTEX_REGION_SMALL_FAST_MODEL`), so new models are covered automatically |
| **AWS** | `AWS_BEARER_TOKEN_BEDROCK`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`, `AWS_DEFAULT_REGION`, `AWS_PROFILE`, `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` |
| **Google Cloud** | `GCLOUD_PROJECT`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`, `VERTEX_AI_PROJECT_ID`, `VERTEX_AI_API_ENDPOINT`, `CLOUD_RUN_JOB_ATTEMPT`, `CLOUD_ML_REGION` |
| **GitHub** (requires `--git`) | `GH_TOKEN`, `GITHUB_TOKEN` |
| **GPG** (socket bound under `--git`) | `GPG_TTY`, `GNUPGHOME` |
| **MCP standards** | `MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `MCP_CONNECT_TIMEOUT_MS`, `MCP_ENABLED`, `MCP_OAUTH_CALLBACK_PORT`, `MCP_CLIENT_SECRET`, `MCP_SSE_URL`, `MCP_DISCOVERY_CACHE`, `ENABLE_TOOL_SEARCH`, `ENABLE_CLAUDEAI_MCP_SERVERS`, `MCP_CONNECTION_NONBLOCKING`, `MCP_SERVER_*` (glob; covers env-based `MCP_SERVER_<ID>` server config and `MCP_SERVER_CONNECTION_BATCH_SIZE`), `MCP_REMOTE_SERVER_CONNECTION_BATCH_SIZE` |
| **OpenTelemetry** | `OTEL_*`, enumerated rather than prefix-matched (exporter config, OTLP endpoints/protocols/export intervals for metrics/logs/traces, generic and per-signal client cert/key plus the collector CA bundle, all bind-mounted read-only; log level toggles incl. `OTEL_LOG_RAW_API_BODIES`, resource attributes, attribute-length limits incl. the `LOGRECORD`/`SPAN` variants), `TRACEPARENT`, `TRACESTATE` |
| **Bash / shell** | `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_OUTPUT_LENGTH`, `BASH_MAX_TIMEOUT_MS` |
| **Tokens & retries** | `MAX_THINKING_TOKENS`, `MAX_MCP_OUTPUT_TOKENS`, `MAX_STRUCTURED_OUTPUT_RETRIES`, `TASK_MAX_OUTPUT_LENGTH`, `SLASH_COMMAND_TOOL_CHAR_BUDGET`, `API_TIMEOUT_MS`, `API_FORCE_IDLE_TIMEOUT`, `FALLBACK_FOR_ALL_PRIMARY_MODELS` |
| **Network/TLS** | `HTTP_PROXY`, `HTTPS_PROXY`, `SOCKS_PROXY`, `NO_PROXY`, `NODE_EXTRA_CA_CERTS`, `NODE_TLS_REJECT_UNAUTHORIZED` (CA-store selection is now `CLAUDE_CODE_CERT_STORE`, covered by the `CLAUDE_` prefix) |
| **Updates/Installation** | `FORCE_AUTOUPDATE_PLUGINS`, `DISABLE_INSTALLATION_CHECKS`, `DISABLE_UPDATES`, `DISABLE_UPGRADE_COMMAND`, `DISABLE_DOCTOR_COMMAND`, `DISABLE_EXTRA_USAGE_COMMAND`, `DISABLE_LOGIN_COMMAND`, `DISABLE_LOGOUT_COMMAND`, `DISABLE_FEEDBACK_COMMAND` |
| **Caching & compaction** | `DISABLE_PROMPT_CACHING*`, `DISABLE_NON_ESSENTIAL_MODEL_CALLS`, `DISABLE_AUTO_COMPACT`, `DISABLE_COMPACT`, `DISABLE_INTERLEAVED_THINKING`, `ENABLE_PROMPT_CACHING_1H`, `ENABLE_PROMPT_CACHING_1H_BEDROCK`, `FORCE_PROMPT_CACHING_5M` |
| **Runtime indicators / misc** | `IS_DEMO`, `FORCE_HYPERLINK`, `USE_BUILTIN_RIPGREP`, `CCR_FORCE_BUNDLE`, `CLAUDECODE`, `AI_AGENT`, `DEBUG`, `DISABLE_COST_WARNINGS`, `CI`, `NO_COLOR`, `FORCE_COLOR` |
| **Other LLM APIs** | `OPENAI_API_KEY`, `OPENAI_API_BASE`, `OPENAI_ORG_ID`, `AZURE_OPENAI_*`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `MISTRAL_API_KEY`, `COHERE_API_KEY`, `HUGGINGFACE_API_KEY`, `HF_TOKEN`, `GROQ_API_KEY`, `TOGETHER_API_KEY`, `REPLICATE_API_TOKEN`, `PERPLEXITY_API_KEY`, `FIREWORKS_API_KEY`, `DEEPSEEK_API_KEY`, `XAI_API_KEY`, `JINA_API_KEY`, `EXA_API_KEY` |
| **Third-party Services** | `FEEDLY_ACCESS_TOKEN`, `RAINDROP_ACCESS_TOKEN` |
| **claudechic** | `CLAUDECHIC_DEBUG`, `CLAUDECHIC_REMOTE_PORT`, `CHIC_PROFILE`, `CHIC_SAMPLE_THRESHOLD` |
| **notebooklm-mcp** | `NOTEBOOKLM_COOKIES`, `NOTEBOOKLM_CSRF_TOKEN`, `NOTEBOOKLM_SESSION_ID`, `NOTEBOOKLM_MCP_*` |
| **claude-mem** | Any variable starting with `CLAUDE_MEM_` (covered by the `CLAUDE_*` prefix match, e.g. `CLAUDE_MEM_DATA_DIR`, `CLAUDE_MEM_WORKER_PORT`) |
| **Webhooks** | Any variable ending in `_WEBHOOK` (e.g., `SLACK_WEBHOOK`, `DISCORD_WEBHOOK`) |
| **Webshare** | Any variable starting with `WEBSHARE_` (e.g., `WEBSHARE_API_KEY`, `WEBSHARE_PROXY`) |

Use `--env KEY=VALUE` to pass additional variables not covered above.

## Protected workspace paths

Inspired by Anthropic's [sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime), blaude write-protects files and directories inside the workspace that could be used to execute code *outside* the sandbox. A sandboxed agent running with `--dangerously-skip-permissions` has full write access to the workspace. Without this protection, it could plant a malicious `.git/hooks/pre-commit` or `.bashrc` that runs the next time you open a shell or make a commit on the host.

sandbox-runtime enforces this using ripgrep-based scanning with `/dev/null` overlays and symlink neutralization. blaude uses a similar technique adapted for its bash/bwrap architecture, with zero host filesystem artifacts:

- Files that already exist are `--ro-bind` mounted from the host, which keeps their content readable and blocks writes.
- Directories that already exist get a `--tmp-overlay`: content stays readable and writes succeed, but they are ephemeral and never reach the host. This needs bwrap 0.8.0 or newer. Older versions fall back to `--ro-bind`, which still blocks writes but may leave host stubs where the target didn't exist.
- When a protected directory is missing, its parent is overlaid instead. If `.git/hooks/` is absent, `.git/` gets the overlay, so the sandbox cannot create the hooks directory at all.
- Root-level dotfiles like `.bashrc` are protected only when they already exist, since there is no parent to overlay. The risk is low because they are uncommon in project directories.
- In git worktrees, `.git/*` paths are protected only when `.git` is a directory rather than a file.
- Nested copies get the same treatment. A `find` scan up to depth 3 catches monorepos, git submodules and vendored dependencies, so `packages/app/.git/hooks/` and `packages/lib/.bashrc` are covered too.
- A pre-flight scan (`find -maxdepth 4 -type l`) warns about workspace symlinks that point outside the workspace tree and outside known-safe system paths (`/usr`, `/lib*`, `/bin`, `/sbin`, `/etc`, `/proc`, `/sys`, `/dev`). bwrap mounts don't follow these, but paired with `-m ...:rw` they could expose host paths you didn't intend to share.

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

## Host /tmp sockets

`/tmp` is bind-mounted from the host by default, which also exposes the IPC sockets sitting there, and the sandbox runs as the same user that owns them. The sharpest case is tmux: with a live server, `tmux send-keys` types straight into one of your host shells. That's *immediate* host code execution, not the deferred kind the workspace protections guard against. An ssh-agent socket under `/tmp/ssh-XXXX/` would likewise sidestep the `--ssh` opt-in, and `/tmp/dbus-*` would sidestep `--keyring`.

blaude shadows each of these with an empty tmpfs, so the sandbox sees the directory but can't reach the host's sockets:

| Path | Risk |
|------|------|
| `/tmp/.X11-unix` | X11 input injection and screen capture |
| `/tmp/.ICE-unix`, `/tmp/.XIM-unix`, `/tmp/.font-unix` | X session manager and input-method channels |
| `/tmp/tmux-*` | `tmux send-keys` into a host shell: direct command execution |
| `/tmp/ssh-*` | ssh-agent hijacking, bypassing `--ssh` |
| `/tmp/dbus-*` | Session bus access, bypassing `--keyring` |

blaude only shadows directories that already exist, since creating the mountpoint for an absent one would leave a real directory behind on your host. It skips the shadows entirely under `--clear-tmp` (already isolated) and `--allow-protected-writes`.

> **Two gaps this doesn't close**: bare socket *files* at the `/tmp` root (`/tmp/.s.PGSQL.5432`, `/tmp/mysql.sock`) can't be shadowed by a tmpfs without covering `/tmp` itself, and a tmux server you start *after* launching blaude creates its socket directory mid-session, unshadowed. Use `--clear-tmp` for a private tmpfs `/tmp` if either matters to you. It closes both, at the cost of not sharing files through `/tmp`.

## Clipboard support

VTE-based terminals (Terminator, GNOME Terminal, XFCE Terminal) don't support OSC 52 clipboard sequences. Claude Code uses OSC 52 for clipboard operations, so copying silently fails on these terminals.

blaude ships `osc52-clipboard`, a companion script that intercepts OSC 52 sequences and copies to the system clipboard via `xclip`, `xsel`, or `wl-copy`. It activates automatically when `osc52-clipboard` is found (same directory as blaude, or on PATH). Disable with `--no-clipboard` or `OSC52_NO_CLIPBOARD=1`.

Requires one of: `xclip`, `xsel` (X11), or `wl-copy` (Wayland).

## Asciinema support

When running inside [asciinema](https://asciinema.org/) (`ASCIINEMA_REC=1`), blaude pauses the recording for the duration of the Claude session. The asciinema process is stopped (SIGSTOP) before the sandbox starts and resumed (SIGCONT) when it exits. The recording picks up again after Claude exits.

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

You only need to run this once. The fix is idempotent, so running it again is a no-op.

## License

Apache-2.0. See [LICENSE](LICENSE).

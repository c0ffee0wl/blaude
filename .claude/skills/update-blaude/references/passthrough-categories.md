# Passthrough Array Categories

`ANTHROPIC_*` and `CLAUDE_*` are auto-passed by prefix match in the env scanning loop — they do NOT appear in `claude_env_vars`. The array only contains non-prefix vars, grouped under comment headers. When recommending additions for a non-prefix var, place it in the correct category.

| Comment header | Examples |
|---|---|
| `# Bedrock / AWS auth` | `AWS_BEARER_TOKEN_BEDROCK`, `AWS_ACCESS_KEY_ID`, `AWS_PROFILE`, `AWS_REGION` |
| `# Google Cloud auth (Vertex AI)` | `GCLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`, `CLOUD_ML_REGION` |
| `# Vertex region overrides` | `VERTEX_REGION_CLAUDE_*`, `VERTEX_REGION_DEFAULT`, `VERTEX_REGION_SMALL_FAST_MODEL` |
| `# GPG` | `GPG_TTY`, `GNUPGHOME` |
| `# MCP standards` | `MCP_TIMEOUT`, `MCP_TOOL_TIMEOUT`, `ENABLE_TOOL_SEARCH`, `ENABLE_CLAUDEAI_MCP_SERVERS` |
| `# OpenTelemetry exporter + W3C trace context` | `OTEL_*`, `TRACEPARENT`, `TRACESTATE` |
| `# Bash / shell tool tunables` | `BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_*` |
| `# Token & retry limits` | `MAX_THINKING_TOKENS`, `MAX_MCP_OUTPUT_TOKENS`, `API_TIMEOUT_MS`, `FALLBACK_FOR_ALL_PRIMARY_MODELS` |
| `# Network & TLS` | `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, `NODE_EXTRA_CA_CERTS` |
| `# Updates & installation toggles` | `FORCE_AUTOUPDATE_PLUGINS`, `DISABLE_INSTALLATION_CHECKS`, `DISABLE_UPDATES`, `DISABLE_*_COMMAND` |
| `# Caching & compaction toggles` | `DISABLE_PROMPT_CACHING*`, `ENABLE_PROMPT_CACHING_1H*`, `FORCE_PROMPT_CACHING_5M` |
| `# Runtime indicators (set by Claude Code itself or external tooling) and misc` | `CLAUDECODE`, `AI_AGENT`, `DEBUG`, `IS_DEMO`, `FORCE_HYPERLINK`, `USE_BUILTIN_RIPGREP`, `CCR_FORCE_BUNDLE`, `DISABLE_COST_WARNINGS` |
| `# Additional LLM API keys` | `OPENAI_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, etc. |
| `# Third-party service tokens` | `FEEDLY_ACCESS_TOKEN`, `RAINDROP_ACCESS_TOKEN` |
| `# claudechic environment variables` | `CLAUDECHIC_*`, `CHIC_*` (note: `CLAUDECHIC_` does NOT match the `CLAUDE_` prefix because there's no underscore between `CLAUDE` and `CHIC`) |
| `# notebooklm-mcp environment variables` | `NOTEBOOKLM_*` |

## Prefix-matched (NOT in the array)

- **`ANTHROPIC_*`**: all Anthropic-namespaced vars (`ANTHROPIC_API_KEY`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL*`, `ANTHROPIC_BEDROCK_*`, `ANTHROPIC_FOUNDRY_*`, `ANTHROPIC_VERTEX_*`, etc.)
- **`CLAUDE_*`**: all Claude Code vars (`CLAUDE_CODE_*`, `CLAUDE_AGENT_SDK_*`, `CLAUDE_AUTOCOMPACT_*`, `CLAUDE_BASH_*`, `CLAUDE_CONFIG_DIR`, `CLAUDE_EFFORT`, `CLAUDE_ENABLE_*`, `CLAUDE_ENV_FILE`, `CLAUDE_MEM_*`, `CLAUDE_PLUGIN_*`, `CLAUDE_REMOTE_CONTROL_*`, `CLAUDE_SKILL_DIR`, `CLAUDE_STREAM_*`, etc.)
- **`*_WEBHOOK`** and **`WEBSHARE_*`**: other prefix patterns in the loop

## Intentional non-official vars

blaude includes vars not in the official Claude Code docs. These are intentional and should NOT be flagged for removal:

- **Third-party LLM keys**: `OPENAI_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, etc. — for MCP servers and tools
- **claudechic vars**: `CLAUDECHIC_*`, `CHIC_*` — for the claudechic TUI wrapper
- **notebooklm-mcp vars**: `NOTEBOOKLM_*` — for NotebookLM MCP server

Flag these as "intentional extra" not "possibly deprecated."

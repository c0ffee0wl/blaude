# Passthrough Array Categories

The `claude_env_vars` array (~line 694) uses comment headers to organize vars. When recommending additions, place vars in the correct category.

| Comment header | Examples |
|---|---|
| `# Authentication & API Configuration` | `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL` |
| `# Model Configuration` | `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL*`, `VERTEX_REGION_*` |
| `# Bash & Command Execution` | `BASH_*`, `CLAUDE_CODE_SHELL*`, `CLAUDE_CODE_SCRIPT_CAPS` (note: `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is force-set to `0` in `_hardcoded_env_vars`, NOT in passthrough) |
| `# Token & Output Limits` | `CLAUDE_CODE_MAX_OUTPUT_TOKENS`, `MAX_MCP_OUTPUT_TOKENS` |
| `# Cloud Provider Configuration` | `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_SKIP_*_AUTH` |
| `# AWS Credentials (for Bedrock)` | `AWS_ACCESS_KEY_ID`, `AWS_PROFILE`, `AWS_REGION` |
| `# Google Cloud Credentials (for Vertex AI)` | `GCLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS` |
| `# MCP Configuration` | `MCP_TIMEOUT`, `ENABLE_TOOL_SEARCH` |
| `# Telemetry & Monitoring` | `CLAUDE_CODE_ENABLE_TELEMETRY`, `OTEL_*` |
| `# UI & Display` | `CLAUDE_CODE_HIDE_ACCOUNT_INFO`, `CLAUDE_CODE_DISABLE_MOUSE` |
| `# Development & Debugging` | `CLAUDECODE` |
| `# File & Directory Configuration` | `CLAUDE_CONFIG_DIR`, `CLAUDE_ENV_FILE` |
| `# Credential & mTLS Authentication` | `CLAUDE_CODE_CLIENT_CERT`, `CLAUDE_CODE_API_KEY_HELPER_TTL_MS` |
| `# Network & TLS` | `HTTP_PROXY`, `NO_PROXY`, `NODE_EXTRA_CA_CERTS` |
| `# Updates & Installation` | `FORCE_AUTOUPDATE_PLUGINS`, `DISABLE_INSTALLATION_CHECKS` |
| `# Memory` | `CLAUDE_CODE_DISABLE_AUTO_MEMORY` |
| `# Features & Functionality` | `CLAUDE_CODE_SIMPLE`, `CLAUDE_CODE_DISABLE_CRON` |
| `# Advanced Features` | `CLAUDE_AUTOCOMPACT_*`, `DISABLE_PROMPT_CACHING*` |
| `# Additional LLM API keys` | `OPENAI_API_KEY`, `GEMINI_API_KEY`, etc. |
| `# claudechic environment variables` | `CLAUDECHIC_*`, `CHIC_*` |
| `# notebooklm-mcp environment variables` | `NOTEBOOKLM_*` |

## Intentional non-official vars

blaude includes vars not in the official Claude Code docs. These are intentional and should NOT be flagged for removal:

- **Third-party LLM keys**: `OPENAI_API_KEY`, `GEMINI_API_KEY`, `DEEPSEEK_API_KEY`, etc. — for MCP servers and tools
- **claudechic vars**: `CLAUDECHIC_*`, `CHIC_*` — for the claudechic TUI wrapper
- **notebooklm-mcp vars**: `NOTEBOOKLM_*` — for NotebookLM MCP server
- **Unofficial Anthropic vars**: `ANTHROPIC_BEDROCK_BASE_URL`, `ANTHROPIC_VERTEX_PROJECT_ID`, etc. — functional but undocumented
- **Wildcard patterns** (in the glob passthrough block): `*_WEBHOOK`, `WEBSHARE_*`

Flag these as "intentional extra" not "possibly deprecated."

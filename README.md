# Clawdbot + Claude Integration

Configuration for running [Clawdbot](https://clawd.bot/) with Claude as the AI model provider.

## Prerequisites

- Clawdbot installed (`npm install -g clawdbot@latest` or via [install script](https://docs.clawd.bot/start/getting-started))
- One of:
  - **Anthropic API key** (recommended) — from [console.anthropic.com](https://console.anthropic.com/)
  - **Claude Pro/Max subscription** — use `claude setup-token` from the Claude Code CLI

## Setup

1. **Copy the environment file and add your credentials:**

   ```bash
   cp .env.example .env
   ```

   Then edit `.env` and fill in either `ANTHROPIC_API_KEY` or `CLAUDE_SETUP_TOKEN`.

2. **Run the onboarding wizard** (optional, for channel connections):

   ```bash
   clawdbot onboard
   ```

3. **Or start directly with this config:**

   ```bash
   clawdbot start --config clawdbot.config.yaml
   ```

4. **Open the web UI** at `http://127.0.0.1:18789/` to verify the connection.

## Claude Code Setup Token

If you're using a Claude Pro/Max subscription instead of an API key:

```bash
# In your terminal (Claude Code CLI must be installed)
claude setup-token
```

Copy the output and paste it as `CLAUDE_SETUP_TOKEN` in your `.env` file, or provide it during `clawdbot onboard` when prompted for authentication.

## Configuration

See `clawdbot.config.yaml` for the full configuration. Key settings:

| Setting | Description |
|---|---|
| `agent.model` | Claude model to use (default: `claude-sonnet-4-20250514`) |
| `skills` | Enabled Clawdbot skills (claude-connect, claude-code-usage, etc.) |
| `memory.enabled` | Persistent memory across sessions |
| `gateway.port` | Local port for the web UI (default: 18789) |

## Health Check

```bash
clawdbot doctor
```

This verifies your configuration, authentication, and security settings.

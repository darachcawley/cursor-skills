# Cursor Skills

A collection of AI agent skills for [Cursor](https://cursor.com) that integrate with Slack and Jira to automate daily workflows.

## Available Skills


| Skill                                                    | Description                                                                                                                                                                                                                                                                      |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[Daily Digest](.cursor/skills/daily-digest/SKILL.md)** | - Summarizes your Slack channels, DMs, and Jira mentions into a browsable daily report. - Track actions for you and your team members, which you can mark as done. - Track Features in Jira which you want to watch for progress & get summary updates that span Jira and Slack. |


## Prerequisites

- [Cursor IDE](https://cursor.com) with Agent mode enabled
- A Slack workspace you can generate tokens for
- A Jira Cloud instance with API token access
- `npx` and `uvx` available on your PATH (Node.js and Python/uv)

## Quick Start

### 1. Clone the repo

```bash
git clone <repo-url> cursor-skills
cd cursor-skills
```

### 2. Configure MCP servers

The skills talk to Slack and Jira through MCP (Model Context Protocol) servers running locally. Copy the example config and fill in your credentials:

```bash
cp .cursor/mcp.example.json .cursor/mcp.json
```

Edit `.cursor/mcp.json` with your values:

```json
{
  "mcpServers": {
    "atlassian": {
      "type": "stdio",
      "command": "uvx",
      "args": ["mcp-atlassian"],
      "env": {
        "JIRA_URL": "https://your-company.atlassian.net",
        "JIRA_USERNAME": "you@company.com",
        "JIRA_API_TOKEN": "<your-jira-api-token>",
        "JIRA_SSL_VERIFY": "true"
      }
    },
    "slack": {
      "command": "npx",
      "args": ["-y", "slack-mcp-server"],
      "env": {
        "SLACK_MCP_XOXC_TOKEN": "<your-xoxc-token>",
        "SLACK_MCP_XOXD_TOKEN": "<your-xoxd-token>",
        "SLACK_MCP_CUSTOM_TLS": "1"
      }
    }
  }
}
```

**Getting your tokens:**

- **Jira API token** — generate one at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens)
- **Slack tokens** (`xoxc` / `xoxd`) — these are session tokens extracted from the Slack web app. Open Slack in your browser, open DevTools, and find them in cookies/local storage. They rotate, so you may need to refresh them periodically.

### 3. Set up your identity

Copy the example user config and fill in your details:

```bash
cp user_config.example.json user_config.json
```

Edit `user_config.json`:

```json
{
  "slack_username": "your-slack-username",
  "jira_display_name": "Your Full Name",
  "jira_username": "your-jira-username",
  "slack_domain": "your-company.enterprise.slack.com",
  "jira_base_url": "https://your-company.atlassian.net"
}
```

This file is shared across all skills and is gitignored.

### 4. Configure the Daily Digest (optional but recommended)

Set up which Slack channels to monitor:

```bash
cp .cursor/skills/daily-digest/slack_channels_config.example.json \
   .cursor/skills/daily-digest/slack_channels_config.json
```

Edit `slack_channels_config.json` to list your channels, usergroup mentions, and whether to include DMs:

```json
{
  "channels": ["#your-team-channel", "#your-working-group"],
  "mention_groups": ["@your-usergroup"],
  "include_dms": true
}
```

Optionally, set up the Jira feature watchlist to track feature progress alongside your digest:

```bash
cp .cursor/skills/daily-digest/feature_watchlist.example.json \
   .cursor/skills/daily-digest/feature_watchlist.json
```

Add your Jira feature keys to `feature_watchlist.json`.

### 5. Open the project in Cursor and go

Open the `cursor-skills` folder in Cursor. The skills are automatically discovered. Try:

> "Give me a daily digest for yesterday"

## Viewing Digests

After generating a digest, serve the built-in HTML viewer:

```bash
npx serve .cursor/skills/daily-digest
```

Then open `http://localhost:3000/viewer/` in your browser. The viewer shows all generated digests in a browsable timeline with action items, thread links, and feature tracking.

## Project Structure

```
cursor-skills/
├── README.md
├── user_config.json              # Your identity (gitignored, create from .example)
├── user_config.example.json      # Template
└── .cursor/
    ├── mcp.json                  # MCP server config (gitignored, create from .example)
    ├── mcp.example.json          # Template
    └── skills/
        └── daily-digest/         # Slack + Jira daily summary skill
            ├── SKILL.md
            ├── slack_channels_config.json
            ├── feature_watchlist.json
            ├── digests/          # Auto-generated daily JSON files
            └── viewer/           # Self-contained HTML digest viewer
```

## Troubleshooting

**MCP servers not connecting** — Restart Cursor after editing `.cursor/mcp.json`. Check that `npx` and `uvx` are on your PATH by running them in your terminal.

**Slack tokens expired** — The `xoxc`/`xoxd` tokens are session-based and expire. Re-extract them from the Slack web app when you see auth errors.

**"Could not load user_config.json"** — Make sure you copied `user_config.example.json` to `user_config.json` in the workspace root (not inside the skill directory).

**Empty digest** — Verify your `slack_channels_config.json` lists channels you actually have access to, and that the date you requested has activity.
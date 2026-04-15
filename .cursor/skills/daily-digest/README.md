# Daily Digest (skill)

Summarize Slack activity for a chosen date, merge Jira feature + mention context, and browse results in a local HTML viewer or Obsidian-friendly Markdown.

## Full documentation

- **[SKILL.md](SKILL.md)** — Complete workflow: MCP tools, channel config, person search (Step 3d), safe merge when Slack/Jira fails, Steps 7–8 (viewer + Markdown export)

## Quick setup (from repo root)

```bash
cp user_config.example.json user_config.json
# edit user_config.json — see README.md in repo root for field meanings

cp .cursor/skills/daily-digest/slack_channels_config.example.json \
   .cursor/skills/daily-digest/slack_channels_config.json
cp .cursor/skills/daily-digest/feature_watchlist.example.json \
   .cursor/skills/daily-digest/feature_watchlist.json
```

Configure Slack + Jira MCP in `.cursor/mcp.json` (see [README.md](../../../README.md)).

## Outputs (after a digest run)

| Output | Location |
| --- | --- |
| Digest JSON | `digests/YYYY-MM-DD.json` |
| HTML viewer | Serve repo: `npx serve .cursor/skills/daily-digest` → `/viewer/` |
| Markdown (Obsidian) | `markdown/YYYY-MM-DD.md` or `obsidian_digest_path` in `user_config.json` |

## DMs

With `include_dms: true`, **Step 3b** loads 1:1 DMs with other people for the digest date via a **separate** `conversations_search_messages` call per IM channel (see [SKILL.md](SKILL.md) Step 3b). Channel search (Step 2), self-DM (Step 3), and usergroup search (Step 3c) are unchanged.

## Try in Cursor

> Give me a daily digest for yesterday

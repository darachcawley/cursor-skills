---
name: daily-digest
description: Generate a daily digest of Slack conversations across configured channels and DMs. Use when the user asks for a daily digest, Slack summary, daily standup recap, or conversation roundup for a specific date.
---

# Slack Daily Digest

Produce a summarized daily digest of Slack activity across configured channels and DMs for a given date. Outputs a structured JSON file per day and an HTML viewer to browse all digests.

## First-time setup

Before first use, copy each `.example.json` file to its real name and fill in your values:

1. `user_config.example.json` → `user_config.json` (in the **workspace root**, not this skill's directory) — your identity and environment
2. `slack_channels_config.example.json` → `slack_channels_config.json` — Slack channels to monitor
3. `feature_watchlist.example.json` → `feature_watchlist.json` — Jira feature keys to track (optional)

You also need the following MCP servers configured in Cursor:
- **Slack MCP** — named `user-slack` (provides `conversations_history`, `conversations_search_messages`, etc.)
- **Atlassian MCP** — named `user-atlassian` (provides `jira_get_issue`, `jira_search`)

## MCP Servers

This skill uses **only** the MCP servers configured in Cursor. The expected server names are `user-slack` and `user-atlassian`. If your MCP servers have different names, update the `server:` values in the workflow steps below.

**Do NOT** use any other Slack MCP server.

## Required Input

The user must provide a **date** for the digest (e.g., `2026-03-21`, `yesterday`, `today`). If not provided, ask for it before proceeding. Normalize the date to `YYYY-MM-DD` format.

## Workflow

### Step 0 — Load user configuration

Read `user_config.json` (in the **workspace root**) to get the user's identity and environment. All subsequent steps use these values instead of hardcoded names or URLs.

```json
{
  "slack_username": "your-slack-username",
  "jira_display_name": "Your Full Name",
  "jira_username": "your-jira-username",
  "slack_domain": "your-company.enterprise.slack.com",
  "jira_base_url": "https://your-company.atlassian.net"
}
```

Use `{slack_username}`, `{jira_display_name}`, `{jira_username}`, `{slack_domain}`, and `{jira_base_url}` as placeholders in the steps below. Substitute the actual values from the workspace-root `user_config.json` at runtime.

### Step 1 — Load channel configuration

Read `slack_channels_config.json` (in this skill's directory) to get the list of channels and whether DMs should be included.

```json
{
  "channels": ["#team-channel-one", "#wg-channel-two", ...],
  "mention_groups": ["@your-usergroup-one", "@your-usergroup-two"],
  "include_dms": true
}
```

To add or remove channels or mention groups, edit `slack_channels_config.json` directly.

### Step 2 — Fetch channel messages for the target date

For **each channel** in the config, use the `conversations_history` MCP tool on `user-slack`:

```
server: user-slack
tool: conversations_history
args:
  channel_id: "#channel-name"
  limit: "1d"
```

The `limit: "1d"` fetches one day of history. If the target date is not today, use `conversations_search_messages` with date filters instead:

```
server: user-slack
tool: conversations_search_messages
args:
  filter_in_channel: "#channel-name"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

### Step 3 — Fetch self-DMs (notes to self)

Always fetch messages the user sent to themselves. These are personal reminders, action items, and reference links that should appear in the digest as actions.

For today, use `conversations_history` on `user-slack`:

```
server: user-slack
tool: conversations_history
args:
  channel_id: "@{slack_username}"
  limit: "1d"
```

For historical dates, use `conversations_search_messages` on `user-slack`:

```
server: user-slack
tool: conversations_search_messages
args:
  filter_in_im_or_mpim: "@{slack_username}"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

Treat every self-DM as an action item. Set urgency based on the message content (default to `"today"` unless the message clearly refers to a future date). Include these in the digest under a channel entry named `"Self (notes/reminders)"`.

### Step 3b — Fetch DMs with others (if enabled)

If `include_dms` is true, use `conversations_unreads` on `user-slack` to find active DM conversations with other people, then fetch history for each:

```
server: user-slack
tool: conversations_unreads
args:
  channel_types: "dm"
  include_messages: true
  max_channels: 50
  max_messages_per_channel: 20
```

For historical dates, use `conversations_search_messages` on `user-slack` with `filter_date_on` and no channel filter, or search across DM channels individually.

### Step 3c — Search for usergroup mentions

For each group in `mention_groups`, search for messages that `@mention` that group on the target date. This catches messages in channels not in the configured list that still need attention.

```
server: user-slack
tool: conversations_search_messages
args:
  search_query: "@openshift-ai-exploring-managers"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

Deduplicate against messages already fetched from configured channels. For any new messages found, include them in the digest under a channel entry named `"Mentions (@group-name)"` — e.g. `"Mentions (@openshift-ai-exploring-managers)"`. The channel name **must** start with `"Mentions ("` so the viewer can identify these as tagged items. The viewer automatically labels these actions as **"Tagged"** and routes them to the **My Actions** tab (since the user was directly mentioned via a group they belong to). Treat these as action items with urgency `"this_week"` unless the content indicates higher urgency.

### Step 4 — Fetch thread replies

For any message that is a thread parent (has `reply_count > 0` or `thread_ts`), fetch the full thread using `user-slack`:

```
server: user-slack
tool: conversations_replies
args:
  channel_id: "#channel-name"
  thread_ts: "1234567890.123456"
  limit: "1d"
```

### Step 5 — Analyze and summarize

For each thread or standalone message, produce:

1. **summary** — 1-3 sentence summary of the conversation
2. **actions_needed** — List of action items extracted from the conversation (empty array if none)
3. **action_owner** — Who likely needs to perform each action (use Slack display names)
4. **urgency** — One of: `"today"`, `"this_week"`, `"later"`
5. **thread_link** — Slack deep link to the thread: `https://{slack_domain}/archives/{channel_id}/p{thread_ts_no_dot}`

#### Urgency classification rules

- **today**: Explicit deadlines for today, blockers, urgent requests, production issues, review requests with same-day expectations
- **this_week**: Items with near-term deadlines, follow-ups expected this week, PR reviews, meeting action items
- **later**: FYI messages, long-term planning discussions, ideas, nice-to-haves, informational updates

### Step 6 — Build the daily digest JSON

Write the digest to `digests/YYYY-MM-DD.json` in this skill's directory. Use this schema:

```json
{
  "date": "2026-03-21",
  "generated_at": "2026-03-21T15:30:00Z",
  "channels": [
    {
      "channel": "#team-dashboard-crimson",
      "channel_id": "C1234567890",
      "threads": [
        {
          "thread_ts": "1234567890.123456",
          "thread_link": "https://{slack_domain}/archives/C1234567890/p1234567890123456",
          "participants": ["@alice", "@bob"],
          "summary": "Discussed the new model registry API changes...",
          "actions_needed": [
            {
              "action": "Review PR #456 for model registry changes",
              "owner": "@alice",
              "urgency": "this_week"
            }
          ]
        }
      ]
    },
    {
      "channel": "DM with @bob",
      "channel_id": "D9876543210",
      "threads": [
        {
          "thread_ts": "1234567891.654321",
          "thread_link": "https://{slack_domain}/archives/D9876543210/p1234567891654321",
          "participants": ["@you", "@bob"],
          "summary": "Bob asked about deployment timeline for gen-ai package...",
          "actions_needed": [
            {
              "action": "Reply with updated deployment schedule",
              "owner": "@you",
              "urgency": "today"
            }
          ]
        }
      ]
    }
  ],
  "jira_mentions": [
    {
      "issue_key": "RHOAIENG-12345",
      "issue_summary": "Fix the widget",
      "issue_status": "In Progress",
      "issue_link": "{jira_base_url}/browse/RHOAIENG-12345",
      "comment_author": "Jane Doe",
      "comment_date": "2026-03-21T14:00:00.000+0000",
      "comment_text": "@you can you review this?"
    }
  ],
  "executive_summary": {
    "my_actions": [
      {
        "action": "Reply with updated deployment schedule",
        "urgency": "today",
        "channel": "DM with @bob",
        "thread_link": "https://{slack_domain}/archives/D9876543210/p1234567891654321"
      }
    ],
    "others_actions": [
      {
        "action": "Review PR #456 for model registry changes",
        "owner": "@alice",
        "urgency": "this_week",
        "channel": "#team-dashboard-crimson",
        "thread_link": "https://{slack_domain}/archives/C1234567890/p1234567890123456"
      }
    ],
    "key_highlights": [
      "Model registry API redesign discussion kicked off in #team-dashboard-crimson — consensus to use OpenAPI spec",
      "E2E pipeline fixed after 2-day outage — root cause was stale envtest binaries on self-hosted runners"
    ]
  },
  "summary_stats": {
    "total_channels": 7,
    "total_threads": 23,
    "total_actions": 5,
    "actions_today": 2,
    "actions_this_week": 2,
    "actions_later": 1,
    "jira_mentions": 1
  }
}
```

### Step 6a — Build executive summary (MANDATORY)

After assembling all channel threads and actions, build the `executive_summary` object at the top level of the digest JSON. This is what the user sees first, so make it concise and actionable.

Split actions into two lists based on whether the owner is `@{slack_username}` (from `user_config.json`):

1. **my_actions** — Actions where the owner is the user (`@{slack_username}`). Omit the `owner` field (it's implicit). Include `action`, `urgency` (`"today"` or `"this_week"`), `channel`, and `thread_link`. Sort by urgency: `"today"` items first, then `"this_week"`.
2. **others_actions** — Actions where the owner is someone else. Include `action`, `owner`, `urgency`, `channel`, and `thread_link`. Sort the same way: `"today"` first, then `"this_week"`.
3. **key_highlights** — Write 3-7 bullet points (plain strings) capturing the most important things that happened across all channels. Focus on decisions made, blockers raised, milestones hit, risks surfaced, and notable team events. Each bullet should be a single sentence. Do not repeat action items here — highlights are informational context.

Also present this executive summary directly to the user in your response (not just in the JSON). Format it as:

- A one-line stats banner (channels, threads, action counts)
- **My Actions** numbered list (items with urgency "today" get a **TODAY** label)
- **Others' Actions** numbered list (items with urgency "today" get a **TODAY** label)
- **Key Highlights** bulleted list

### Step 6b — Update active feature tracker (MANDATORY)

**This step MUST run on every digest invocation.** It refreshes progress data for the feature tracker panel in the viewer.

First, read `feature_watchlist.json` (in this skill's directory) to get the canonical list of Jira keys to track:

```json
{
  "features": ["RHAISTRAT-545", "RHAISTRAT-172", ...]
}
```

The user adds/removes keys in this file. Then read `active_features.json` and reconcile:
- **Add** any key present in `feature_watchlist.json` but missing from `active_features.json` (initialize with empty fields — they will be populated below).
- **Remove** any entry in `active_features.json` whose key is no longer in `feature_watchlist.json`.

For **each feature** (including those with status "Closed"), use the `jira_get_issue` MCP tool on `user-atlassian` to fetch the latest details:

```
server: user-atlassian
tool: jira_get_issue
args:
  issue_key: "RHAISTRAT-1112"
  fields: "summary,status,assignee,fixVersions,comment"
  comment_limit: 1
```

Then use `jira_search` on `user-atlassian` to find child issues (epics/tasks) with their summaries:

```
server: user-atlassian
tool: jira_search
args:
  jql: "parent = RHAISTRAT-1112 OR \"Epic Link\" = RHAISTRAT-1112"
  fields: "summary,status"
  limit: 50
```

Calculate progress as: `(closed or resolved issues / total issues) * 100`, rounded to nearest integer.

**Overwrite** each entry in `active_features.json` with fresh values — do not skip any fields or reuse stale data:
- **status** — current Jira status (e.g., "In Progress", "New")
- **assignee** — display name of the assignee
- **target_version** — first fixVersion name, or null
- **progress** — percentage (0-100) based on child issue completion
- **last_comment** — text of the most recent comment (truncated to 200 chars)
- **epics** — array of child issues, each with `key`, `summary`, and `status` (fetched fresh from the search above)
- **whats_next** — 1-2 sentence summary of what's coming next for this feature, based on in-progress/new child issues and recent Slack activity from the digest

Set `updated_at` to the current timestamp. Always write the file even if nothing changed — the timestamp itself is meaningful.

### Step 6c — Find Jiras mentioning me in comments

Search for Jira issues where the user is mentioned in comments using `jira_search` on `user-atlassian`.

**Important:** Jira Cloud stores @mentions using internal account IDs, not usernames. The `comment ~` JQL operator searches indexed text which contains the **display name**, not the username. Always search by display name first.

```
server: user-atlassian
tool: jira_search
args:
  jql: "comment ~ \"{jira_display_name}\" AND updated >= -3d"
  fields: "summary,status,comment"
  limit: 50
```

Also run a second search for the username as a fallback (catches plain-text references):

```
server: user-atlassian
tool: jira_search
args:
  jql: "comment ~ \"{jira_username}\" AND updated >= -3d"
  fields: "summary,status,comment"
  limit: 50
```

Deduplicate results by issue key across both searches.

For each result, use `jira_get_issue` on `user-atlassian` to fetch the full issue with comments:

```
server: user-atlassian
tool: jira_get_issue
args:
  issue_key: "PROJ-123"
  fields: "summary,status,comment"
  comment_limit: 5
  update_history: false
```

Scan comments for any that mention `{jira_username}` OR `{jira_display_name}` (case-insensitive match). For each matching comment, record:
- **issue_key** — the Jira key (e.g., "RHOAIENG-12345")
- **issue_summary** — the issue title
- **issue_status** — current status
- **issue_link** — `{jira_base_url}/browse/{issue_key}`
- **comment_author** — display name of the comment author
- **comment_date** — when the comment was created
- **comment_text** — the full comment text (truncated to 300 chars)

Write or update `jira_mentions.json` in this skill's directory. Deduplicate by issue_key + comment_date. Set `updated_at` to the current timestamp.

Additionally, filter the mentions whose `comment_date` falls on the target digest date and include them in the digest JSON as the `jira_mentions` array (see schema above). Update `summary_stats.jira_mentions` with the count.

### Step 7 — Generate the HTML report

After saving the JSON, update the viewer. The HTML viewer at `viewer/index.html` is a self-contained single-page app that:

- Loads all `digests/*.json` files via a manifest
- Shows a left sidebar with dates (most recent first)
- Shows the selected day's digest in the main view
- Defaults to the latest available digest

**Update the digest manifest** by reading all files in `digests/` and writing `viewer/digests-manifest.json`:

```json
{
  "last_updated": "2026-03-21T15:30:00Z",
  "digests": [
    { "date": "2026-03-21", "file": "2026-03-21.json" },
    { "date": "2026-03-20", "file": "2026-03-20.json" }
  ]
}
```

Sort entries newest-first. The viewer reads this manifest to build the navigation.

### Step 8 — Serve and view

Tell the user to serve the viewer:

```bash
npx serve .cursor/skills/daily-digest
```

Then open `/viewer/` in the browser.

## File Structure

```
cursor-skills/                            # Workspace root
├── user_config.json                      # Your identity + environment (create from .example)
├── user_config.example.json              # Template for user_config.json
└── .cursor/skills/daily-digest/
    ├── SKILL.md                          # This file
    ├── slack_channels_config.json        # Channels + DM config (create from .example)
    ├── slack_channels_config.example.json # Template for slack_channels_config.json
    ├── feature_watchlist.json            # User-managed list of Jira keys to track (create from .example)
    ├── feature_watchlist.example.json    # Template for feature_watchlist.json
    ├── active_features.json              # Auto-generated feature detail (do not edit)
    ├── jira_mentions.json                # Auto-generated Jira mentions (do not edit)
    ├── digests/                          # Auto-generated, one JSON per day
    │   └── YYYY-MM-DD.json
    └── viewer/
        ├── index.html                    # Self-contained HTML viewer
        └── digests-manifest.json         # Auto-generated manifest
```

## Notes

- Thread links use the Slack domain from the workspace-root `user_config.json` (`{slack_domain}`)
- When a channel has no activity for the target date, omit it from the digest (don't include empty channel entries)
- Group standalone messages (not in threads) that are related by topic into a single summary entry
- If rate-limited by Slack, pause and retry; inform the user of any channels that couldn't be fetched

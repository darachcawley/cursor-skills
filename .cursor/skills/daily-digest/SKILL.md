---
name: daily-digest
description: Generate a daily digest of Slack conversations across configured channels and DMs. Also searches what a specific person said on Slack on a given date. Use when the user asks for a daily digest, Slack summary, daily standup recap, conversation roundup, what someone said on Slack, a person's Slack activity, or to search a person's messages.
---

# Slack Daily Digest

Produce a summarized daily digest of Slack activity across configured channels and DMs for a given date. Outputs a structured JSON file per day and an HTML viewer to browse all digests.

## First-time setup

Before first use, copy each `.example.json` file to its real name and fill in your values:

1. `user_config.example.json` → `user_config.json` (in the **workspace root**, not this skill's directory) — your identity and environment (optional: `jira_email`, `jira_account_id` for reliable Jira @mention search in Step 6c; optional `obsidian_digest_path` for where Markdown is written at the end of Step 7)
2. `slack_channels_config.example.json` → `slack_channels_config.json` — Slack channels to monitor
3. `feature_watchlist.example.json` → `feature_watchlist.json` — Jira feature keys to track (optional); optional `epic_child_refresh` controls how often child issues are refetched (Step 6b)

You also need the following MCP servers configured in Cursor:
- **Slack MCP** — commonly `user-slack` or `user-user-slack` (provides `conversations_history`, `conversations_search_messages`, etc.); use whatever identifier Cursor shows for **your** Slack integration
- **Atlassian MCP** — commonly `user-atlassian` (provides `jira_get_issue`, `jira_search`); use your Cursor MCP identifier

## MCP Servers

This skill uses **only** the MCP servers configured in Cursor. Workflow steps below use placeholders **`{slack_mcp_server}`** and **`{atlassian_mcp_server}`** in every `server:` field—substitute the **actual** server names from your Cursor MCP configuration (Settings → MCP), not the example names above.

**Do NOT** use any other Slack MCP server than the one configured for your workspace.

## Required Input

The user must provide a **date** for the digest (e.g., `2026-03-21`, `yesterday`, `today`). If not provided, ask for it before proceeding. Normalize the date to `YYYY-MM-DD` format.

### Optional: Person activity search

The user may also provide a **person identifier** — a Slack handle, email address, or display name (e.g., `your-rh-handle@redhat.com`, `@your-rh-handle`, `Jane Smith`). When provided, Step 3d runs to search what that person said across all public channels on the target date. This can be used:

- **Alongside a full digest** — the person's activity is appended to the digest JSON and presented after the executive summary
- **On its own** — if the user only asks what a specific person said (without requesting a full digest), skip Steps 1–3c and 6b–6c, and only run Steps 0, 1b, 3d, 4, 5, 6, 6a, 7 (including the Markdown export at the end of Step 7), and 8

## Workflow

### Step 0 — Load user configuration

Read `user_config.json` (in the **workspace root**) to get the user's identity and environment. All subsequent steps use these values instead of hardcoded names or URLs.

```json
{
  "slack_username": "your-slack-username",
  "jira_display_name": "Your Full Name",
  "jira_username": "your-jira-username",
  "jira_email": "you@company.com",
  "jira_account_id": "712020:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "slack_domain": "your-company.enterprise.slack.com",
  "slack_dm_domain": "your-company-internal.slack.com",
  "jira_base_url": "https://your-company.atlassian.net",
  "obsidian_digest_path": ""
}
```

Use `{slack_username}`, `{jira_display_name}`, `{jira_username}`, `{jira_email}`, `{jira_account_id}`, `{slack_domain}`, `{slack_dm_domain}`, and `{jira_base_url}` as placeholders in the steps below. Substitute the actual values from the workspace-root `user_config.json` at runtime.

**MCP server placeholders:** Use `{slack_mcp_server}` for every Slack tool invocation (`channels_list`, `conversations_history`, `conversations_search_messages`, `conversations_replies`, `users_search`, etc.) and `{atlassian_mcp_server}` for every Atlassian/Jira tool. Read the actual names from Cursor’s MCP panel (e.g. `user-slack`, `user-user-slack`, `user-atlassian`).

**Optional Jira fields:** `jira_email` and `jira_account_id` are optional. Omit them or leave empty if unused.

**Obsidian Markdown output directory:** `obsidian_digest_path` — optional absolute path to a folder inside your Obsidian vault. If omitted or empty, Step 7 writes Markdown under this skill’s `markdown/` directory (you can symlink that folder into a vault).

**Atlassian MCP identity:** JQL `currentUser()` refers to whoever authenticated the **`{atlassian_mcp_server}`** MCP connection (OAuth or API token owner). That is usually your own Atlassian account when you connect the integration in Cursor. If `comment ~ currentUser()` returns no rows but you know you have mentions, or results clearly belong to a different identity, treat the connection as non-matching and rely on `jira_account_id` (see Step 6c).

**Resolve `jira_account_id` when missing:** Before Step 6c, if `jira_account_id` is absent or blank, call `jira_get_user_profile` on `{atlassian_mcp_server}` with `user_identifier` set to `{jira_email}` if configured, otherwise `{jira_username}`. From the response, read the Atlassian account ID field (commonly `accountId`). Use that value for AAID-based JQL in Step 6c and suggest the user persist it in `user_config.json`.

**Note:** Some Slack workspaces use different domains for channel links vs DM links (e.g., `redhat.enterprise.slack.com` for channels but `redhat-internal.slack.com` for DMs). Use `{slack_dm_domain}` for all DM thread links (self-DMs and DMs with others). If `slack_dm_domain` is not set, fall back to `{slack_domain}`.

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

### Step 1b — Resolve channel IDs

Slack deep links require **channel IDs** (e.g., `C09S4J8TV5Y`), not channel names. Before fetching messages, use `channels_list` on `{slack_mcp_server}` to get a mapping of channel names to IDs:

```
server: {slack_mcp_server}
tool: channels_list
args:
  channel_types: "public_channel,private_channel"
  limit: 999
```

Also fetch **all** IM (1:1 DM) rows and **all** MPIM rows so self-DM resolution, DM/MPDM **`thread_link`** ids, and **[slack-dm-list](../slack-dm-list/SKILL.md)** (invoked from Step 3b) have complete maps:

```
server: {slack_mcp_server}
tool: channels_list
args:
  channel_types: "im"
  limit: 999
```

```
server: {slack_mcp_server}
tool: channels_list
args:
  channel_types: "mpim"
  limit: 999
```

For **both** `im` and `mpim`, paginate with **`cursor`** until no further cursor—do not assume one page lists every conversation.

The self-DM channel is the IM entry named `@{slack_username}` (e.g., `D06BXAVPNA2` for `@dcawley`). Record its **`D…` id** as **`self_dm_channel_id`** for Step 3 and Step 3b (exclude self-DM from the Step 3b “with others / group” bucket).

Build a lookup map from configured **public/private** channel name → channel ID. Use these IDs in **all** `thread_link` fields for configured channels. For **1:1** DMs use **`D…`** with `{slack_dm_domain}`; for **MPDMs** use **`C…`** with the domain rules in Step 5.

**ID maps for Step 3b (slack-dm-list + digest links):** From `channels_list` (`im`) results, for **each** IM row record **`dm_channel_id`** (`D…`) and **`dm_peer_scope`** (Name column, e.g. `@handle`). Build an optional **`@handle` → `D…`** map for resolving bulk-search rows. From `mpim` results, map **`mpdm_name`** (row `Name` / `#mpdm-…`) → **`mpdm_channel_id`** (`C…`) and a display string from **Purpose** / **Topic**. **`dm_peer_scope`** / **`dm_channel_id`** are used for **legacy fallback** in Step 3b only if bulk `is:dm` fails.

(Do not use these maps to change Step 2 or Step 3c.)

### Step 2 — Fetch channel messages for the target date

For **each channel** in the config, use the `conversations_history` MCP tool on `{slack_mcp_server}`:

```
server: {slack_mcp_server}
tool: conversations_history
args:
  channel_id: "#channel-name"
  limit: "1d"
```

The `limit: "1d"` fetches one day of history. If the target date is not today, use `conversations_search_messages` with date filters instead:

```
server: {slack_mcp_server}
tool: conversations_search_messages
args:
  filter_in_channel: "#channel-name"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

### Step 3 — Fetch self-DMs (notes to self)

Always fetch messages the user sent to themselves. These are personal reminders, action items, and reference links that should appear in the digest as actions.

For today, use `conversations_history` on `{slack_mcp_server}`:

```
server: {slack_mcp_server}
tool: conversations_history
args:
  channel_id: "@{slack_username}"
  limit: "1d"
```

For historical dates, use `conversations_search_messages` on `{slack_mcp_server}`:

```
server: {slack_mcp_server}
tool: conversations_search_messages
args:
  filter_in_im_or_mpim: "@{slack_username}"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

Treat every self-DM as an action item. Set urgency based on the message content (default to `"today"` unless the message clearly refers to a future date). Include these in the digest under a channel entry named `"Self (notes/reminders)"`.

### Step 3b — Fetch DMs with others and group DMs (if enabled)

If `include_dms` is true, **delegate DM discovery and bulk fetch** to the **[slack-dm-list](../slack-dm-list/SKILL.md)** skill, then merge results into the digest pipeline. This **does not** change Step 2 (channels), Step 3 (self-DM), or Step 3c (usergroup searches).

**MCP alignment:** Read the `conversations_search_messages` tool descriptor on `{slack_mcp_server}` before calling (required by slack-dm-list and this step).

**Primary path — invoke slack-dm-list**

1. **Read** [slack-dm-list/SKILL.md](../slack-dm-list/SKILL.md) in full at the start of this step (same workspace: `.cursor/skills/slack-dm-list/SKILL.md`).
2. Run **slack-dm-list** [Workflow](../slack-dm-list/SKILL.md#workflow) steps **1 — Bulk search** and **2 — Dedupe by conversation** using digest date **`D`** as the target date and the same **`{slack_mcp_server}`** as the rest of this digest.
3. **Digest-specific:** Unlike a standalone slack-dm-list user reply (which may present only a table), for the digest you **must retain all message rows** from the bulk search, **grouped by `Channel`**, for Steps **4** (`conversations_replies`) and **5** (summarization). Do not drop message text after deduping.
4. Run **slack-dm-list** step **3 — Labels** to set digest **`channel`** display names (`"DM with @peer"`, `"MPDM: …"`, etc.). **Omit** the self-DM conversation from Step 3b’s grouped results: use **`self_dm_channel_id`** from Step 1b so self-DM content stays **only** under Step 3’s `"Self (notes/reminders)"`.
5. Resolve **`channel_id`** and archive ids for **`thread_link`** using **slack-dm-list** step **4 — Optional archive links** (optional `channels_list`) **plus** Step 1b ID maps. Apply **`{slack_dm_domain}`** / `{slack_domain}` per Step 5 in this skill.
6. **Empty vs error:** Follow slack-dm-list **Failure handling** and daily-digest **Safe write rules**: bulk search completes with **zero rows** ⇒ no DM/MPDM activity for `D` in search scope (valid empty). **Do not** treat as Slack-unhealthy.
7. **Optional supplements** (only if the bulk `is:dm` path **errors** or a **`channel_id` cannot be resolved** after slack-dm-list fallbacks): you may use narrow `conversations_history` / client-side filtering to calendar **`D`**; mark **`key_highlights`** **best-effort** when you rely on this.

**Legacy fallback (daily-digest only — if bulk `is:dm` is unsupported or errors on `{slack_mcp_server}`):** Do **not** use the slack-dm-list primary path. Instead: use Step 1b **paginated** `im` rows, **exclude** self-DM; for **each** remaining IM run `conversations_search_messages` with `filter_date_on: D` and `filter_in_im_or_mpim` try-order **(A)** `dm_peer_scope`, **(B)** `dm_channel_id` if the MCP documents `D…` for that parameter, **(C)** record IM as skipped if both fail. For **MPDMs** on `D` not returned by a failed bulk attempt, use `channels_list` (`mpim`) and scoped search only where needed. There is **no** 50-IM cap when paginating the full `im` list. List skipped or partial DMs in **`key_highlights`**.

**Do not use** `conversations_unreads` as the primary source for DM activity on date `D` — it reflects unread state, not full history for `D`. You may still call `conversations_unreads` for diagnostics only; it must not replace Steps 1–3 above for building the digest content.

### Step 3c — Search for usergroup mentions

For each group in `mention_groups`, search for messages that `@mention` that group on the target date. This catches messages in channels not in the configured list that still need attention.

```
server: {slack_mcp_server}
tool: conversations_search_messages
args:
  search_query: "@openshift-ai-exploring-managers"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

Deduplicate against messages already fetched from configured channels. For any new messages found, include them in the digest under a channel entry named `"Mentions (@group-name)"` — e.g. `"Mentions (@openshift-ai-exploring-managers)"`. The channel name **must** start with `"Mentions ("` so the viewer can identify these as tagged items. The viewer automatically labels these actions as **"Tagged"** and routes them to the **My Actions** tab (since the user was directly mentioned via a group they belong to). Treat these as action items with urgency `"this_week"` unless the content indicates higher urgency.

### Step 3d — Person activity search (OPTIONAL)

**Only run this step if the user provided a person identifier.** This searches all public channels for what a specific person said on the target date.

#### 3d.1 — Resolve the person

Use `users_search` on `{slack_mcp_server}` to resolve the person's identity:

```
server: {slack_mcp_server}
tool: users_search
args:
  query: "<email or handle provided by user>"
  limit: 5
```

From the results, identify the correct user. Extract:
- **slack_user_id** — the Slack user ID (e.g., `U1234567890`)
- **slack_username** — their Slack username (e.g., `your-rh-handle`)
- **display_name** — their display name (e.g., `Jane Smith`)
- **email** — their email address

If multiple results are returned, pick the best match. If no results, inform the user and stop.

#### 3d.2 — Search for the person's messages

Use `conversations_search_messages` on `{slack_mcp_server}` to find all messages from the person on the target date across all public channels:

```
server: {slack_mcp_server}
tool: conversations_search_messages
args:
  filter_users_from: "@<slack_username>"
  filter_date_on: "YYYY-MM-DD"
  limit: 100
```

This searches across all public channels — no channel list needed.

If the results are paginated (a cursor is returned), fetch additional pages until all are retrieved.

#### 3d.3 — Fetch full thread context

For each message that is part of a thread (has a `thread_ts`), fetch the full thread:

```
server: {slack_mcp_server}
tool: conversations_replies
args:
  channel_id: "<channel_id from search result>"
  thread_ts: "<thread_ts>"
  limit: "50"
```

Deduplicate threads — if the person sent multiple messages in the same thread, only fetch the thread once.

#### 3d.4 — Summarize each thread

For each thread the person participated in, produce:

1. **summary** — 1-3 sentence summary of the overall thread conversation
2. **person_said** — 1-3 sentence summary specifically of what the target person contributed (their messages, opinions, decisions, commitments)
3. **participants** — list of Slack usernames who participated in the thread
4. **thread_link** — Slack deep link: `https://{slack_domain}/archives/{channel_id}/p{thread_ts_no_dot}`

For standalone messages (not in a thread), treat each as its own entry.

#### 3d.5 — Build person activity output

Assemble the person activity into the `person_activity` object (see schema in Step 6) and also write a standalone report to `reports/YYYY-MM-DD-<slack_username>.json` in this skill's directory.

**Update the reports manifest** by reading all files in `reports/` and writing `viewer/reports-manifest.json`:

```json
{
  "last_updated": "2026-04-01T15:30:00Z",
  "reports": [
    { "date": "2026-04-01", "person": "jsmith", "display_name": "Jane Smith", "file": "2026-04-01-jsmith.json" }
  ]
}
```

Sort entries newest-first. The viewer reads this manifest to populate the **People** tab under To Do.

Report schema:

```json
{
  "person": {
    "email": "your-rh-handle@redhat.com",
    "slack_username": "@your-rh-handle",
    "display_name": "Jane Smith",
    "slack_user_id": "U1234567890"
  },
  "date": "2026-04-01",
  "generated_at": "2026-04-01T15:30:00Z",
  "channels": [
    {
      "channel": "#team-dashboard-crimson",
      "channel_id": "C1234567890",
      "threads": [
        {
          "thread_ts": "1234567890.123456",
          "thread_link": "https://{slack_domain}/archives/C1234567890/p1234567890123456",
          "participants": ["@your-rh-handle", "@alice", "@bob"],
          "summary": "Team discussed the new PatternFly 6 migration timeline.",
          "person_said": "Jane proposed a phased migration starting with layout components."
        }
      ]
    }
  ],
  "overall_summary": "Jane was active in 3 channels across 5 threads...",
  "stats": {
    "total_channels": 3,
    "total_threads": 5,
    "total_messages": 12
  }
}
```

#### 3d.6 — Present person activity

After saving the JSON, present an inline summary of the person's activity:

1. **Person banner** — who was searched, the date, message count
2. **Per-channel breakdown** — for each channel, list threads with the `person_said` summary
3. **Overall summary**
4. **File location** — where the report was saved

Format example:

> **Slack activity for Jane Smith (@your-rh-handle) on 2026-04-01**
> 3 channels · 5 threads · 12 messages
>
> **#team-dashboard-crimson** (2 threads)
> - *PatternFly 6 migration*: Jane proposed a phased migration starting with layout components...
> - *Sprint retro*: Jane flagged CI pipeline flakiness as the top concern...

### Step 4 — Fetch thread replies

For any message that is a thread parent (has `reply_count > 0` or `thread_ts`), fetch the full thread using `{slack_mcp_server}`:

```
server: {slack_mcp_server}
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
3. **action_owner** — Who likely needs to perform each action (use Slack handles, e.g. `@alice`). Assign `@{slack_username}` when the user is clearly the right owner — they were asked to do something, volunteered, or the action falls under their responsibility based on context. If no specific individual can be reasonably identified as the owner, use `@team` — do not default to `@{slack_username}` just because they are reading the digest.
4. **urgency** — One of: `"today"`, `"this_week"`, `"later"`
5. **thread_link** — Slack deep link to the thread: `https://{domain}/archives/{channel_id}/p{thread_ts_no_dot}` — **IMPORTANT**: `{channel_id}` must be the Slack channel ID (e.g., `C09S4J8TV5Y`) resolved in Step 1b, NOT the channel name. For DMs (channel IDs starting with `D`), use `{slack_dm_domain}` as the domain. For channels (IDs starting with `C`), use `{slack_domain}`. Links with channel names will not open in Slack.

#### Urgency classification rules

- **today**: Explicit deadlines for today, blockers, urgent requests, production issues, review requests with same-day expectations
- **this_week**: Items with near-term deadlines, follow-ups expected this week, PR reviews, meeting action items
- **later**: FYI messages, long-term planning discussions, ideas, nice-to-haves, informational updates

### Step 6 — Build the daily digest JSON

Write the digest to `digests/YYYY-MM-DD.json` in this skill's directory. **Before writing, follow the “Safe write rules (digests)” section below** (merge-by-source, preserve on MCP failure). Use this schema:

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
  "person_activity": {
    "person": {
      "email": "your-rh-handle@redhat.com",
      "slack_username": "@your-rh-handle",
      "display_name": "Jane Smith",
      "slack_user_id": "U1234567890"
    },
    "channels": [
      {
        "channel": "#team-dashboard-crimson",
        "channel_id": "C1234567890",
        "threads": [
          {
            "thread_ts": "1234567890.123456",
            "thread_link": "https://{slack_domain}/archives/C1234567890/p1234567890123456",
            "participants": ["@your-rh-handle", "@alice"],
            "summary": "Discussed the new model registry API changes...",
            "person_said": "Jane proposed using OpenAPI spec and volunteered to write the migration guide."
          }
        ]
      }
    ],
    "overall_summary": "Jane was active in 3 channels across 5 threads...",
    "stats": { "total_channels": 3, "total_threads": 5, "total_messages": 12 }
  },
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
  },
  "slack_fetch_status": "ok",
  "jira_fetch_status": "ok",
  "last_successful_slack_merge_at": "2026-03-21T15:30:00Z",
  "last_successful_jira_merge_at": "2026-03-21T15:30:00Z"
}
```

**Optional provenance fields** (viewer ignores; set when using safe merge):

| Field | Values | Meaning |
|-------|--------|--------|
| `slack_fetch_status` | `"ok"` \| `"failed"` \| `"skipped"` | Slack MCP / steps completed successfully, errored, or not run (e.g. person-only run) |
| `jira_fetch_status` | `"ok"` \| `"failed"` \| `"skipped"` | Jira steps completed successfully, errored, or skipped |
| `last_successful_slack_merge_at` | ISO timestamp | When Slack-derived digest content was last successfully written |
| `last_successful_jira_merge_at` | ISO timestamp | When Jira-derived sections for this digest were last successfully merged |

### Safe write rules (digests)

**Goal:** Never replace a **richer** existing digest with **emptier** data because Slack or Jira MCP broke, auth failed, or tools returned no results for a **bad** reason.

#### Detect source health

- **Slack unhealthy** if: MCP/tool unavailable, auth failed, rate-limit abort, or any step in 1b–3c did not complete successfully for **configured** channels. **Do not** infer failure from “zero messages” alone if each channel was **successfully** fetched (no activity is valid). The same applies to **Step 3b**: if the **slack-dm-list bulk `is:dm` path** (or, when used, **legacy per-IM** attempts) **completed without tool error**, zero DM/MPDM rows for `D` is **valid empty**, not Slack-unhealthy—do not assume “there are always DMs.”
- **Slack healthy** if: `conversations_history` / `conversations_search_messages` (etc.) completed **per channel** (or per scope) for date `D` without tool error, including Step 3b **slack-dm-list bulk search pagination** finishing without MCP outage (or legacy fallback completing / deterministically skipping IMs without outage).
- **Jira unhealthy** if: `jira_search` / `jira_get_issue` / `jira_get_user_profile` throws, auth fails, or MCP returns an explicit error. **Do not** treat “0 search results” as failure by itself—empty results can be legitimate.
- **Jira healthy** if: Steps 6b–6c complete without tool errors (even when zero mentions).

#### Never clobber good data

1. If `digests/D.json` **already exists** with non-empty **`channels`** (or non-zero Slack-derived `summary_stats` / `executive_summary` content), and this run would write **empty** `channels` **because Slack was unhealthy** → **retain** the previous file’s **`channels`**, **`person_activity`** (if any), and Slack-related parts of **`executive_summary`** and **`summary_stats`**. Optionally merge: keep prior **`executive_summary`** entirely if splitting Slack vs Jira bullets is ambiguous.
2. If **Slack is healthy** and the day truly had no messages in scope → empty `channels` is correct.
3. If **Jira unhealthy** for this run → **do not** clear existing **`jira_mentions`** in `digests/D.json`; **do not** wipe **`jira_mentions.json`** on tool error. **Preserve** prior digest Jira rows and merged file contents unless Jira was healthy and you intentionally re-filtered mentions for `D`.
4. **User override:** Only replace preserved content if the user explicitly asks to **reset/clear** that day’s digest.

#### Merge algorithm (when writing `digests/D.json`)

1. Read **existing** `digests/D.json` if present; parse `slack_fetch_status` / `jira_fetch_status` if set.
2. Run Slack pipeline (Steps 1–5, etc.). Set **`slack_fetch_status`** to `"ok"` or `"failed"` / `"skipped"` as appropriate.
3. Run Jira pipeline (6b–6c). Set **`jira_fetch_status`** to `"ok"` or `"failed"` / `"skipped"`.
4. **Channels / person_activity / Slack stats:** If Slack is **`ok`**, use newly built content and set **`last_successful_slack_merge_at`** to `generated_at`. If Slack is **not ok** and existing file has Slack content → **copy forward** from existing file; keep prior **`last_successful_slack_merge_at`** (or leave unchanged).
5. **Jira mentions in digest:** If Jira is **`ok`**, use newly filtered mentions for `D` and set **`last_successful_jira_merge_at`**. If Jira **not ok** → copy forward **`jira_mentions`** from existing file.
6. **`executive_summary` / `summary_stats`:** Rebuild from the **merged** Slack + Jira content when either source is fresh; if only one source is fresh, merge highlights so you do not drop the other source’s prior bullets. If both failed, keep prior **`executive_summary`** entirely.
7. **Append** a **`key_highlights`** line when content was retained due to failure, e.g. `Slack refresh failed; earlier Slack content for this date was preserved.`
8. Set **`generated_at`** to now even on partial merges.

#### Optional backup before replace

Before overwriting `digests/D.json`, copy it to `digests/.backups/D-<ISO8601>.json` (same directory). Keeps a recoverable snapshot if the merge logic mis-fires. See File Structure below.

### Step 6a — Build executive summary (MANDATORY)

After assembling all channel threads and actions, build the `executive_summary` object at the top level of the digest JSON. This is what the user sees first, so make it concise and actionable.

When applying **safe merge** (see **Safe write rules (digests)** above), build **`executive_summary`** from the **final merged** Slack + Jira content (after copy-forward), not from a failed partial fetch alone.

Split actions into two lists based on whether the owner is `@{slack_username}` (from `user_config.json`):

1. **my_actions** — Actions where `@{slack_username}` is the owner because they were asked, volunteered, or are clearly responsible based on context. Omit the `owner` field (it's implicit). Include `action`, `urgency` (`"today"` or `"this_week"`), `channel`, and `thread_link`. Sort by urgency: `"today"` items first, then `"this_week"`.
2. **others_actions** — Actions where the owner is someone else (including `@team` for actions with no clear individual owner). Include `action`, `owner`, `urgency`, `channel`, and `thread_link`. Sort the same way: `"today"` first, then `"this_week"`.
3. **key_highlights** — Write 3-7 bullet points (plain strings) capturing the most important things that happened across all channels. Focus on decisions made, blockers raised, milestones hit, risks surfaced, and notable team events. Each bullet should be a single sentence. Do not repeat action items here — highlights are informational context.

Also present this executive summary directly to the user in your response (not just in the JSON). Format it as:

- A one-line stats banner (channels, threads, action counts)
- **My Actions** numbered list (items with urgency "today" get a **TODAY** label)
- **Others' Actions** numbered list (items with urgency "today" get a **TODAY** label)
- **Key Highlights** bulleted list

### Step 6b — Update active feature tracker (MANDATORY)

**This step MUST run on every digest invocation.** It refreshes progress data for the feature tracker panel in the viewer.

First, read `feature_watchlist.json` (in this skill's directory) to get the canonical list of Jira keys and optional refresh settings:

```json
{
  "features": ["RHAISTRAT-545", "RHAISTRAT-172"],
  "epic_child_refresh": "every_run"
}
```

- **features** — Jira issue keys to track (required).
- **epic_child_refresh** — optional, default `"every_run"`. Use `"weekly"` to refresh child-issue lists and progress **at most once per rolling 7-day window** (see delta logic below). Parent issue fields still refresh every run when the parent’s `updated` changes.

The user adds/removes keys in this file. Then read `active_features.json` and `jira_local_state.json` (create if missing) and reconcile:
- **Add** any key present in `feature_watchlist.json` but missing from `active_features.json` (initialize with empty fields — they will be populated below).
- **Remove** any entry in `active_features.json` whose key is no longer in `feature_watchlist.json`.

**Goal:** Minimize Jira calls by **batching** searches and **skipping redundant child searches** when safe.

**MCP guardrail:** If the Atlassian MCP is configured with `projects_filter` (or env) restricting projects, a batched `key in (...)` query only returns issues in allowed projects. Missing keys are not errors—note any expected key absent from results.

#### 6b.1 — Batch-fetch parent issues (replace N × `jira_get_issue`)

Build JQL `key in (KEY1, KEY2, …)` for all watchlist keys. **Chunk keys into groups of at most 50** per `jira_search` call (API result limit is 50 issues per page). Paginate with `start_at` / `page_token` until all keys are covered.

```
server: {atlassian_mcp_server}
tool: jira_search
args:
  jql: "key in (RHAISTRAT-545, RHAISTRAT-172, RHAISTRAT-1112)"
  fields: "summary,status,assignee,fixVersions,updated,comment"
  limit: 50
```

Use `comment` from search results for **last_comment** when the API returns enough; if not, call `jira_get_issue` **only for keys** that need a fresher comment (see delta below).

#### 6b.2 — Delta refresh (optional, fewer `get_issue` / child searches)

For each feature key, compare the Jira **`updated`** field from the batch result with **`jira_issue_updated`** stored on the previous `active_features.json` entry (see schema below).

- If **`updated` is unchanged** and **`epic_child_refresh` is `"weekly"`** and a full child refresh ran within the last 7 days (see `last_children_full_refresh_at` in `jira_local_state.json`), **reuse** the prior entry’s **epics** array and **progress**; still refresh **whats_next** from the current digest’s Slack context.
- If **`updated` changed**, or the key is new, or weekly mode is due for children, fetch children as in 6b.3.
- **children_fingerprint** (optional): a stable string of sorted `childKey|status` from the last child search. If parent `updated` is unchanged **and** fingerprint matches a quick **no-op** check, you may skip the child `jira_search` even in `every_run` mode (advanced; optional).

#### 6b.3 — Batch-fetch child issues (replace N × per-parent `jira_search`)

For keys that need fresh children, build **one** JQL per chunk of parent keys (chunk to stay within JQL length limits and result sizes), e.g.:

`((parent in (KEY1, KEY2, …)) OR ("Epic Link" in (KEY1, KEY2, …)))`

Some projects use different epic linking; if the batch returns incomplete data for a key, fall back to the per-key query from the older workflow:

`parent = KEY OR "Epic Link" = KEY`

Paginate until all child issues are retrieved. Compute **progress** as: `(closed or resolved issues / total issues) * 100`, rounded to nearest integer.

When `epic_child_refresh` is `"weekly"`, run the full batched child search only if `last_children_full_refresh_at` is older than 7 days or missing; otherwise reuse stored **epics** / **progress** from `active_features.json` and set `updated_at` on the file.

#### 6b.4 — Write `active_features.json`

**Overwrite** the file with a top-level object the viewer expects: `{ "features": [ … ] }` (see [`viewer/index.html`](viewer/index.html) `loadFeatureTracker`). Each feature object includes:

- **key**, **summary**, **status**, **assignee**, **target_version**, **progress**, **last_comment**, **epics**, **whats_next** — same meaning as before.
- **jira_issue_updated** — Jira’s issue `updated` timestamp (ISO string) from the API for delta logic next run.

Set file-level `updated_at` to the current timestamp. When using weekly child refresh, update `jira_local_state.json` **last_children_full_refresh_at** whenever you perform a full batched child search.

**Fields:** Keep requests minimal — never use `*all` for this step.

### Step 6c — Find Jiras mentioning me in comments

Search for issues where **you** were @mentioned or otherwise referenced in comments, using `jira_search` on `{atlassian_mcp_server}`.

**Why display-name-only search fails:** Jira Cloud stores @mentions as `[~accountid:AAID]`. Indexed search matches the **AAID**, not display name or username. See [Atlassian: search @mentions with JQL](https://community.atlassian.com/forums/Jira-articles/How-to-search-for-your-mentions-with-JQL/ba-p/2771763).

#### 6c.0 — Time window `window_start` (digest-aware, fewer candidates)

Let `D` be the digest date (`YYYY-MM-DD`) and `T` be **today’s** date in the same calendar system you use for the digest.

- If **`|D − T| ≤ 1` day** (digest is today or yesterday): set `window_start` to **`D` minus 3 calendar days** (short window; still tolerates timezone drift).
- **Else** (backfilled digest): set `window_start` to **`D` minus 14 calendar days**.

Always combine with: `updated >= "{window_start}"` (never `updated >= -3d` relative to run time).

#### 6c.1 — Primary mention search: run **one** of (A) or (B), not both

**Goal:** Avoid duplicate JQL when `currentUser()` and AAID would return the same issues.

- **(A)** If `jira_account_id` is set after Step 0 — run **only**:

```
server: {atlassian_mcp_server}
tool: jira_search
args:
  jql: "comment ~ \"{jira_account_id}\" AND updated >= \"{window_start}\""
  fields: "summary,status,comment"
  limit: 50
```

- **(B)** If `jira_account_id` is **not** set — run **only**:

```
server: {atlassian_mcp_server}
tool: jira_search
args:
  jql: "comment ~ currentUser() AND updated >= \"{window_start}\""
  fields: "summary,status,comment"
  limit: 50
```

Run the **other** query only when troubleshooting identity mismatch (e.g. MCP token is a service account).

#### 6c.2 — Plain-text fallbacks (conditional — only if primary returned **zero** issues)

Only if the primary search returned no issues, run **one or both** (order does not matter):

```
jql: "comment ~ \"{jira_display_name}\" AND updated >= \"{window_start}\""
```

```
jql: "comment ~ \"{jira_username}\" AND updated >= \"{window_start}\""
```

These catch literal text, not `@mention` tokens.

#### 6c.3 — Pagination cap

If results hit the 50-issue cap, paginate with `start_at` or `page_token`, but stop after **at most 5 pages** (250 issues) unless the user explicitly asks for full history—prevents runaway API usage.

#### 6c.4 — Optional: same-digest cache (`jira_local_state.json`)

Read `jira_local_state.json` (same directory as this skill). If `step_6c_last.digest_date` equals the current `D` **and** `step_6c_last.window_start` equals the computed `window_start`, you **may** reuse `step_6c_last.issue_keys` as the deduped key list and skip repeating **primary** JQL—still run `jira_get_issue` if you need fresh comment bodies. Update `step_6c_last` after a full search.

#### 6c.5 — Fetch issue comments

For each unique issue key from searches, use `jira_get_issue`:

```
server: {atlassian_mcp_server}
tool: jira_get_issue
args:
  issue_key: "PROJ-123"
  fields: "summary,status,comment"
  comment_limit: 50
  update_history: false
```

Keep **fields** minimal; avoid `*all`.

#### 6c.6 — Optional: `jira_batch_get_changelogs` (Jira Cloud only)

For large issues where `comment_limit: 50` is heavy, you **may** use `jira_batch_get_changelogs` on `{atlassian_mcp_server}` with comma-separated `issue_ids_or_keys` and `fields` filtering to **comment**-related history to spot recent comment activity with less payload than loading all comments—**only** when you are confident parsing changelog entries. If unsure, keep `jira_get_issue`.

```
server: {atlassian_mcp_server}
tool: jira_batch_get_changelogs
args:
  issue_ids_or_keys: "PROJ-123,PROJ-456"
  limit: 20
```

Use optional `fields` on this tool only if you know which issue fields to filter (see MCP tool schema). Cloud only; not available on Server/Data Center.

#### 6c.7 — Scan comment bodies

Include a comment when:

- `{jira_account_id}` is known and the body contains that id or `[~accountid:{jira_account_id}]`
- The body contains `{jira_username}` or `{jira_display_name}` as plain text

Issues from the primary JQL only prove *some* comment matches; still apply checks **per comment**. **Without** `jira_account_id`, complete Step 0 profile lookup so token matching works.

For each matching comment, record:

- **issue_key**, **issue_summary**, **issue_status**, **issue_link**, **comment_author**, **comment_date**, **comment_text** (truncated to 300 chars)

#### 6c.8 — Merge into `jira_mentions.json` (local state)

Write **`jira_mentions.json`** in this skill’s directory using a stable shape for the viewer:

```json
{
  "updated_at": "2026-04-10T15:30:00Z",
  "mentions": [ … ]
}
```

The viewer loads `mentions` from this file ([`viewer/index.html`](viewer/index.html) `fetchJiraMentions`).

**Merge semantics:** Read the existing file if present. **Merge** new records into `mentions` by deduplicating on **`issue_key` + `comment_date`** (match ISO timestamps to second precision or normalize). **Do not** drop older mention rows from previous runs—append new ones so the file accumulates history for the To Do / People views. Set top-level `updated_at` to now.

If Step 6c **failed** (Jira MCP unhealthy), **do not** replace `jira_mentions.json` with an empty list—leave the file unchanged and align with **Safe write rules (digests)** for the digest JSON’s `jira_mentions` array.

Additionally, filter mentions whose `comment_date` falls on the target digest date `D` and include **only those** in the digest JSON `jira_mentions` array. Update `summary_stats.jira_mentions` with that count.

### Step 7 — Generate the HTML report and Obsidian Markdown

After saving the JSON (using **safe write** / merge rules so MCP failures do not wipe prior content), update the viewer. The HTML viewer at `viewer/index.html` is a self-contained single-page app that:

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

**Copy user config into viewer** so the static file server can access it (the workspace-root file is outside the serve root):

```bash
cp user_config.json viewer/user_config.json
```

The path is relative to this skill's directory. This ensures `MY_USER` loads correctly for the My Actions / To Watch split. The viewer already checks `./user_config.json` as a fallback path.

**Markdown export (mandatory):** Immediately after the digest file `digests/D.json` for the target date `D` is present and the manifest step above is done, **run** the exporter from the **workspace root** so Obsidian receives an up-to-date note. Do not skip this step when executing the skill in an environment where shell commands are available.

```bash
python3 .cursor/skills/daily-digest/export_digest_to_md.py .cursor/skills/daily-digest/digests/D.json
```

Substitute `D` with the digest date `YYYY-MM-DD` (e.g. `2026-04-10.json`). Output goes to `obsidian_digest_path` from workspace-root `user_config.json` when set; otherwise to `markdown/D.md` under this skill directory.

If the command fails, report the error to the user; the digest JSON remains the source of truth—fix the environment or re-run the command manually. If the agent cannot run shell commands, instruct the user to run the same command once.

**Backfill** (optional, not part of every run): export every digest JSON at once:

```bash
python3 .cursor/skills/daily-digest/export_digest_to_md.py --all
```

**Override output directory** for a one-off run (optional):

```bash
python3 .cursor/skills/daily-digest/export_digest_to_md.py --output-dir "/path/to/vault/Daily Digests" .cursor/skills/daily-digest/digests/D.json
```

Each Markdown file includes YAML front matter (`date`, `tags`, `source`), executive summary sections, Jira mentions, and per-channel thread summaries with Slack links.

### Step 8 — Serve and view

Tell the user to serve the viewer:

```bash
npx serve .cursor/skills/daily-digest
```

Then open `/viewer/` in the browser.

## File Structure

```
cursor-skills/                            # Workspace root
├── user_config.json                      # Your identity + environment (optional: jira_email, jira_account_id for Step 6c; optional obsidian_digest_path for Markdown output in Step 7)
├── user_config.example.json              # Template for user_config.json
└── .cursor/skills/daily-digest/
    ├── SKILL.md                          # This file
    ├── slack_channels_config.json        # Channels + DM config (create from .example)
    ├── slack_channels_config.example.json # Template for slack_channels_config.json
    ├── feature_watchlist.json            # User-managed list of Jira keys to track (create from .example)
    ├── feature_watchlist.example.json    # Template for feature_watchlist.json
    ├── close_circle.json                 # Slack handles of people in your close circle (viewer tab)
    ├── active_features.json              # Auto-generated feature detail (do not edit); includes jira_issue_updated for delta refresh
    ├── jira_local_state.json             # Auto-generated: last_children_full_refresh_at, step_6c_last cache (optional)
    ├── jira_mentions.json                # Auto-generated merged mention history; top-level `mentions` array for viewer
    ├── export_digest_to_md.py            # Export digest JSON → Markdown for Obsidian (run at end of Step 7)
    ├── markdown/                         # Default output for .md exports (or use obsidian_digest_path)
    ├── digests/                          # Auto-generated, one JSON per day
    │   ├── YYYY-MM-DD.json
    │   └── .backups/                     # Optional: timestamped copies before overwrite (see Safe write rules)
    ├── reports/                          # Auto-generated person activity reports (Step 3d)
    │   └── YYYY-MM-DD-<username>.json
    └── viewer/
        ├── index.html                    # Self-contained HTML viewer
        ├── digests-manifest.json         # Auto-generated digest manifest
        └── reports-manifest.json         # Auto-generated person reports manifest
```

## Notes

- Thread links use the Slack domain from the workspace-root `user_config.json` (`{slack_domain}`)
- When a channel has no activity for the target date, omit it from the digest (don't include empty channel entries)
- Group standalone messages (not in threads) that are related by topic into a single summary entry
- If rate-limited by Slack, pause and retry; inform the user of any channels that couldn't be fetched
- **DMs and group DMs (Step 3b):** Delegates bulk fetch and dedupe to **[slack-dm-list](../slack-dm-list/SKILL.md)** (Workflow steps 1–2), keeps **full message rows** for digest summarization, applies steps **3–4** for labels and ids, excludes **self-DM** from this step. **Legacy per-IM** try-order only if bulk `is:dm` fails. Optional `conversations_history` supplements **only on tool error**—**never** treat successful empty DM search as Slack-unhealthy. Step 3b does not broaden Step 2 or Step 3c
- **Person search** (Step 3d) searches **all public channels**, not just configured ones
- Person search includes full thread context from all participants to produce meaningful summaries
- If the person had no activity on the target date, report that clearly
- When running person-search standalone (without a full digest), omit the `person_activity` wrapper and write the report directly to `reports/`
- **Jira:** Batched `key in (...)` and combined child JQL reduce API calls; if the MCP `projects_filter` omits a project, watchlist keys in that project will not appear in search results—widen the filter or fall back to per-key queries
- **MCP failures:** If Slack or Jira returns nothing because the integration failed (auth, network, tool error), **do not** overwrite an existing digest with empty data—follow **Safe write rules (digests)** in Step 6 (merge-by-source, optional `digests/.backups/` before replace)

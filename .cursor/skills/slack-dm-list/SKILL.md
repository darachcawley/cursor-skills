---
name: slack-dm-list
description: >-
  Lists Slack 1:1 DMs, self-DM, and group DMs (MPDMs) the user had messages in on
  a chosen calendar date via Slack MCP, using a single date-scoped DM search with
  pagination. Use when the user asks for DM conversations, a list of DMs, direct
  messages from a date, or Slack DM activity on a specific day.
---

# Slack DM conversations by date

Produce a **deduplicated list of DM-style conversations** (1:1 IMs, self-DM, and MPDMs) where the authenticated Slack user had activity on a **single calendar date**.

## Required input

- **Date** — Accept `YYYY-MM-DD`, or relative terms (`today`, `yesterday`). Normalize to **`YYYY-MM-DD`** before calling Slack. If the user gives no date, ask once.

## MCP server

Use the Slack integration configured in Cursor (commonly `user-user-slack` or `user-slack`). Substitute the real server name for **`{slack_mcp_server}`** in every tool call.

**Before the first `conversations_search_messages` call:** Read the tool descriptor JSON for that server (e.g. `conversations_search_messages.json` under the MCP’s `tools/` folder) so `limit`, `cursor`, and parameter names match the schema.

## Workflow

### 1 — Bulk search (minimal Slack calls)

Call `conversations_search_messages` on **`{slack_mcp_server}`**:

| Parameter | Value |
|-----------|--------|
| `search_query` | `is:dm` |
| `filter_date_on` | Target date `YYYY-MM-DD` |
| `limit` | Maximum allowed by the tool schema (often `100`) |

**Paginate:** If the response includes a **`cursor`** (or equivalent), repeat the same call with `cursor` until there is no next page or the response is empty. Optional **safety cap** (e.g. 50 pages); if reached, say so in the output.

### 2 — Dedupe by conversation

Treat each distinct value of the **`Channel`** column as one conversation (one row in the final list). Aggregate is enough—do not list every message unless the user asks for detail.

- **`#mpdm-…`** — Group DM (MPDM).
- **`#U…`** (user id) — Typical form for a **1:1** DM channel in search exports.
- If the MCP uses other `Channel` shapes, still **one row per distinct `Channel`**.

### 3 — Labels (from search rows)

For each deduped `Channel`:

- **1:1:** Prefer a title like **`DM with @handle`** using peer **`UserName`** / **RealName** from any message row in that thread where the sender is **not** the requesting user (when identifiable). If only the user’s messages appear, use **`DM (peer unresolved)`** or resolve via `users_search` / `channels_list` (`im`) only for that thread—**do not** fan out to every IM preemptively.
- **MPDM:** Title like **`MPDM: …`** using the `#mpdm-…` slug or, after a single optional `channels_list` (`mpim`, paginated), the **Purpose** / **Topic** line for a friendlier name.
- **Self-DM:** If the conversation is the user’s notes-to-self channel, label **`Self (notes)`** (match against workspace-root `user_config.json` → `slack_username` and/or the self IM from `channels_list` `im` named `@{slack_username}` if you already fetched lists for links).

### 4 — Optional archive links

If workspace-root **`user_config.json`** defines **`slack_dm_domain`** (and optionally **`slack_username`** for self-DM id resolution), you may add one **Slack archive** link per row after resolving **`D…`** or **`C…`** via `channels_list` (`im` / `mpim`, paginated). If config is missing or mapping is uncertain, **omit links** and still deliver the list.

## Output format

Present to the user as a **markdown table**:

| Conversation | Kind | Notes |
|--------------|------|--------|
| … | 1:1 / Self / MPDM | e.g. message count that day (optional) |

End with **one line**: date covered, **count** of distinct conversations, and whether pagination capped the search.

## Optional config (workspace root)

[`user_config.json`](../../../user_config.example.json) fields used when present:

- **`slack_username`** — Self-DM labeling and exclusion from “with others” if the user later narrows scope.
- **`slack_dm_domain`** — Base host for optional `https://{slack_dm_domain}/archives/{id}/p…` links.

## Failure handling

- **Tool / auth error:** Report the error; do not invent conversations.
- **Empty result after successful search:** Report **no DM/MPDM activity** found for that date in search scope (valid outcome).

## Relationship to daily digest

The **[daily-digest](../daily-digest/SKILL.md)** skill **Step 3b** instructs the agent to **read this file** and follow **Workflow** steps **1 through 4** below for DM/MPDM discovery on digest date `D`, while **keeping all returned message rows** grouped by `Channel` for downstream digest steps (thread replies, summarization, JSON)—not only the markdown inventory table in **Output format**.

When run **standalone** (user asks only for a DM list), follow **Output format** and you may aggregate per conversation. This skill does **not** replace Jira, configured channels, or viewer steps from daily-digest.

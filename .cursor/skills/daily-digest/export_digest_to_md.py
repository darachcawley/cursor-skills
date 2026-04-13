#!/usr/bin/env python3
"""
Export a daily digest JSON file to Obsidian-friendly Markdown.

Called automatically at the end of daily-digest Step 7 (see SKILL.md).

Reads workspace-root user_config.json for optional obsidian_digest_path.
If unset or empty, writes to ./markdown/YYYY-MM-DD.md under this skill directory.

Usage:
  python3 export_digest_to_md.py digests/2026-04-10.json
  python3 export_digest_to_md.py --all
  python3 export_digest_to_md.py --digest ../digests/2026-04-10.json --output-dir /path/to/vault/Daily\\ Digests
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


SKILL_DIR = Path(__file__).resolve().parent


def find_workspace_root(start: Path) -> Path | None:
    for p in [start, *start.parents]:
        cfg = p / "user_config.json"
        if cfg.is_file():
            return p
    return None


def load_user_config(workspace_root: Path | None) -> dict:
    if workspace_root is None:
        return {}
    cfg = workspace_root / "user_config.json"
    try:
        with open(cfg, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def output_dir_for_export(user_config: dict) -> Path:
    raw = (user_config.get("obsidian_digest_path") or "").strip()
    if raw:
        return Path(raw).expanduser().resolve()
    return SKILL_DIR / "markdown"


def md_escape_inline(text: str) -> str:
    if not text:
        return ""
    t = text.replace("\r\n", "\n").replace("\r", "\n")
    t = re.sub(r"\n+", " ", t)
    return t


def format_action_line(action: dict, include_owner: bool) -> str:
    parts = []
    u = action.get("urgency", "")
    if u == "today":
        parts.append("**TODAY**")
    line = action.get("action", "")
    if include_owner and action.get("owner"):
        line = f"{line} ({action['owner']})"
    if parts:
        parts.append(line)
        body = " ".join(parts)
    else:
        body = line
    ch = action.get("channel", "")
    link = action.get("thread_link", "")
    if link:
        tail = f" — [{ch}]({link})" if ch else f" — [thread]({link})"
        body += tail
    elif ch:
        body += f" — {ch}"
    return body


def render_digest_md(data: dict) -> str:
    date = data.get("date", "unknown-date")
    gen = data.get("generated_at", "")
    stats = data.get("summary_stats") or {}
    exec_sum = data.get("executive_summary") or {}

    lines: list[str] = []

    # YAML front matter (Obsidian / Dataview)
    lines.append("---")
    lines.append(f"date: {date}")
    lines.append("tags:")
    lines.append("  - slack-digest")
    lines.append("  - work")
    lines.append('source: "daily-digest"')
    lines.append("---")
    lines.append("")

    lines.append(f"# Slack daily digest — {date}")
    lines.append("")
    if gen:
        lines.append(f"*Generated: {gen}*")
        lines.append("")

    lines.append("## Stats")
    lines.append("")
    lines.append(
        "| Metric | Value |"
    )
    lines.append("| --- | --- |")
    for key, label in [
        ("total_channels", "Channels"),
        ("total_threads", "Threads"),
        ("total_actions", "Actions"),
        ("actions_today", "Actions (today)"),
        ("actions_this_week", "Actions (this week)"),
        ("actions_later", "Actions (later)"),
        ("jira_mentions", "Jira @mentions"),
    ]:
        if key in stats:
            lines.append(f"| {label} | {stats[key]} |")
    lines.append("")

    if data.get("_note"):
        lines.append("> [!note] Partial / note")
        for part in str(data["_note"]).split("\n"):
            lines.append(f"> {part}")
        lines.append("")

    my_actions = exec_sum.get("my_actions") or []
    lines.append("## My actions")
    lines.append("")
    if not my_actions:
        lines.append("*(none)*")
    else:
        for i, a in enumerate(my_actions, 1):
            lines.append(f"{i}. {format_action_line(a, include_owner=False)}")
    lines.append("")

    others = exec_sum.get("others_actions") or []
    lines.append("## Others' actions")
    lines.append("")
    if not others:
        lines.append("*(none)*")
    else:
        for i, a in enumerate(others, 1):
            lines.append(f"{i}. {format_action_line(a, include_owner=True)}")
    lines.append("")

    highlights = exec_sum.get("key_highlights") or []
    lines.append("## Key highlights")
    lines.append("")
    if not highlights:
        lines.append("*(none)*")
    else:
        for h in highlights:
            lines.append(f"- {md_escape_inline(str(h))}")
    lines.append("")

    jira_mentions = data.get("jira_mentions") or []
    lines.append("## Jira mentions (digest day)")
    lines.append("")
    if not jira_mentions:
        lines.append("*(none)*")
    else:
        for m in jira_mentions:
            key = m.get("issue_key", "")
            summ = md_escape_inline(m.get("issue_summary", ""))
            st = m.get("issue_status", "")
            link = m.get("issue_link", "")
            author = m.get("comment_author", "")
            cdate = m.get("comment_date", "")
            ctext = md_escape_inline((m.get("comment_text") or "")[:500])
            title = f"[{key}]({link})" if link else key
            lines.append(f"- **{title}** ({st}) — {summ}")
            lines.append(f"  - Comment by {author} @ {cdate}")
            lines.append(f"  - {ctext}")
    lines.append("")

    pa = data.get("person_activity")
    if pa:
        lines.append("## Person activity")
        lines.append("")
        p = pa.get("person") or {}
        disp = p.get("display_name", "")
        un = p.get("slack_username", "")
        lines.append(f"*Person:* {disp} ({un})")
        if pa.get("overall_summary"):
            lines.append("")
            lines.append(md_escape_inline(pa["overall_summary"]))
        lines.append("")

    channels = data.get("channels") or []
    lines.append("## Channels")
    lines.append("")
    if not channels:
        lines.append("*(no channel data for this digest)*")
    else:
        for ch in channels:
            cname = ch.get("channel", "")
            cid = ch.get("channel_id", "")
            lines.append(f"### {cname}")
            if cid:
                lines.append(f"*Channel ID:* `{cid}`")
            lines.append("")
            threads = ch.get("threads") or []
            if not threads:
                lines.append("*(no threads)*")
                lines.append("")
                continue
            for t in threads:
                ts = t.get("thread_ts", "")
                tlink = t.get("thread_link", "")
                if tlink:
                    lines.append(f"#### [Thread {ts}]({tlink})")
                else:
                    lines.append(f"#### Thread {ts}")
                lines.append("")
                if t.get("summary"):
                    lines.append(md_escape_inline(t["summary"]))
                    lines.append("")
                parts = t.get("participants") or []
                if parts:
                    lines.append(f"*Participants:* {', '.join(parts)}")
                    lines.append("")
                actions_needed = t.get("actions_needed") or []
                if actions_needed:
                    lines.append("*Actions:*")
                    for an in actions_needed:
                        act = an.get("action", "")
                        own = an.get("owner", "")
                        urg = an.get("urgency", "")
                        uflag = f" **[{urg}]**" if urg else ""
                        lines.append(f"- {act}{uflag} ({own})")
                    lines.append("")
            lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def export_file(digest_path: Path, out_dir: Path) -> Path:
    with open(digest_path, encoding="utf-8") as f:
        data = json.load(f)
    date = data.get("date")
    if not date:
        m = re.search(r"(\d{4}-\d{2}-\d{2})", digest_path.name)
        date = m.group(1) if m else digest_path.stem
        data["date"] = date

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"{date}.md"
    md = render_digest_md(data)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(md)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Export daily digest JSON to Markdown for Obsidian.")
    parser.add_argument(
        "digest",
        nargs="?",
        help="Path to a single digest JSON (e.g. digests/2026-04-10.json)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Export every digests/*.json under this skill (excluding .backups)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        help="Override output directory (default: obsidian_digest_path from user_config or skill markdown/)",
    )
    parser.add_argument(
        "--workspace",
        type=Path,
        help="Workspace root containing user_config.json (auto-detected if omitted)",
    )
    args = parser.parse_args()

    workspace = args.workspace
    if workspace is None:
        workspace = find_workspace_root(SKILL_DIR)
    user_config = load_user_config(workspace)

    out_dir = args.output_dir
    if out_dir is None:
        out_dir = output_dir_for_export(user_config)
    else:
        out_dir = Path(out_dir).expanduser().resolve()

    digests_dir = SKILL_DIR / "digests"

    if args.all:
        paths = sorted(digests_dir.glob("*.json"))
        if not paths:
            print("No digest JSON files found.", file=sys.stderr)
            return 1
        written = []
        for p in paths:
            written.append(str(export_file(p, out_dir)))
        print(f"Exported {len(written)} file(s) to {out_dir}")
        for w in written:
            print(f"  {w}")
        return 0

    if not args.digest:
        parser.error("Provide a digest path or use --all")

    digest_path = Path(args.digest).expanduser().resolve()
    if not digest_path.is_file():
        print(f"Not found: {digest_path}", file=sys.stderr)
        return 1

    out = export_file(digest_path, out_dir)
    print(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

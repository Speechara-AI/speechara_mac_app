#!/usr/bin/env python3
import argparse
import datetime as dt
import html
import re
import sys
from pathlib import Path


RELEASE_RE = re.compile(r"^##\s+(.+?)\s+-\s+(\d{4}-\d{2}-\d{2})\s*$")
SECTION_RE = re.compile(r"^###\s+(.+?)\s*$")
BULLET_RE = re.compile(r"^-\s+(.+?)\s*$")


def parse_changelog(path):
    releases = []
    current_release = None
    current_section = None

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.rstrip()
        stripped = line.strip()

        release_match = RELEASE_RE.match(stripped)
        if release_match:
            current_release = {
                "version": release_match.group(1),
                "date": release_match.group(2),
                "sections": [],
            }
            releases.append(current_release)
            current_section = None
            continue

        section_match = SECTION_RE.match(stripped)
        if section_match and current_release is not None:
            current_section = {
                "title": section_match.group(1),
                "items": [],
            }
            current_release["sections"].append(current_section)
            continue

        bullet_match = BULLET_RE.match(stripped)
        if bullet_match and current_section is not None:
            current_section["items"].append(bullet_match.group(1))
            continue

        if stripped and current_section is not None and current_section["items"]:
            current_section["items"][-1] += " " + stripped

    return releases


def display_date(value):
    parsed = dt.date.fromisoformat(value)
    return f"{parsed.strftime('%B')} {parsed.day}, {parsed.year}"


def escape(value):
    return html.escape(value, quote=True)


def render_release_sections(release, heading_level=2):
    chunks = []
    heading_tag = f"h{heading_level}"

    if not release["sections"]:
        return "<p>No release notes were provided for this version.</p>"

    for section in release["sections"]:
        chunks.append(f"<{heading_tag}>{escape(section['title'])}</{heading_tag}>")
        if section["items"]:
            chunks.append("<ul>")
            for item in section["items"]:
                chunks.append(f"  <li>{escape(item)}</li>")
            chunks.append("</ul>")

    return "\n".join(chunks)


def page_shell(title, body):
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{escape(title)}</title>
  <style>
    :root {{
      color-scheme: light;
      --text: #142235;
      --muted: #637083;
      --border: #dce3ec;
      --panel: #ffffff;
      --page: #f6f8fb;
      --accent: #0b82ff;
    }}
    body {{
      margin: 0;
      background: var(--page);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.55;
    }}
    main {{
      width: min(760px, calc(100% - 40px));
      margin: 0 auto;
      padding: 48px 0 64px;
    }}
    article {{
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 28px;
      box-shadow: 0 18px 45px rgba(20, 34, 53, 0.08);
    }}
    .eyebrow {{
      margin: 0 0 8px;
      color: var(--muted);
      font-size: 13px;
      font-weight: 700;
      letter-spacing: 0;
      text-transform: uppercase;
    }}
    h1 {{
      margin: 0;
      font-size: 34px;
      line-height: 1.16;
      letter-spacing: 0;
    }}
    .date {{
      margin: 8px 0 28px;
      color: var(--muted);
    }}
    h2, h3 {{
      margin: 26px 0 8px;
      font-size: 18px;
      letter-spacing: 0;
    }}
    ul {{
      margin: 0;
      padding-left: 22px;
    }}
    li + li {{
      margin-top: 6px;
    }}
    a {{
      color: var(--accent);
      font-weight: 700;
      text-decoration: none;
    }}
    a:hover {{
      text-decoration: underline;
    }}
    .history-link {{
      margin-top: 28px;
      padding-top: 18px;
      border-top: 1px solid var(--border);
    }}
    .release + .release {{
      margin-top: 28px;
      padding-top: 28px;
      border-top: 1px solid var(--border);
    }}
    @media (max-width: 560px) {{
      main {{
        width: min(100% - 24px, 760px);
        padding: 24px 0 40px;
      }}
      article {{
        padding: 22px;
      }}
      h1 {{
        font-size: 28px;
      }}
    }}
  </style>
</head>
<body>
  <main>
{body}
  </main>
</body>
</html>
"""


def render_release_notes(product, platform_name, release, history_url):
    body = f"""    <article>
      <p class="eyebrow">{escape(platform_name)} update</p>
      <h1>{escape(product)} {escape(release['version'])}</h1>
      <p class="date">{escape(display_date(release['date']))}</p>
{indent(render_release_sections(release), 6)}
      <p class="history-link"><a href="{escape(history_url)}">View full {escape(platform_name)} version history</a></p>
    </article>"""
    return page_shell(f"{product} {release['version']} Release Notes", body)


def render_history(product, platform_name, releases):
    release_blocks = []

    for release in releases:
        release_blocks.append(f"""      <section class="release">
        <h2>{escape(product)} {escape(release['version'])}</h2>
        <p class="date">{escape(display_date(release['date']))}</p>
{indent(render_release_sections(release, heading_level=3), 8)}
      </section>""")

    body = f"""    <article>
      <p class="eyebrow">{escape(platform_name)}</p>
      <h1>{escape(product)} {escape(platform_name)} Version History</h1>
      <p class="date">Latest published changes for {escape(product)} on {escape(platform_name)}.</p>
{chr(10).join(release_blocks)}
    </article>"""
    return page_shell(f"{product} {platform_name} Version History", body)


def indent(value, spaces):
    prefix = " " * spaces
    return "\n".join(prefix + line if line else line for line in value.splitlines())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--changelog", required=True, type=Path)
    parser.add_argument("--product", required=True)
    parser.add_argument("--platform-name", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--release-notes-output", required=True, type=Path)
    parser.add_argument("--history-output", required=True, type=Path)
    parser.add_argument("--history-url", required=True)
    args = parser.parse_args()

    if not args.changelog.is_file():
        print(f"Changelog not found: {args.changelog}", file=sys.stderr)
        return 1

    releases = parse_changelog(args.changelog)
    release = next((item for item in releases if item["version"] == args.version), None)

    if release is None:
        print(
            f"Version {args.version} is missing from {args.changelog}. "
            "Add a '## VERSION - YYYY-MM-DD' section before publishing.",
            file=sys.stderr,
        )
        return 1

    args.release_notes_output.parent.mkdir(parents=True, exist_ok=True)
    args.history_output.parent.mkdir(parents=True, exist_ok=True)
    args.release_notes_output.write_text(
        render_release_notes(args.product, args.platform_name, release, args.history_url),
        encoding="utf-8",
    )
    args.history_output.write_text(
        render_history(args.product, args.platform_name, releases),
        encoding="utf-8",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

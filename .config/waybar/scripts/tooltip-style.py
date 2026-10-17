#!/usr/bin/env python3
"""Presentation-only JSON-lines filter. No polling, device reads, or actions.

Inputs are plain text (including text/alt); output alone is trusted Pango markup.
Codex already produces escaped markup and deliberately does not use this filter.
"""
import html
import json
from pathlib import Path
import re
import sys
import textwrap

PALETTE = Path(__file__).resolve().parents[1] / "style.css"
TITLES = {
    "spotify": "Now playing", "updates": "Software updates",
    "notification": "Notifications", "psad": "Network protection · PSAD",
    "battery": "Battery", "temperature": "Temperature",
    "hyprsunset": "Night light", "ap": "College applications",
}


def colors(path=PALETTE):
    result = dict(accent="#9a633d", muted="#6c5960", success="#4f7f5a",
                  warning="#986f2f", danger="#ae4c68", coral="#b35f3b")
    try:
        result.update(re.findall(r"@define-color\s+([\w-]+)\s+(#[\da-fA-F]{6});", path.read_text()))
    except OSError:
        pass
    return result


def escaped(value):
    # XML 1.0/Pango rejects most control characters, even when HTML-escaped.
    return html.escape(re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", str(value)), quote=True)


def span(value, palette, role="muted", bold=False):
    return f'<span foreground="{palette[role]}"' + (' weight="bold"' if bold else '') + f'>{escaped(value)}</span>'


def bounded(value, width=62, max_lines=26):
    lines = []
    for line in str(value).splitlines():
        lines.extend(textwrap.wrap(line, width, replace_whitespace=False,
                                   drop_whitespace=True) or [""])
    if len(lines) > max_lines:
        lines = lines[:max_lines - 1] + ["… additional details omitted from this preview"]
    return lines


def style(kind, data, palette=None):
    palette = palette or colors()
    result = data.copy()
    for key in ("text", "alt"):
        if key in result:
            result[key] = escaped(result[key])
    raw = str(data.get("tooltip", ""))
    css = data.get("class", "")
    css = " ".join(css) if isinstance(css, list) else str(css)
    title = TITLES[kind]
    role = "text"
    if any(s in css for s in ("error", "failed", "critical", "deadlock", "alert")):
        role = "danger"
    elif any(s in css for s in ("warning", "stale", "timeout", "available", "running")):
        role = "warning"
    elif any(s in css for s in ("good", "clean", "idle")):
        role = "success"

    if kind == "updates":
        # The upstream shell producer uses literal backslash-n in some states.
        raw = raw.replace("\\n", "\n")
    elif kind == "notification":
        state = str(data.get("alt", "none"))
        count = str(data.get("text", "0"))
        raw = f"{count} notification" + ("" if count == "1" else "s")
        raw += "\nDo not disturb: " + ("on" if "dnd" in state else "off")
        if "inhibited" in state:
            raw += "\nPopups inhibited by an application"
        if data.get("tooltip") and not re.fullmatch(r"\d+\s+Notifications?", str(data["tooltip"]), re.I):
            raw += "\n" + str(data["tooltip"])
        raw += "\n\nLeft click: notification center\nRight click: toggle do not disturb"
        role = "warning" if "dnd" in state or "inhibited" in state else "success"
    elif kind in ("battery", "temperature"):
        raw += "\n\nACPI-safe guarded status"
        if "deadlock" in css:
            raw += "\nHardware reads suspended by the safety guard"
        elif "timeout" in css:
            raw += "\nRead failed; no ACPI/EC deadlock signature detected"
        elif "unavailable" in css:
            role = "muted"
    elif kind == "ap":
        role = "danger" if "passed" in raw else "warning"
    elif kind == "hyprsunset":
        raw = raw.replace("Temp: Off", "Off · following your schedule").replace("Temp: ", "Color temperature · ")
        role = "warning" if css == "on" else "muted"
    elif kind == "psad":
        raw = raw.removeprefix("PSAD — port-scan detector\n")
        # Keep all ten existing source records, with readable compact field names.
        raw = re.sub(r"Danger level: (.*?) \| Packets: (.*?) \| Unique signatures: (.*?) \| Signature matches: (.*?) \| Local: (.*)",
                     r"Level \1 · \2 pkts · \3 sigs / \4 hits · local \5", raw)
        raw = raw.replace("Tracked sources (saved PSAD table):", "Saved source details")
        raw = re.sub(r"\nFields:.*", "", raw)
    elif kind == "capslock":
        raw = raw.removeprefix("Caps Lock\n").strip("\n")
        if "locked" in css or "\nOn" in raw:
            role = "warning"
        elif "unknown" in css:
            role = "danger"
        else:
            role = "muted"

    # Actions always remain visible at the bottom, even when details are capped.
    raw_lines = raw.splitlines()
    is_action = lambda line: bool(re.match(r"(?:Left click:|Right click:|Click:|Scroll:)", line))
    actions = [line for line in raw_lines if is_action(line)]
    body = "\n".join(line for line in raw_lines if not is_action(line)).rstrip()
    lines = bounded(body, max_lines=34 if kind == "psad" else 12 if kind == "updates" else 23)
    if actions:
        lines += [""] + actions
    output = [span(title, palette, "accent", True), ""]
    for i, line in enumerate(lines):
        if not line:
            output.append("")
        elif i == 0 and role != "text":
            output.append(span(line, palette, role, True))
        elif re.match(r"(?:Left click:|Right click:|Click:|Scroll:|ACPI-safe|Read failed;|Hardware reads|Elapsed time|Deadline ·|Start at boot:|Last data write:|Saved snapshot time:|Data age:|…)", line):
            output.append(span(line, palette))
        elif kind == "psad" and line == "Saved source details":
            output.append(span(line, palette, "accent", True))
        else:
            output.append(escaped(line))
    result["tooltip"] = "\n".join(output)
    return result


def main():
    kind = sys.argv[1]
    for line in sys.stdin:
        try:
            data = json.loads(line)
            if not isinstance(data, dict):
                raise ValueError("expected object")
            print(json.dumps(style(kind, data), ensure_ascii=False), flush=True)
        except (ValueError, TypeError):
            # Never turn a malformed stream record into executable markup.
            print(json.dumps(style(kind, {"text": "", "class": "error",
                "tooltip": "Status data unavailable · invalid producer output"})), flush=True)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3

"""Emit one attractive, deliberately static Fastfetch snapshot for EWW.

This is intentionally a one-shot command.  The launcher runs it once, writes
the result into EWW's static `plaque_data` variable, and then opens the window;
the plaque is not another live monitor.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any


def clean(value: Any, fallback: str = "Unavailable") -> str:
    if value is None:
        return fallback
    return re.sub(r"\s+", " ", str(value)).strip() or fallback


def module_map(payload: list[dict[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for module in payload:
        module_type = module.get("type")
        if module_type and "result" in module:
            result[module_type] = module["result"]
    return result


def first_item(value: Any) -> dict[str, Any]:
    if isinstance(value, list) and value and isinstance(value[0], dict):
        return value[0]
    return {}


def gib(value: Any) -> str:
    try:
        return f"{float(value) / (1024 ** 3):.2f} GB"
    except (TypeError, ValueError):
        return "Unavailable"


def short_cpu(value: Any) -> str:
    text = clean(value)
    text = text.replace("(R)", "").replace("(TM)", "")
    text = text.replace(" CPU", "")
    text = re.sub(r"\s+", " ", text).strip()
    if text.startswith("13th Gen Intel Core(TM) "):
        text = text.replace("13th Gen Intel Core(TM) ", "Intel ", 1)
    return text


def short_host(host: dict[str, Any]) -> str:
    name = clean(host.get("name"))
    # The full firmware model string is useful in raw Fastfetch, but too long
    # for the plaque. Keep the recognizable machine identity instead.
    name = name.replace(" inch", '"')
    name = re.sub(r"\s+Notebook PC$", "", name)
    return name


def format_display(value: Any) -> str:
    display = first_item(value)
    output = display.get("output", {})
    width = output.get("width")
    height = output.get("height")
    refresh = output.get("refreshRate")
    dpi = output.get("dpi") or 0
    pieces = []
    if width and height:
        pieces.append(f"{width}×{height}")
    if refresh:
        pieces.append(f"{float(refresh):.0f} Hz")
    if dpi:
        pieces.append(f"{float(dpi) / 96:.2f}× scale")
    return " · ".join(pieces) or "Unavailable"


def format_gpu(value: Any) -> str:
    gpu = first_item(value)
    vendor = clean(gpu.get("vendor"), "")
    name = clean(gpu.get("name"))
    if vendor and vendor.lower() not in name.lower():
        return f"{vendor} {name}"
    return name


def format_storage(value: Any, mountpoint: str) -> str:
    if not isinstance(value, list):
        return "Unavailable"
    for disk in value:
        if disk.get("mountpoint") == mountpoint:
            return gib(disk.get("bytes", {}).get("total"))
    return "Unavailable"


def fallback() -> dict[str, str]:
    now = datetime.now().astimezone().strftime("%d %b %Y · %H:%M")
    return {
        "identity": f"{os.environ.get('USER', 'user')}@{os.uname().nodename}",
        "captured": now,
        "os": "Arch Linux",
        "host": "System information unavailable",
        "kernel": os.uname().release,
        "wm": "Hyprland · Wayland",
        "cpu": "Unavailable",
        "gpu": "Unavailable",
        "memory": "Unavailable",
        "display": "Unavailable",
        "display_short": "Unavailable",
        "packages": "Unavailable",
        "package_count": "Unavailable",
        "shell": Path(os.environ.get("SHELL", "")).name or "Unavailable",
        "theme": "Unavailable",
        "icons": "Unavailable",
        "font": "Unavailable",
        "cursor": "Unavailable",
        "root_disk": "Unavailable",
        "home_disk": "Unavailable",
    }


def snapshot() -> dict[str, str]:
    try:
        completed = subprocess.run(
            ["fastfetch", "--format", "json", "--logo", "none"],
            check=True,
            capture_output=True,
            text=True,
            timeout=8,
        )
        modules = module_map(json.loads(completed.stdout))
    except (OSError, subprocess.SubprocessError, json.JSONDecodeError, TypeError):
        return fallback()

    title = modules.get("Title", {})
    os_info = modules.get("OS", {})
    host = modules.get("Host", {})
    kernel = modules.get("Kernel", {})
    packages = modules.get("Packages", {})
    shell = modules.get("Shell", {})
    wm = modules.get("WM", {})
    theme = modules.get("Theme", {})
    icons = modules.get("Icons", {})
    font = modules.get("Font", {})
    cursor = modules.get("Cursor", {})
    cpu = modules.get("CPU", {})
    memory = modules.get("Memory", {})

    os_name = clean(os_info.get("prettyName"), "Arch Linux")
    version = clean(os_info.get("version"), "")
    if version and version != "rolling" and version not in os_name:
        os_name = f"{os_name} · {version}"

    wm_name = clean(wm.get("prettyName"), "Hyprland")
    protocol = clean(wm.get("protocolName"), "Wayland")

    shell_name = Path(os.environ.get("SHELL", "")).name
    if not shell_name:
        shell_name = clean(shell.get("exeName"))
    shell_version = clean(shell.get("version"), "")
    shell_display = f"{shell_name} {shell_version}".strip()

    theme_display = clean(theme.get("theme2"), clean(theme.get("theme1")))
    theme_display = re.sub(r"\s*\[[^]]*\]", "", theme_display)
    theme_display = theme_display.replace(",", " /")
    icons_display = clean(icons.get("icons2"), clean(icons.get("icons1")))
    icons_display = re.sub(r"\s*\[[^]]*\]", "", icons_display)
    font_display = clean(font.get("display"))
    font_display = font_display.split(" [", 1)[0]
    cursor_theme = clean(cursor.get("theme")).replace("_cursors", "")
    cursor_display = f"{cursor_theme} · {clean(cursor.get('size'))} px"

    memory_total = memory.get("total") if isinstance(memory, dict) else None
    pacman_count = packages.get("pacman") if isinstance(packages, dict) else None
    if pacman_count is None and isinstance(packages, dict):
        pacman_count = packages.get("all")

    gpu_value = format_gpu(modules.get("GPU"))
    cpu_value = short_cpu(cpu.get("cpu")) if isinstance(cpu, dict) else "Unavailable"
    captured = datetime.now().astimezone().strftime("%d %b %Y · %H:%M")
    display_value = format_display(modules.get("Display"))

    return {
        "identity": f"{clean(title.get('userName'), os.environ.get('USER', 'user'))}@{clean(title.get('hostName'), os.uname().nodename)}",
        "captured": captured,
        "os": os_name,
        "host": short_host(host),
        "kernel": clean(kernel.get("release")),
        "wm": f"{wm_name} · {protocol}",
        "cpu": cpu_value,
        "gpu": gpu_value,
        "memory": gib(memory_total),
        "display": display_value,
        "display_short": display_value.split(" · ", 1)[0],
        "packages": f"{int(pacman_count):,} pacman" if isinstance(pacman_count, (int, float)) else "Unavailable",
        "package_count": f"{int(pacman_count):,}" if isinstance(pacman_count, (int, float)) else "Unavailable",
        "shell": shell_display,
        "theme": theme_display,
        "icons": icons_display,
        "font": font_display,
        "cursor": cursor_display,
        "root_disk": format_storage(modules.get("Disk"), "/"),
        "home_disk": format_storage(modules.get("Disk"), "/home"),
    }


print(json.dumps(snapshot(), ensure_ascii=False, separators=(",", ":")))

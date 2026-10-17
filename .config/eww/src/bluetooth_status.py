#!/usr/bin/env python3

import json
import re
import select
import shutil
import subprocess
import sys
import time


def run(*args, timeout=4):
    try:
        completed = subprocess.run(
            args,
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return completed.stdout.strip()


def property_map(output):
    properties = {}
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        properties[key.strip()] = value.strip()
    return properties


def device_icon(icon_name):
    name = icon_name.casefold()
    if "head" in name or "audio" in name:
        return "󰋋"
    if "keyboard" in name:
        return "󰌌"
    if "mouse" in name:
        return "󰍽"
    if "phone" in name:
        return "󰄜"
    if "game" in name or "joystick" in name:
        return "󰊴"
    return "󰂯"


def battery_percentage(properties):
    for key in ("Battery Percentage", "BatteryPercentage", "Percentage"):
        value = properties.get(key, "")
        if not value:
            continue
        parenthesized = re.search(r"\((\d{1,3})\)", value)
        numeric = parenthesized or re.search(r"\b(\d{1,3})\b", value)
        if numeric:
            return max(0, min(100, int(numeric.group(1))))
    return -1


def collect():
    payload = {
        "available": False,
        "powered": False,
        "discovering": False,
        "controller": "No Bluetooth adapter",
        "devices": [],
    }
    if shutil.which("bluetoothctl") is None:
        return payload

    controller_output = run("bluetoothctl", "show")
    if not controller_output:
        return payload

    controller = property_map(controller_output)
    payload["available"] = True
    payload["powered"] = controller.get("Powered") == "yes"
    payload["discovering"] = controller.get("Discovering") == "yes"
    payload["controller"] = controller.get("Alias") or controller.get("Name") or "Bluetooth"

    devices = []
    for line in run("bluetoothctl", "devices").splitlines()[:16]:
        if not line.startswith("Device "):
            continue
        parts = line.split(maxsplit=2)
        if len(parts) < 3:
            continue
        address, fallback_name = parts[1], parts[2]
        info = property_map(run("bluetoothctl", "info", address, timeout=3))
        name = info.get("Alias") or info.get("Name") or fallback_name
        paired = info.get("Paired") == "yes"
        connected = info.get("Connected") == "yes"
        trusted = info.get("Trusted") == "yes"
        battery = battery_percentage(info)
        detail = "Connected" if connected else ("Paired" if paired else "Available")
        devices.append(
            {
                "address": address,
                "name": name,
                "icon": device_icon(info.get("Icon", "")),
                "paired": paired,
                "connected": connected,
                "trusted": trusted,
                "battery": battery,
                "battery_text": f"{battery}%" if battery >= 0 else "",
                "detail": detail,
            }
        )

    devices.sort(key=lambda item: (not item["connected"], not item["paired"], item["name"].casefold()))
    payload["devices"] = devices[:10]
    payload["connected_count"] = sum(device["connected"] for device in devices)
    return payload


def emit():
    print(json.dumps(collect(), ensure_ascii=False, separators=(",", ":")), flush=True)


def watch():
    """Refresh from BlueZ D-Bus signals, with a slow safety refresh."""
    emit()
    match_rule = "type='signal',sender='org.bluez'"
    while True:
        try:
            monitor = subprocess.Popen(
                ["dbus-monitor", "--system", match_rule],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except OSError:
            time.sleep(5)
            emit()
            continue

        last_emit = time.monotonic()
        assert monitor.stdout is not None
        while monitor.poll() is None:
            readable, _, _ = select.select([monitor.stdout], [], [], 45)
            if readable:
                monitor.stdout.readline()
                time.sleep(0.2)
            if readable or time.monotonic() - last_emit >= 45:
                emit()
                last_emit = time.monotonic()
        time.sleep(1)


if __name__ == "__main__":
    if "--watch" in sys.argv:
        watch()
    else:
        emit()

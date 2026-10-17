#!/usr/bin/env python3

import base64
import json
import select
import shutil
import subprocess
import sys
import time


def run(*args, timeout=5):
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


def split_escaped(line):
    fields = []
    field = []
    escaped = False
    for character in line:
        if escaped:
            field.append(character)
            escaped = False
        elif character == "\\":
            escaped = True
        elif character == ":":
            fields.append("".join(field))
            field = []
        else:
            field.append(character)
    if escaped:
        field.append("\\")
    fields.append("".join(field))
    return fields


def signal_icon(signal):
    if signal >= 75:
        return "󰤨"
    if signal >= 50:
        return "󰤥"
    if signal >= 25:
        return "󰤢"
    return "󰤟"


def encoded(value):
    return base64.b64encode(value.encode("utf-8")).decode("ascii")


def collect():
    empty = {
        "available": False,
        "enabled": False,
        "connected": False,
        "device": "",
        "connection": "Unavailable",
        "ssid": "Not connected",
        "signal": 0,
        "ip": "No IPv4 address",
        "networks": [],
    }
    if shutil.which("nmcli") is None:
        return empty

    empty["available"] = True
    empty["enabled"] = run("nmcli", "-t", "-f", "WIFI", "general") == "enabled"

    for line in run(
        "nmcli", "-t", "-e", "yes", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"
    ).splitlines():
        fields = split_escaped(line)
        if len(fields) < 4 or fields[1] != "wifi" or fields[0].startswith("p2p-"):
            continue
        if not empty["device"]:
            empty["device"] = fields[0]
        if fields[2] == "connected":
            empty["connected"] = True
            empty["device"] = fields[0]
            empty["connection"] = fields[3] or "Connected"
            break

    if empty["device"] and empty["connected"]:
        addresses = run("nmcli", "-g", "IP4.ADDRESS", "device", "show", empty["device"])
        if addresses:
            empty["ip"] = addresses.splitlines()[0].split("/", 1)[0]

    saved_names = set()
    for line in run(
        "nmcli", "-t", "-e", "yes", "-f", "NAME,TYPE", "connection", "show"
    ).splitlines():
        fields = split_escaped(line)
        if len(fields) >= 2 and fields[1] in {"wifi", "802-11-wireless"}:
            saved_names.add(fields[0])

    networks_by_ssid = {}
    if empty["enabled"]:
        listing = run(
            "nmcli",
            "-t",
            "-e",
            "yes",
            "-f",
            "IN-USE,SIGNAL,SECURITY,SSID",
            "device",
            "wifi",
            "list",
            "--rescan",
            "no",
        )
        for line in listing.splitlines():
            fields = split_escaped(line)
            if len(fields) < 4:
                continue
            in_use, raw_signal, security, ssid = fields[0].strip(), fields[1], fields[2], fields[3]
            if not ssid:
                continue
            try:
                signal = max(0, min(100, int(raw_signal)))
            except ValueError:
                signal = 0
            active = in_use == "*"
            network = {
                "id": encoded(ssid),
                "ssid": ssid,
                "signal": signal,
                "icon": signal_icon(signal),
                "security": security if security and security != "--" else "Open network",
                "locked": bool(security and security != "--"),
                "simple_password": bool(
                    security
                    and security != "--"
                    and "WPA" in security.upper()
                    and "802.1X" not in security.upper()
                    and "ENTERPRISE" not in security.upper()
                ),
                "known": ssid in saved_names,
                "active": active,
            }
            previous = networks_by_ssid.get(ssid)
            if previous is None or active or signal > previous["signal"]:
                networks_by_ssid[ssid] = network

    networks = sorted(
        networks_by_ssid.values(),
        key=lambda item: (not item["active"], -item["signal"], item["ssid"].casefold()),
    )[:10]
    empty["networks"] = networks

    active_network = next((item for item in networks if item["active"]), None)
    if active_network:
        empty["ssid"] = active_network["ssid"]
        empty["signal"] = active_network["signal"]
    elif empty["connected"]:
        empty["ssid"] = empty["connection"]

    return empty


def emit():
    print(json.dumps(collect(), ensure_ascii=False, separators=(",", ":")), flush=True)


def watch():
    """Refresh on NetworkManager events, with a slow safety refresh."""
    emit()
    while True:
        try:
            monitor = subprocess.Popen(
                ["nmcli", "monitor"],
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
            readable, _, _ = select.select([monitor.stdout], [], [], 30)
            if readable:
                monitor.stdout.readline()
                # Coalesce the burst of lines emitted for one state transition.
                time.sleep(0.15)
            if readable or time.monotonic() - last_emit >= 30:
                emit()
                last_emit = time.monotonic()
        time.sleep(1)


if __name__ == "__main__":
    if "--watch" in sys.argv:
        watch()
    else:
        emit()

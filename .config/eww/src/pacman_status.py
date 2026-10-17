#!/usr/bin/env python3

"""Expose pacman update state to Waybar and EWW.

The normal state is derived from ``checkupdates``.  The update controller
stores a small state file while a full upgrade is running or after it fails;
that lets the indicator change immediately without launching a terminal.
"""

from __future__ import annotations

import json
import fcntl
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path


HOME = Path.home()
STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "waybar"
STATE_FILE = STATE_ROOT / "pacman-update.json"
LOCK_FILE = STATE_ROOT / "pacman-update.lock"

KERNEL_NAMES = {
    "linux",
    "linux-lts",
    "linux-zen",
    "linux-hardened",
    "linux-rt",
    "linux-rt-lts",
    "linux-mainline",
    "kernel",
    "kernel-lts",
    "kernel-zen",
    "kernel-hardened",
}
KERNEL_VARIANT = re.compile(
    r"^(?:linux|kernel)(?:-(?:lts|zen|hardened|rt(?:-lts)?|mainline|"
    r"xanmod(?:-[a-z0-9]+)*|cachyos(?:-[a-z0-9]+)*|tkg|ck|lqx))?(?:-headers)?$"
)
KERNEL_NEIGHBOR_NAMES = {
    "linux-firmware",
    "amd-ucode",
    "intel-ucode",
    "microcode",
}
DKMS_PREFIXES = ("nvidia", "virtualbox", "zfs", "v4l2loopback", "wireguard")


def read_state() -> dict:
    try:
        with STATE_FILE.open(encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def write_state(value: dict) -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_name(f".{STATE_FILE.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, STATE_FILE)


def process_alive(pid: object) -> bool:
    try:
        numeric_pid = int(pid)
    except (TypeError, ValueError):
        return False
    if numeric_pid <= 0:
        return False
    try:
        os.kill(numeric_pid, 0)
    except (OSError, ProcessLookupError):
        return False
    return True


def log_tail(path: object, limit: int = 6000) -> str:
    if not path:
        return ""
    try:
        text = Path(str(path)).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""
    return text[-limit:].strip()


def package_kind(line: str) -> tuple[str, str]:
    """Return the package name and the warning class used by the panel."""
    name = line.split(None, 1)[0].strip().lower()
    if (
        name in KERNEL_NAMES
        or KERNEL_VARIANT.fullmatch(name)
        or (name.startswith(("linux-", "kernel-")) and name.endswith("-headers"))
    ):
        return name, "kernel"

    if (
        name == "dkms"
        or "dkms" in name
        or name in KERNEL_NEIGHBOR_NAMES
        or name.endswith("-ucode")
        or any(name == prefix or name.startswith(f"{prefix}-") for prefix in DKMS_PREFIXES)
    ):
        return name, "dkms"
    return name, "normal"


def package_fields(packages: list[str]) -> dict:
    items = []
    kernel_packages = []
    dkms_packages = []
    for line in packages:
        name, kind = package_kind(line)
        items.append({"name": name, "text": line, "kind": kind})
        if kind == "kernel":
            kernel_packages.append(name)
        elif kind == "dkms":
            dkms_packages.append(name)

    return {
        "count": len(packages),
        "packages": packages,
        "package_items": items,
        "kernel_count": len(kernel_packages),
        "kernel_packages": kernel_packages,
        "kernel_notice": "Kernel update — reboot after installing" if kernel_packages else "",
        "dkms_count": len(dkms_packages),
        "dkms_packages": dkms_packages,
        "dkms_notice": "DKMS/module change — rebuild after reboot" if dkms_packages else "",
    }


def payload(status: str, packages: list[str], message: str, error: str = "", log: str = "", log_text: str = "") -> dict:
    return {
        "status": status,
        "message": message,
        "error": error,
        "log": log,
        "log_tail": log_text,
        **package_fields(packages),
    }


def checkupdates() -> tuple[list[str], str]:
    if shutil.which("checkupdates") is None:
        return [], "checkupdates is unavailable"

    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    lock = LOCK_FILE.open("a+", encoding="utf-8")
    fcntl.flock(lock.fileno(), fcntl.LOCK_EX)

    try:
        completed = subprocess.run(
            ["checkupdates"],
            check=False,
            capture_output=True,
            text=True,
            timeout=60,
        )
    except (OSError, subprocess.SubprocessError) as error:
        return [], f"Could not check for updates: {error}"
    finally:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()

    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    # checkupdates can use a non-zero status for an empty result on some
    # pacman-contrib versions.  Only treat stderr as a checking failure when
    # there was no useful package output to display.
    if not lines and completed.stderr.strip():
        return [], completed.stderr.strip().splitlines()[-1]
    return lines, ""


def idle_payload() -> dict:
    return payload("idle", [], "System is up to date")


def collect() -> dict:
    state = read_state()
    status = state.get("status", "")
    packages = [str(item) for item in state.get("packages", []) if str(item).strip()]

    if status == "running":
        started = float(state.get("started", 0) or 0)
        pid = state.get("pid")
        # The controller writes the PID just after spawning the worker.  Allow
        # that tiny handoff window, but turn a genuinely vanished worker into
        # an actionable failure instead of leaving a permanent spinner.
        if pid and not process_alive(pid) and time.time() - started > 8:
            state = {
                **state,
                "status": "failed",
                "error": "The update process stopped unexpectedly.",
                "finished": time.time(),
            }
            write_state(state)
            status = "failed"
        else:
            return payload(
                "running",
                packages,
                "Updating in the background",
                log=str(state.get("log", "")),
                log_text=log_tail(state.get("log")),
            )

    if status == "failed":
        error = str(state.get("error", "Update failed"))
        return payload(
            "failed",
            packages,
            "Full update failed — resolve manually",
            error=error,
            log=str(state.get("log", "")),
            log_text=log_tail(state.get("log")),
        )

    packages, error = checkupdates()
    if error and not packages:
        return payload("error", [], "Could not check for updates", error=error)
    if not packages:
        return idle_payload()
    return payload("available", packages, "Review packages before proceeding")


def emit() -> None:
    print(json.dumps(collect(), ensure_ascii=False, separators=(",", ":")), flush=True)


def watch() -> None:
    while True:
        emit()
        time.sleep(900)


if __name__ == "__main__":
    if "--watch" in sys.argv:
        watch()
    else:
        emit()

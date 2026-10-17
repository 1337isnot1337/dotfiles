#!/usr/bin/env python3

"""Start and manage the confirmed background pacman upgrade."""

from __future__ import annotations

import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


HOME = Path.home()
STATE_ROOT = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "waybar"
STATE_FILE = STATE_ROOT / "pacman-update.json"
LOCK_FILE = STATE_ROOT / "pacman-update.lock"


def ensure_state_root() -> None:
    STATE_ROOT.mkdir(parents=True, exist_ok=True)
    os.chmod(STATE_ROOT, 0o700)


def read_state() -> dict:
    try:
        with STATE_FILE.open(encoding="utf-8") as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError, TypeError):
        return {}


def write_state(value: dict) -> None:
    ensure_state_root()
    temporary = STATE_FILE.with_name(f".{STATE_FILE.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    os.chmod(temporary, 0o600)
    os.replace(temporary, STATE_FILE)


def remove_state() -> None:
    try:
        STATE_FILE.unlink()
    except FileNotFoundError:
        pass


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


def updates() -> tuple[list[str], str]:
    if shutil.which("checkupdates") is None:
        return [], "checkupdates is unavailable"
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

    lines = [line.strip() for line in completed.stdout.splitlines() if line.strip()]
    if not lines and completed.stderr.strip():
        return [], completed.stderr.strip().splitlines()[-1]
    return lines, ""


def lock_file():
    ensure_state_root()
    handle = LOCK_FILE.open("a+", encoding="utf-8")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    return handle


def append_log(path: Path, line: str) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(line.rstrip("\n") + "\n")


def start() -> int:
    lock = lock_file()
    try:
        state = read_state()
        if state.get("status") == "running" and process_alive(state.get("pid")):
            return 0

        package_list, error = updates()
        if error and not package_list:
            write_state(
                {
                    "status": "failed",
                    "packages": [],
                    "count": 0,
                    "error": error,
                    "log": "",
                    "started": time.time(),
                    "finished": time.time(),
                }
            )
            return 1
        if not package_list:
            remove_state()
            return 0

        timestamp = time.strftime("%Y%m%d-%H%M%S")
        log_path = STATE_ROOT / f"pacman-update-{timestamp}.log"
        log_path.touch(mode=0o600, exist_ok=False)
        append_log(log_path, f"Started full system update at {time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
        append_log(log_path, "Packages reviewed in EWW:")
        for package in package_list:
            append_log(log_path, f"  {package}")
        append_log(log_path, "")

        started = time.time()
        state = {
            "status": "running",
            "packages": package_list,
            "count": len(package_list),
            "error": "",
            "log": str(log_path),
            "started": started,
            "finished": 0,
            "pid": 0,
        }
        write_state(state)

        try:
            worker = subprocess.Popen(
                [sys.executable, str(Path(__file__).resolve()), "worker"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as error:
            write_state(
                {
                    **state,
                    "status": "failed",
                    "error": f"Could not start the update worker: {error}",
                    "finished": time.time(),
                }
            )
            append_log(log_path, f"Could not start the update worker: {error}")
            return 1

        # The worker can fail immediately (for example when sudo needs an
        # uncached password).  Do not overwrite that failure with a stale
        # running state if it has already updated the file.
        current = read_state()
        if current.get("status") == "running":
            write_state({**current, "pid": worker.pid})
        return 0
    finally:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()


def worker() -> int:
    state = read_state()
    if state.get("status") != "running":
        return 0

    log_value = state.get("log", "")
    log_path = Path(str(log_value)) if log_value else STATE_ROOT / "pacman-update.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    append_log(log_path, f"Running sudo pacman -Syu --noconfirm at {time.strftime('%Y-%m-%d %H:%M:%S %Z')}")

    sudo = shutil.which("sudo") or "/usr/bin/sudo"
    pacman = shutil.which("pacman") or "/usr/bin/pacman"
    try:
        with log_path.open("a", encoding="utf-8") as log:
            completed = subprocess.run(
                [sudo, "-n", pacman, "-Syu", "--noconfirm"],
                stdin=subprocess.DEVNULL,
                stdout=log,
                stderr=subprocess.STDOUT,
                check=False,
            )
        return_code = completed.returncode
    except (OSError, subprocess.SubprocessError) as error:
        append_log(log_path, f"Could not execute pacman: {error}")
        return_code = 1

    finished = time.time()
    if return_code == 0:
        append_log(log_path, f"Update completed successfully at {time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
        remove_state()
        return 0

    append_log(log_path, f"Update failed with exit code {return_code} at {time.strftime('%Y-%m-%d %H:%M:%S %Z')}")
    write_state(
        {
            **state,
            "status": "failed",
            "error": f"pacman exited with code {return_code}",
            "finished": finished,
            "return_code": return_code,
            "pid": 0,
        }
    )
    return return_code


def clear_failure() -> int:
    lock = lock_file()
    try:
        state = read_state()
        if state.get("status") == "running" and process_alive(state.get("pid")):
            return 1
        remove_state()
        return 0
    finally:
        fcntl.flock(lock.fileno(), fcntl.LOCK_UN)
        lock.close()


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "start"
    if command == "start":
        return start()
    if command == "worker":
        return worker()
    if command in {"clear", "clear-failure"}:
        return clear_failure()
    print(f"usage: {sys.argv[0]} {{start|clear-failure|worker}}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

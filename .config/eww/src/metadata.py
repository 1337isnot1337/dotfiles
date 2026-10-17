#!/usr/bin/env python3

"""Emit one complete, live media state object for the EWW dashboard.

Playerctl signals handle track/player changes and a single lightweight timer
advances position, lyrics, and system-volume state. This replaces the old
collection of independent EWW polls.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import unquote, urlparse

import gi
import numpy as np
import requests
from PIL import Image

gi.require_version("Playerctl", "2.0")
from gi.repository import GLib, Playerctl


CACHE_DIR = Path.home() / ".config/eww/spotify_cache"
ART_PATH = CACHE_DIR / "album_art.png"
MODIFIED_ART_PATH = CACHE_DIR / "album_art_modified.png"
DEFAULT_ART_PATH = CACHE_DIR / "default.png"
LYRICS_ENDPOINT = "http://localhost:3000/v1/lyrics/{}"
DEFAULT_ACCENT = "#ebcb8b"
DEFAULT_DARK = "#17171b"

manager = Playerctl.PlayerManager()
managed_players: dict[str, Playerctl.Player] = {}
cached_player_name = ""
cached_track_key = ""
cached_metadata: dict[str, object] = {}
cached_lyrics: list[dict[str, object]] = []
cached_colors: dict[str, str] = {}


def emit(payload: dict[str, object]) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)


def first_value(value: object, fallback: str = "") -> str:
    if isinstance(value, (list, tuple)):
        return str(value[0]) if value else fallback
    if value is None:
        return fallback
    return str(value)


def run(*args: str, timeout: float = 2.0) -> str:
    try:
        completed = subprocess.run(
            args, check=False, capture_output=True, text=True, timeout=timeout
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return completed.stdout.strip()


def save_image(url: str) -> bool:
    if not url:
        return False
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    temporary_path: Path | None = None
    try:
        if url.startswith("file://"):
            data = Path(unquote(urlparse(url).path)).read_bytes()
        else:
            response = requests.get(url, timeout=5)
            response.raise_for_status()
            data = response.content
        with tempfile.NamedTemporaryFile(
            mode="wb", dir=CACHE_DIR, prefix="album_art.", delete=False
        ) as temporary:
            temporary.write(data)
            temporary_path = Path(temporary.name)
        temporary_path.replace(ART_PATH)
        return True
    except (OSError, requests.RequestException, ValueError):
        return False
    finally:
        if temporary_path is not None and temporary_path.exists():
            temporary_path.unlink(missing_ok=True)


def palette() -> dict[str, str]:
    try:
        with Image.open(ART_PATH) as source:
            pixels = np.asarray(source.convert("RGB").resize((64, 64))).reshape(-1, 3)
        candidates = [
            tuple(map(int, pixel))
            for pixel in pixels
            if 45 < sum(map(int, pixel)) < 690
            and max(map(int, pixel)) - min(map(int, pixel)) > 24
        ]
        if not candidates:
            candidates = [tuple(map(int, pixel)) for pixel in pixels]
        counts: dict[tuple[int, int, int], int] = {}
        for color in candidates:
            quantized = tuple((channel // 24) * 24 for channel in color)
            counts[quantized] = counts.get(quantized, 0) + 1
        dominant = max(counts, key=counts.get)
        luminance = sum(dominant) / (255 * 3)
        white_mix = 0.52 if luminance < 0.42 else 0.28
        accent = tuple(
            round(channel * (1 - white_mix) + 255 * white_mix)
            for channel in dominant
        )
        darkest = min(
            (tuple(map(int, pixel)) for pixel in pixels), key=lambda color: sum(color)
        )
        accent_luminance = sum(accent) / (255 * 3)
        return {
            "tint": "#{:02x}{:02x}{:02x}".format(*accent),
            "tint_soft": "rgba({},{},{},0.14)".format(*accent),
            "dark": "#{:02x}{:02x}{:02x}".format(*darkest),
            "accent_text": DEFAULT_DARK if accent_luminance > 0.55 else "#f2edf0",
        }
    except (OSError, ValueError, TypeError):
        return {
            "tint": DEFAULT_ACCENT,
            "tint_soft": "rgba(235,203,139,0.14)",
            "dark": DEFAULT_DARK,
            "accent_text": DEFAULT_DARK,
        }


def status_of(player: Playerctl.Player | None) -> str:
    if player is None:
        return "Stopped"
    try:
        value = str(player.props.status)
    except (AttributeError, TypeError):
        value = "Stopped"
    for known in ("Playing", "Paused", "Stopped"):
        if known.casefold() in value.casefold():
            return known
    return value.title() or "Stopped"


def selected_player() -> Playerctl.Player | None:
    players = list(managed_players.values())
    for desired in ("Playing", "Paused"):
        for player in players:
            if status_of(player) == desired:
                return player
    return players[0] if players else None


def player_name(player: Playerctl.Player | None) -> str:
    if player is None:
        return ""
    try:
        return str(player.props.player_name)
    except AttributeError:
        return "unknown"


def player_metadata(player: Playerctl.Player | None) -> dict[str, object]:
    if player is None:
        return {}
    try:
        return dict(player.props.metadata or {})
    except (AttributeError, TypeError, ValueError):
        return {}


def source_label(name: str, media_url: str = "") -> str:
    lowered = name.casefold()

    # Browser MPRIS players are all exposed as Firefox/LibreWolf regardless of
    # the site producing the audio. Prefer the page origin when it is present
    # so Spotify-in-a-browser is not mislabeled as YouTube.
    try:
        hostname = (urlparse(media_url).hostname or "").casefold().rstrip(".")
    except ValueError:
        hostname = ""

    source_domains = (
        ("spotify.com", "Spotify"),
        ("youtube.com", "YouTube"),
        ("youtu.be", "YouTube"),
        ("youtube-nocookie.com", "YouTube"),
        ("soundcloud.com", "SoundCloud"),
        ("bandcamp.com", "Bandcamp"),
        ("music.apple.com", "Apple Music"),
        ("tidal.com", "TIDAL"),
        ("deezer.com", "Deezer"),
        ("music.amazon.com", "Amazon Music"),
        ("pandora.com", "Pandora"),
        ("mixcloud.com", "Mixcloud"),
        ("twitch.tv", "Twitch"),
        ("vimeo.com", "Vimeo"),
    )
    for domain, label in source_domains:
        if hostname == domain or hostname.endswith(f".{domain}"):
            return label

    if media_url.casefold().startswith("spotify:") or "spotify" in lowered:
        return "Spotify"
    if "firefox" in lowered or "librewolf" in lowered:
        return "Web"
    return name.replace(".instance", "").replace("_", " ").title() or "Media"


def spotify_track_id(url: str) -> str:
    candidate = url.removeprefix("spotify:track:").split("?", 1)[0].rsplit("/", 1)[-1]
    return candidate if re.fullmatch(r"[A-Za-z0-9]{22}", candidate) else ""


def load_lyrics(name: str, url: str) -> list[dict[str, object]]:
    if "spotify" not in name.casefold():
        return []
    track_id = spotify_track_id(url)
    if not track_id:
        return []
    try:
        response = requests.get(LYRICS_ENDPOINT.format(track_id), timeout=2)
        response.raise_for_status()
        lines = response.json().get("lyrics", {}).get("lines", [])
    except (requests.RequestException, ValueError, AttributeError):
        return []
    normalized = []
    for line in lines:
        try:
            normalized.append(
                {
                    "start": int(line.get("startTimeMs", 0)),
                    "words": str(line.get("words", "")).strip(),
                }
            )
        except (TypeError, ValueError, AttributeError):
            continue
    return sorted(
        (line for line in normalized if line["words"]), key=lambda line: line["start"]
    )


def refresh_track_cache(player: Playerctl.Player | None) -> None:
    global cached_player_name, cached_track_key, cached_metadata, cached_lyrics, cached_colors
    name = player_name(player)
    metadata = player_metadata(player)
    title = first_value(metadata.get("xesam:title"))
    artist = first_value(metadata.get("xesam:artist"))
    url = first_value(metadata.get("xesam:url"))
    art_url = first_value(metadata.get("mpris:artUrl"))
    track_key = "\x1f".join((name, url, title, artist, art_url))
    if track_key == cached_track_key and name == cached_player_name:
        return
    cached_player_name = name
    cached_track_key = track_key
    cached_metadata = metadata
    cached_lyrics = load_lyrics(name, url)
    if not save_image(art_url) and not ART_PATH.exists() and DEFAULT_ART_PATH.exists():
        shutil.copyfile(DEFAULT_ART_PATH, ART_PATH)
    source = ART_PATH if ART_PATH.exists() else DEFAULT_ART_PATH
    if source.exists():
        try:
            shutil.copyfile(source, MODIFIED_ART_PATH)
        except OSError:
            pass
    cached_colors = palette() if player is not None else {}


def format_time(microseconds: int) -> str:
    total_seconds = max(0, microseconds // 1_000_000)
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours}:{minutes:02d}:{seconds:02d}" if hours else f"{minutes:02d}:{seconds:02d}"


def playback_position(player: Playerctl.Player | None) -> int:
    if player is None:
        return 0
    try:
        return max(0, int(player.get_position()))
    except (AttributeError, GLib.Error, TypeError, ValueError):
        return 0


def bool_property(player: Playerctl.Player | None, property_name: str) -> bool:
    if player is None:
        return False
    try:
        return bool(getattr(player.props, property_name))
    except (AttributeError, TypeError):
        return False


def loop_property(player: Playerctl.Player | None) -> str:
    if player is None:
        return "None"
    try:
        value = str(player.props.loop_status)
    except (AttributeError, TypeError):
        return "None"
    for known in ("None", "Track", "Playlist"):
        if known.casefold() in value.casefold():
            return known
    return "None"


def system_volume() -> tuple[int, bool]:
    output = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@", timeout=1)
    match = re.search(r"Volume:\s*([0-9.]+)", output)
    volume = round(float(match.group(1)) * 100) if match else 0
    return max(0, min(volume, 150)), "[MUTED]" in output


def lyric_context(position_us: int) -> tuple[str, str, str]:
    if not cached_lyrics:
        return "", "", ""
    position_ms = position_us // 1000
    active_index = 0
    for index, line in enumerate(cached_lyrics):
        if int(line["start"]) - 1000 <= position_ms:
            active_index = index
        else:
            break
    previous = str(cached_lyrics[active_index - 1]["words"]) if active_index > 0 else ""
    current = str(cached_lyrics[active_index]["words"])
    following = (
        str(cached_lyrics[active_index + 1]["words"])
        if active_index + 1 < len(cached_lyrics)
        else ""
    )
    return previous, current, following


def current_state() -> dict[str, object]:
    player = selected_player()
    refresh_track_cache(player)
    name = player_name(player)
    metadata = cached_metadata if player is not None else {}
    position = playback_position(player)
    try:
        length = int(metadata.get("mpris:length", 0) or 0)
    except (TypeError, ValueError):
        length = 0
    progress = min(100.0, max(0.0, position / length * 100)) if length else 0.0
    volume, muted = system_volume()
    previous, current, following = lyric_context(position)
    colors = cached_colors or {
        "tint": DEFAULT_ACCENT,
        "tint_soft": "rgba(235,203,139,0.14)",
        "dark": DEFAULT_DARK,
        "accent_text": DEFAULT_DARK,
    }
    return {
        "available": player is not None,
        "status": status_of(player),
        "title": first_value(metadata.get("xesam:title"), "Nothing playing"),
        "artist": first_value(metadata.get("xesam:artist"), "Choose something to listen to"),
        "album": first_value(metadata.get("xesam:album")),
        "current_player": name or "audio-player",
        "source": source_label(name, first_value(metadata.get("xesam:url"))),
        "url": str(ART_PATH if ART_PATH.exists() else DEFAULT_ART_PATH),
        **colors,
        "shuffle": bool_property(player, "shuffle"),
        "loop": loop_property(player),
        "position": format_time(position),
        "length": format_time(length),
        "progress": round(progress, 2),
        "volume": volume,
        "muted": muted,
        "lyrics_available": bool(cached_lyrics),
        "lyric_previous": previous,
        "lyric_current": current,
        "lyric_next": following,
    }


def emit_current(*_args: object) -> bool:
    emit(current_state())
    return True


def init_player(name: str) -> None:
    if not name or name in managed_players:
        return
    try:
        player = Playerctl.Player.new_from_name(name)
        for signal in (
            "metadata",
            "playback-status::playing",
            "playback-status::paused",
            "playback-status::stopped",
        ):
            player.connect(signal, emit_current)
        manager.manage_player(player)
        managed_players[name] = player
    except (GLib.Error, TypeError, ValueError):
        return


def on_name_appeared(_manager: Playerctl.PlayerManager, name: str) -> None:
    init_player(name)
    emit_current()


def on_name_vanished(_manager: Playerctl.PlayerManager, name: str) -> None:
    managed_players.pop(name, None)
    global cached_track_key
    cached_track_key = ""
    emit_current()


manager.connect("name-appeared", on_name_appeared)
manager.connect("name-vanished", on_name_vanished)
for existing_name in list(manager.props.player_names):
    init_player(existing_name)

emit_current()
GLib.timeout_add(500, emit_current)
GLib.MainLoop().run()

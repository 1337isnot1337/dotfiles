# Arch and Hyprland dotfiles

A curated copy of a working Arch Linux desktop, with personal configuration and runtime state removed. Paths mirror the home directory. Review files before installing them; this repository is not an unattended installer.

## Included

- Hyprland 0.56 Lua configuration, touchpad gestures and keyboard shortcuts.
- Waybar, Eww panels, SwayNC and day/night styling.
- Fish, a Starship gradient prompt, Kitty and Rofi themes.
- Clipboard metadata, media controls, brightness/volume helpers and selected user services.
- An abstract wallpaper already published in this repository.

`Super+M` opens the session menu. Logout uses Hyprland's Lua dispatcher. The invisible looping border-angle animation is disabled. Monitor names, scaling, preferred applications and night-mode times are examples to adapt to the target machine.

## Installation notes

Back up existing configuration, then copy only the files you want. Keep scripts in `.local/bin` and the selected configuration scripts executable. Run `systemctl --user daemon-reload` after installing user units. Hyprland starts the relevant desktop services on login; installing these files does not enable automatic idle suspension.

The configuration expects Arch packages for Hyprland, Waybar, Eww, SwayNC, Hyprpaper, Hyprsunset, wlogout, Kitty, Fish, Starship, Rofi/Wofi, wl-clipboard, cliphist, PipeWire/WirePlumber, playerctl, brightnessctl, jq and Python. Individual shortcuts also refer to optional applications such as Firefox, LibreWolf, Dolphin, Spotify and Flameshot. Check each shortcut and the session menu before use.

The public Waybar supervisor launches the packaged `/usr/bin/waybar`. Clipboard helpers use `/usr/bin/cliphist`; `CLIPHIST_REAL` can select another compatible executable. Optional volume-feedback sound files and browser theme overrides are local assets and are not included. The hardware-status guard bounds reads during an ACPI stall; it does not repair firmware.

The Eww music fallback uses the included abstract artwork. Album art, Wi-Fi scan results and other runtime data are generated locally. Private school/account widgets are omitted.

## Privacy

This copy omits browser profiles, cookies, credentials, SSH destinations, account aliases, personal dates, application tracking, device UUIDs, clipboard contents, generated caches and Fish universal-variable state. Home-directory paths use environment variables or systemd's `%h` specifier. Do not copy an entire `.config` directory or live application database into this repository.

Use a public Git identity and a GitHub `noreply` address for commits. Review both new files and diffs before publishing; ignore rules do not inspect file contents or remove earlier history.

## Arch maintenance

`system/pacman-contrib` is an example for `/etc/conf.d/pacman-contrib` that retains three cached package versions. The packaged `paccache.timer` schedules weekly cleanup.

The packaged `fstrim.timer` schedules weekly SSD trimming. Encrypted systems need discard support through every storage layer. Review the privacy tradeoff and boot configuration separately; machine-specific boot entries, encryption headers and keys are intentionally excluded here.

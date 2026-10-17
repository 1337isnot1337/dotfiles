-- Hyprland Lua configuration (0.55+).
-- Migrated from the legacy hyprland.conf; keep that file for rollback if needed.

------------------
---- MONITORS ----
------------------

-- Laptop: retain its native mode and existing UI scale.
hl.monitor({
    output = "eDP-1",
    mode = "preferred",
    position = "0x0",
    scale = 1.25,
})

-- Other displays: mirror the laptop using their own preferred mode.
-- Hyprland 0.56.2 preserves aspect ratio, adding black bars as needed.
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
    mirror = "eDP-1",
})

-- Keep SwayNC popup input stable while a notification is being dismissed.
-- SwayNC owns the card animation; disabling Hyprland's separate layer
-- animation prevents the button release from being retargeted underneath it.
hl.layer_rule({
    name = "swaync-notification-no-anim",
    match = { namespace = "^swaync-notification-window$" },
    no_anim = true,
})

---------------------
---- MY PROGRAMS ----
---------------------

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "dolphin"
local menu = "wofi --show drun"

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Start clipboard watchers only after importing this compositor's environment.
    -- Keep these commands in one shell so asynchronous exec calls cannot race.
    hl.exec_cmd("sh -c 'systemctl --user import-environment DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR && dbus-update-activation-environment --systemd DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_RUNTIME_DIR && systemctl --user restart xdg-desktop-portal-hyprland.service || true; systemctl --user reset-failed cliphist-text.service cliphist-image.service && systemctl --user restart cliphist-text.service cliphist-image.service; systemctl --user start swaync.service || true; for _ in $(/usr/bin/seq 1 40); do if /usr/bin/swaync-client --get-dnd >/dev/null 2>&1; then /usr/bin/swaync-client --dnd-off >/dev/null 2>&1; break; fi; /usr/bin/sleep 0.25; done; systemctl --user restart low-battery-notify.service || true; systemctl --user restart hyprsunset-schedule.service; systemctl --user restart eww-desktop-plaque.service || true'")
    hl.exec_cmd("env QT_QPA_PLATFORM=wayland flameshot")
    hl.exec_cmd(terminal)
    hl.exec_cmd("systemctl --user start waybar-recovery.service")
    hl.exec_cmd("systemctl --user start hyprpaper.service")
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("$HOME/.local/bin/volume-feedback-check")
    hl.exec_cmd("$HOME/.local/bin/workspace-indicator")
end)

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0,
        col = {
            active_border = "rgba(696969ff)",
            inactive_border = "rgba(393939ff)",
        },
        -- Do not let tiled-client border hitboxes extend into Waybar's
        -- exclusive zone; that steals pointer motion from layer-shell
        -- widgets on workspaces with tiled windows.
        resize_on_border = false,
        allow_tearing = false,
        extend_border_grab_area = 10,
        layout = "dwindle",
    },

    decoration = {
        active_opacity = 1.0,
        inactive_opacity = 0.95,
        shadow = {
            enabled = false,
            range = 4,
            render_power = 3,
            color = "rgba(1a1a1aee)",
        },
        blur = {
            enabled = true,
            size = 3,
            passes = 1,
            vibrancy = 0.1696,
        },
    },

    animations = {
        enabled = true,
        workspace_wraparound = true,
    },

    dwindle = {
        preserve_split = true,
    },

    master = {
        new_status = "master",
    },

    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        enable_swallow = false,
        swallow_regex = "^(kitty)$",
        middle_click_paste = false,
    },

    gestures = {
        workspace_swipe_create_new = true,
        workspace_swipe_distance = 170,
        workspace_swipe_direction_lock = false,
        workspace_swipe_forever = true,
        workspace_swipe_invert = true,
    },

    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        kb_rules = "",
        follow_mouse = 1,
        mouse_refocus = true,
        sensitivity = 0.7,
        touchpad = {
            natural_scroll = true,
            clickfinger_behavior = true,
            tap_to_click = true,
            tap_and_drag = true,
            disable_while_typing = true,
        },
    },

    xwayland = {
        force_zero_scaling = true,
    },

    debug = {
        disable_logs = false,
        enable_stdout_logs = false,
    },
})

----------------
---- ANIMATION -
----------------

hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })

hl.animation({
    leaf = "windows",
    enabled = true,
    speed = 6,
    bezier = "wind",
    style = "slide",
})
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 6,
    bezier = "winIn",
    style = "slide",
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 5,
    bezier = "winOut",
    style = "slide",
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 5,
    bezier = "wind",
    style = "slide",
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 1,
    bezier = "liner",
})
-- Borders are hidden; avoid continuously rendering an invisible angle animation.
hl.animation({ leaf = "borderangle", enabled = false })
hl.animation({
    leaf = "fade",
    enabled = true,
    speed = 10,
    bezier = "default",
})
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 5,
    bezier = "wind",
})

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

---------------------
---- KEYBINDINGS ----
---------------------

hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
-- Always-available EWW escape hatch. Applet click-away handling is helpful,
-- but a compositor-level binding must remain usable if an overlay or its own
-- event handler ever becomes unresponsive.
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("$HOME/.config/eww/src/close_panel.sh all"))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("wlogout -c 5 -r 5 -p layer-shell"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("firefox"))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))

hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("librewolf"))
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("discord --enable-features=WaylandWindowDecorations --ozone-platform-hint=auto"))
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd("~/.local/bin/spotify-wayland"))
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("$HOME/.local/bin/waybar-toggle"))
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("codium"))
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("$HOME/.local/bin/cliphist-picker"))
-- Capture through the running Flameshot daemon.
hl.bind(mainMod .. " + Z", hl.dsp.exec_cmd("/usr/bin/dbus-send --session --type=method_call --dest=org.flameshot.Flameshot / org.flameshot.Flameshot.captureScreen"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("playerctl -p spotify play-pause"))
hl.bind(mainMod .. " + SHIFT + P", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd("meru"))
hl.bind(mainMod .. " + K", hl.dsp.exec_cmd("kate"))
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("audacity"))
hl.bind(mainMod .. " + X", hl.dsp.exec_cmd("blueman-manager"))
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("kitty --hold sh -c \"kitty fish -c 'pac && yay -Syyu; kill $PPID'\""))
hl.bind(mainMod .. " + U", hl.dsp.exec_cmd("grimshot save area"))
hl.bind(mainMod .. " + H", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))

hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ workspace = "+1" }))
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ workspace = "-1" }))

hl.bind(mainMod .. " + left", hl.dsp.focus({ workspace = "e-1" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ workspace = "e+1" }))

hl.bind("Caps_Lock", hl.dsp.exec_cmd("/etc/script.sh"), { release = true })

for i = 1, 10 do
    local key = i % 10
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

hl.bind(mainMod .. " + XF86MonBrightnessUp", hl.dsp.exec_cmd("$HOME/.local/bin/brightness-step up"))
hl.bind(mainMod .. " + XF86MonBrightnessDown", hl.dsp.exec_cmd("$HOME/.local/bin/brightness-step down"))
hl.bind(mainMod .. " + XF86AudioRaiseVolume", hl.dsp.exec_cmd("$HOME/.local/bin/volume-step up 2"))
hl.bind(mainMod .. " + XF86AudioLowerVolume", hl.dsp.exec_cmd("$HOME/.local/bin/volume-step down 2"))

hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("$HOME/.local/bin/volume-step up 5"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("$HOME/.local/bin/volume-step down 5"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("$HOME/.local/bin/brightness-step up"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("$HOME/.local/bin/brightness-step down"), { locked = true, repeating = true })

hl.bind(mainMod .. " + backslash", hl.dsp.exec_cmd("busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateTemperature n -500"))
hl.bind(mainMod .. " + bracketright", hl.dsp.exec_cmd("busctl --user -- call rs.wl-gammarelay / rs.wl.gammarelay UpdateTemperature n +500"))

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- Keep Flameshot's capture overlay aligned with the screen instead of tiled.
hl.window_rule({
    name = "flameshot-capture",
    match = { class = "^flameshot$", title = "^flameshot$" },
    float = true,
    no_anim = true,
    decorate = false,
    no_blur = true,
    no_shadow = true,
    border_size = 0,
    rounding = 0,
    move = { 0, 0 },
})

hl.window_rule({
    name = "suppress-maximize-events",
    match = {
        class = ".*",
    },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "fix-xwayland-drags",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

-- Keep Codex's explicitly tagged host-side fallback windows away from the
-- user's working desktop. Workspace 99 is containment only; it does not make
-- host pointer, keyboard, or screen-capture automation safe.
hl.window_rule({
    name = "codex-automation-fallback",
    match = { class = "^codex-automation$" },
    workspace = "99 silent",
    no_focus = true,
})

hl.window_rule({
    name = "codex-automation-browser-fallback",
    match = { class = "^codex-automation-browser$" },
    workspace = "99 silent",
    no_focus = true,
})

hl.window_rule({
    name = "codex-automation-terminal-fallback",
    match = { class = "^codex-automation-terminal$" },
    workspace = "99 silent",
    no_focus = true,
})

-- A nested Hyprland session is hosted by an aquamarine Wayland client on the
-- host. Keep that host surface off the user's working workspace and unfocused.
hl.window_rule({
    name = "codex-nested-compositor-host-surface",
    match = { class = "^aquamarine$" },
    workspace = "99 silent",
    no_focus = true,
})

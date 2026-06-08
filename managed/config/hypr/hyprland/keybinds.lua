return function(ctx)
    local paths = ctx.paths
    local programs = ctx.programs
    local launch = programs.launch
    local bind = hl.bind
    local dsp = hl.dsp
    local exec = dsp.exec_cmd
    local mod = "SUPER"

    bind(mod .. " + Q", exec(programs.terminal), {
        desc = "Launch terminal"
    })
    bind(mod .. " + A", exec(programs.browser), {
        desc = "Launch browser"
    })
    bind(mod .. " + E", exec(programs.file_manager), {
        desc = "Launch file manager"
    })
    bind(mod .. " + C", dsp.window.close(), {
        desc = "Close focused window"
    })
    bind(mod .. " + V", dsp.window.float({
        action = "toggle"
    }), {
        desc = "Toggle floating"
    })
    bind(mod .. " + P", dsp.window.pseudo(), {
        desc = "Toggle pseudotiling"
    })
    bind(mod .. " + J", dsp.layout("togglesplit"), {
        desc = "Toggle dwindle split"
    })

    for _, direction in ipairs({ "left", "right", "up", "down" }) do
        bind(mod .. " + " .. direction, dsp.focus({
            direction = direction
        }), {
            desc = "Focus " .. direction
        })
    end

    for workspace = 1, 10 do
        local key = workspace % 10
        bind(mod .. " + " .. key, dsp.focus({
            workspace = workspace
        }), {
            desc = "Switch to workspace " .. workspace
        })
        bind(mod .. " + SHIFT + " .. key, dsp.window.move({
            workspace = workspace
        }), {
            desc = "Move focused window to workspace " .. workspace
        })
    end

    bind(mod .. " + S", dsp.workspace.toggle_special("magic"), {
        desc = "Toggle scratchpad workspace"
    })
    bind(mod .. " + CTRL + S", dsp.window.move({
        workspace = "special:magic"
    }), {
        desc = "Send window to scratchpad workspace"
    })

    bind(mod .. " + SHIFT + W", dsp.workspace.toggle_special("whatsapp"), {
        desc = "Toggle whatsapp workspace"
    })
    bind(mod .. " + SHIFT + S", dsp.window.move({
        workspace = "special:magic"
    }), {
        desc = "Send window to scratchpad workspace"
    })
    bind("ALT + W", dsp.workspace.toggle_special("whatsapp"), {
        desc = "Toggle whatsapp workspace"
    })
    bind("ALT + S", dsp.workspace.toggle_special("spotify"), {
        desc = "Toggle Spotify workspace"
    })
    bind("ALT + P", exec(paths.scripts .. "/perf.sh"), {
        desc = "Start performance mode"
    })

    bind(mod .. " + mouse_down", dsp.focus({
        workspace = "e+1"
    }))
    bind(mod .. " + mouse_up", dsp.focus({
        workspace = "e-1"
    }))
    bind(mod .. " + mouse:272", dsp.window.drag(), {
        mouse = true
    })
    bind(mod .. " + mouse:273", dsp.window.resize(), {
        mouse = true
    })

    for _, app in ipairs({
        { "ALT + SPACE",             "vicinae toggle",                                                                    "Open launcher" },
        { "ALT + TAB",               "vicinae vicinae://launch/wm/switch-windows",                                        "Open window switcher" },
        { "INSERT",                  "vicinae vicinae://launch/clipboard/history",                                        "Open clipboard manager" },
        { mod .. " + XF86AudioPlay", "vicinae vicinae://launch/@mattisssa/store.raycast.spotify-player/nowPlaying",       "Open media controller" },
        { mod .. " + F1",            "vicinae vicinae://launch/@sovereign/store.vicinae.hypr-keybinds/hyprland-keybinds", "Open keybind help" },
    }) do
        bind(app[1], exec(app[2]), { desc = app[3] })
    end

    bind(mod .. " + M", exec("killall rofi || " .. launch("$XDG_CONFIG_HOME/rofi/bin/calc")), {
        desc = "Launch calculator"
    })
    bind("Print", exec(launch(paths.scripts .. "/screenshot.sh")), {
        desc = "Take screenshot"
    })
    bind("XF86RFKill", exec(launch(paths.scripts .. "/rofi-wireless.sh")), {
        desc = "Open wireless menu"
    })

    bind(mod .. " + L", exec(paths.scripts .. "/lock.sh start"), {
        desc = "Lock session"
    })
    bind(mod .. " + R", exec([[hyprctl reload; hyprctl dispatch 'hl.dsp.dpms({ action = "enable" })']]), {
        locked = true,
        desc = "Reloads Hyprland and wakes display"
    })

    for _, audio in ipairs({
        { "XF86AudioRaiseVolume", "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 1%+", "Volume up" },
        { "XF86AudioLowerVolume", "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 1%-", "Volume down" },
    }) do
        bind(audio[1], exec(audio[2]), {
            locked = true,
            repeating = true,
            desc = audio[3],
        })
    end

    bind("XF86AudioMute", exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), {
        locked = true,
        release = true,
        desc = "Toggle mute"
    })

    for _, media in ipairs({
        { "XF86AudioNext", "playerctl next",       "Next media track" },
        { "XF86AudioPlay", "playerctl play-pause", "Play or pause media" },
        { "XF86AudioPrev", "playerctl previous",   "Previous media track" },
    }) do
        bind(media[1], exec(media[2]), { locked = true, desc = media[3] })
    end

    for _, brightness in ipairs({
        { "XF86MonBrightnessUp",   "brillo -u 100000 -q -A 1", "Increase brightness" },
        { "XF86MonBrightnessDown", "brillo -u 100000 -q -U 1", "Decrease brightness" },
    }) do
        bind(brightness[1], exec(brightness[2]), {
            locked = true,
            repeating = true,
            desc = brightness[3],
        })
    end
end

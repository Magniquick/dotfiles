return function(ctx)
    local theme = ctx.theme

    -- Window and layer rules.

    local function clamp(value, low, high)
        return math.min(math.max(value, low), high)
    end

    local function is_popup(window)
        return window.class == "" and window.title == ""
    end

    local function cursor_anchor(cursor_pos, monitor_pos, monitor_size, window_size)
        local cursor_on_monitor = cursor_pos - monitor_pos
        local before_cursor = cursor_on_monitor <= monitor_size * 0.5
        local offset = before_cursor and 0 or window_size
        local max_position = math.max(0, monitor_size - window_size)
        local anchored = clamp(cursor_on_monitor - offset, 0, max_position)

        return monitor_pos + anchored
    end

    -- Automatically place popup windows on the cursor side that has room, then
    -- clamp them inside the active monitor.
    local function move_popup_to_cursor(window)
        if not is_popup(window) then
            return
        end

        local cursor = hl.get_cursor_pos()
        local monitor = window.monitor or hl.get_monitor_at_cursor()
        local window_w = window.size[1]
        local window_h = window.size[2]

        if cursor == nil or monitor == nil or window_w == nil or window_h == nil then
            return
        end

        local x = cursor_anchor(cursor.x, monitor.x, monitor.width, window_w)
        local y = cursor_anchor(cursor.y, monitor.y, monitor.height, window_h)

        hl.dispatch(hl.dsp.window.move({
            x = math.floor(x),
            y = math.floor(y),
            window = window,
        }))
    end

    local window_rules = {
        -- Make special workspaces more recognisable.
        {
            name = "special_workspace_border",
            match = { workspace = "s[1]" },
            border_size = 2,
            border_color = theme.red,
        },
        {
            name = "hyprland_share_picker",
            match = { class = "^(hyprland-share-picker)$" },
            float = true,
        },
        {
            name = "sushi_preview",
            match = { class = "^(org.gnome.NautilusPreviewer)$" },
            float = true,
        },
        {
            name = "pin_ripdrag",
            match = { class = "^(it.catboy.ripdrag)$" },
            pin = true,
        },
        {
            name = "set_waybar_controls",
            match = { class = "(impala|bluetui)" },
            tag = "+waybar-control",
        },
        {
            name = "whatsapp_initial",
            match = { initial_title = "^(web.whatsapp.com_/)$" },
            workspace = "special:whatsapp silent",
        },
        {
            name = "whatsapp_current",
            match = { class = "^(brave-web%.whatsapp%.com__%-Default)$" },
            workspace = "special:whatsapp silent",
        },
        {
            name = "spotify_initial",
            match = { initial_class = "^(spotify)$" },
            workspace = "special:spotify",
        },
        {
            name = "spotify_current",
            match = { class = "^(Spotify|spotify)$" },
            workspace = "special:spotify",
        },
        -- Chromium preview windows.
        {
            name = "assign_popup",
            match = { class = "^()$", title = "^()$" },
            tag = "+popup",
        },
        {
            name = "magic_popups",
            match = { tag = "popup" },
            float = true,
        },
        {
            name = "force_wl_mirror",
            match = { class = "at.yrlf.wl_mirror" },
            float = true,
            size = "1280 720",
        },
    }

    for _, rule in ipairs(window_rules) do
        hl.window_rule(rule)
    end

    hl.on("window.open", move_popup_to_cursor)

    local layer_rules = {
        {
            name = "vicinae",
            match = { namespace = "vicinae" },
            dim_around = true,
            blur = true,
            ignore_alpha = 0,
            xray = false,
        },
        -- https://www.reddit.com/r/hyprland/comments/1eu3qdv/screenshot_captures_selection_outline_with_grim/
        {
            name = "selection",
            match = { namespace = "selection" },
            no_anim = true,
        },
        {
            name = "powermenu",
            match = { namespace = "powermenu" },
            blur = true,
            dim_around = true,
        },
    }

    for _, rule in ipairs(layer_rules) do
        hl.layer_rule(rule)
    end
end

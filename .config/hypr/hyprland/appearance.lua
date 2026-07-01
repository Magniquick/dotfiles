return function(ctx)
    local theme = ctx.theme

    hl.config({
        general = {
            gaps_in = 3,
            gaps_out = 4,
            border_size = 1,
            col = {
                active_border = theme.border,
                inactive_border = theme.surface1,
            },
            resize_on_border = true,
            allow_tearing = false,
            layout = "dwindle",
        },

        xwayland = {
            force_zero_scaling = true,
        },

        ecosystem = {
            no_update_news = true,
            no_donation_nag = true,
        },

        decoration = {
            rounding = 8,
            rounding_power = 3,
            active_opacity = 1,
            inactive_opacity = 0.87,
            shadow = {
                enabled = false,
            },
            blur = {
                enabled = true,
                size = 8,
                passes = 3,
            },
        },

        animations = {
            enabled = true,
        },

        dwindle = {
            preserve_split = true,
        },

        misc = {
            force_default_wallpaper = 0,
            disable_hyprland_logo = true,
            disable_splash_rendering = true,
            disable_autoreload = true,
            focus_on_activate = true,
            anr_missed_pings = 3,
        },
    })

    hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
    hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
    hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
    hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
    hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
    hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })

    hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
    hl.animation({ leaf = "border", enabled = true, speed = 10, bezier = "easeOutQuint" })
    hl.animation({ leaf = "borderangle", enabled = false, speed = 0, bezier = "default" })
    hl.animation({ leaf = "windows", enabled = true, speed = 4, bezier = "wind", style = "slide" })
    hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "winIn", style = "slide" })
    hl.animation({ leaf = "windowsOut", enabled = true, speed = 4, bezier = "winOut", style = "slide" })
    hl.animation({ leaf = "windowsMove", enabled = true, speed = 7, bezier = "wind", style = "slide" })
    hl.animation({ leaf = "fade", enabled = false, speed = 0, bezier = "default" })
    hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.5, bezier = "easeInOutCubic" })
    hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
    hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint" })
    hl.animation({ leaf = "layersOut", enabled = false, speed = 1, bezier = "linear" })
    hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "wind" })
    hl.animation({ leaf = "workspacesIn", enabled = true, speed = 1.9, bezier = "easeOutQuint" })
    hl.animation({ leaf = "workspacesOut", enabled = true, speed = 1, bezier = "wind" })
    hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "wind", style = "slidevert" })
end

return function()
    hl.config({
        input = {
            kb_layout = "us",
            sensitivity = 0.3,
            touchpad = {
                scroll_factor = 0.8,
                natural_scroll = true,
            },
        },
    })

    hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
    hl.gesture({ fingers = 3, direction = "vertical", action = "special", workspace_name = "magic" })
end

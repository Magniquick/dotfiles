return function(ctx)
    local launch = ctx.programs.launch

    hl.on("hyprland.start", function()
        hl.exec_cmd("hyprctl setcursor rose-pine-hyprcursor 26")
        hl.exec_cmd(launch("gtk-launch whatsapp-web"), {
            workspace = "special:whatsapp silent",
        })
    end)
end

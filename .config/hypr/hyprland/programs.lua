local prefix = "runapp"

local function launch(command)
    return prefix .. " " .. command
end

return {
    launch = launch,
    terminal = launch("kitty"),
    file_manager = launch("nautilus"),
    browser = launch("brave"),
}

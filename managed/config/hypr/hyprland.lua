local config_home = os.getenv("XDG_CONFIG_HOME")
if config_home == nil or config_home == "" then
    config_home = (os.getenv("HOME") or "") .. "/.config"
end

local hypr_root = config_home .. "/hypr"
package.path = table.concat({
    hypr_root .. "/?.lua",
    hypr_root .. "/?/init.lua",
    hypr_root .. "/?/?.lua",
    package.path,
}, ";")

local paths = require("hyprland.paths")
local theme = require("hyprland.theme")
local programs = require("hyprland.programs")

local ctx = {
    paths = paths,
    theme = theme,
    programs = programs,
}

require("hyprland.monitors")(ctx)
require("hyprland.autostart")(ctx)
require("hyprland.appearance")(ctx)
require("hyprland.input")(ctx)
require("hyprland.keybinds")(ctx)
require("hyprland.rules")(ctx)

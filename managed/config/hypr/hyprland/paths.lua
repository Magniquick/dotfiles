local config_home = os.getenv("XDG_CONFIG_HOME")
if config_home == nil or config_home == "" then
    config_home = (os.getenv("HOME") or "") .. "/.config"
end

local root = config_home .. "/hypr"

return {
    root = root,
    scripts = root .. "/scripts",
    common = root .. "/common",
}

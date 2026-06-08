local fallback = {
    border = "rgb(ffb68c)",
    red = "rgb(ffb4ab)",
    surface1 = "rgb(312823)",
    base = "rgb(1a120d)",
    text_hex = "f0dfd7",
    subtext_hex = "d7c2b8",
    text = "rgb(f0dfd7)",
    subtext = "rgb(d7c2b8)",
    overlay1 = "rgb(9f8d84)",
    overlay2 = "rgb(52443c)",
    blue_glow = "rgba(ffb68c)",
}

local ok, generated = pcall(require, "hyprland.generated_theme")
local source = ok and type(generated) == "table" and generated or {}

local theme = {}
for name, value in pairs(fallback) do
    theme[name] = source[name] or value
end

return theme

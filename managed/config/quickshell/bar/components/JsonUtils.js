function safeParse(text) {
    if (!text)
        return null;
    const trimmed = String(text).trim();
    if (trimmed === "")
        return null;
    try {
        return JSON.parse(trimmed);
    } catch (err) {
        return null;
    }
}

function parseObject(text) {
    const parsed = safeParse(text);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
        return parsed;
    return null;
}

function parseArray(text) {
    const parsed = safeParse(text);
    if (Array.isArray(parsed))
        return parsed;
    return null;
}

function formatTooltip(text) {
    if (!text)
        return "";
    const trimmed = String(text).trim();
    if (trimmed === "")
        return "";
    return trimmed.replace(/\r\n/g, "\n").replace(/\n/g, "<br/>");
}

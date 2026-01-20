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

function extractLastObjectText(text) {
    if (!text)
        return "";
    const trimmed = String(text).trim();
    const start = trimmed.lastIndexOf("{");
    const end = trimmed.lastIndexOf("}");
    if (start < 0 || end <= start)
        return "";
    return trimmed.slice(start, end + 1);
}

function parseObject(text) {
    const parsed = safeParse(text);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
        return parsed;
    const fallbackText = extractLastObjectText(text);
    if (!fallbackText)
        return null;
    const fallbackParsed = safeParse(fallbackText);
    if (fallbackParsed && typeof fallbackParsed === "object" && !Array.isArray(fallbackParsed))
        return fallbackParsed;
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

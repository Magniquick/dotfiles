function parseDdcDetect(text) {
    const blocks = String(text || "").trim().split(/\n\s*\n/);
    const map = {};
    for (const block of blocks) {
        if (!block || /does not support DDC\/CI/i.test(block) || /Invalid display/i.test(block))
            continue;
        const connectorMatch = block.match(/DRM\s*connector:\s*(?:card\d+-)?(.+)/i);
        const busMatch = block.match(/I2C\s*bus:\s*.*i2c-(\d+)/i);
        if (!connectorMatch || !busMatch)
            continue;
        const connector = String(connectorMatch[1] || "").trim();
        const busNum = String(busMatch[1] || "").trim();
        if (connector !== "" && busNum !== "")
            map[connector] = busNum;
    }
    return map;
}

function parseDdcVcp10(output) {
    const tokens = String(output || "").trim().match(/0x[0-9a-fA-F]+|\d+/g) || [];
    if (tokens.length < 2)
        return null;

    function parseNum(token) {
        if (token.startsWith("0x") || token.startsWith("0X"))
            return parseInt(token, 16);
        return parseInt(token, 10);
    }

    const current = parseNum(tokens[tokens.length - 2]);
    const max = parseNum(tokens[tokens.length - 1]);
    if (!isFinite(current) || !isFinite(max) || max <= 0)
        return null;
    return { current, max };
}

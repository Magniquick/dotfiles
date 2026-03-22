pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: root
    visible: false

    property url configUrl: Qt.resolvedUrl("../mcp_servers.json")

    FileView {
        id: configFile
        path: root.configUrl
        blockLoading: true
        blockWrites: true
        watchChanges: true
        onFileChanged: reload()
    }

    function parseServers(text) {
        if (!text)
            return [];
        try {
            const parsed = JSON.parse(text);
            return Array.isArray(parsed) ? parsed : [];
        } catch (error) {
            console.warn("Failed to parse MCP config:", error);
            return [];
        }
    }

    readonly property var servers: parseServers(configFile.text())

    function slugify(value) {
        const lower = String(value || "").trim().toLowerCase();
        let out = lower.replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
        if (!out)
            out = "mcp-server";
        return out;
    }

    function generateUniqueId(baseId, entries) {
        const base = slugify(baseId);
        const seen = {};
        const list = Array.isArray(entries) ? entries : [];
        for (let i = 0; i < list.length; i++) {
            const id = String((list[i] || {}).id || "").trim();
            if (id)
                seen[id] = true;
        }
        if (!seen[base])
            return base;
        let suffix = 2;
        while (seen[base + "-" + suffix])
            suffix += 1;
        return base + "-" + suffix;
    }

    function parseHttpUrl(url) {
        const trimmed = String(url || "").trim();
        const match = trimmed.match(/^(https?):\/\/([^\/\s?#]+)([^\s]*)$/i);
        if (!match)
            return null;
        return {
            value: trimmed,
            scheme: String(match[1] || "").toLowerCase(),
            host: String(match[2] || "").toLowerCase()
        };
    }

    function addServer(url, label) {
        const parsed = parseHttpUrl(url);
        if (!parsed)
            return { ok: false, error: "Enter a valid http:// or https:// MCP endpoint." };

        const current = parseServers(configFile.text());
        for (let i = 0; i < current.length; i++) {
            const existing = String((current[i] || {}).url || "").trim();
            if (existing === parsed.value)
                return { ok: false, error: "That MCP server URL is already configured." };
        }

        const resolvedLabel = String(label || "").trim() || parsed.host;
        const entry = {
            id: generateUniqueId(resolvedLabel || parsed.host, current),
            label: resolvedLabel,
            url: parsed.value,
            enabled: true,
            auto_connect: true
        };

        const next = current.concat([entry]);
        const serialized = JSON.stringify(next, null, 2) + "\n";
        configFile.setText(serialized);
        configFile.reload();

        const verified = parseServers(configFile.text());
        const saved = verified.find(item => String((item || {}).id || "").trim() === entry.id);
        if (!saved)
            return { ok: false, error: "Failed to save MCP server configuration." };

        return { ok: true, server: saved };
    }
}

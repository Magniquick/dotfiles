pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: root
    visible: false

    property url envFileUrl: Qt.resolvedUrl("../.env")

    FileView {
        id: envFile
        path: root.envFileUrl
        blockLoading: true
    }

    readonly property var envVars: {
        const vars = {};
        const text = envFile.text();
        if (!text)
            return vars;
        const lines = text.split("\n");
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith("#"))
                continue;
            const eqIdx = trimmed.indexOf("=");
            if (eqIdx === -1)
                continue;
            const key = trimmed.substring(0, eqIdx).trim();
            let value = trimmed.substring(eqIdx + 1).trim();
            if ((value.startsWith("\"") && value.endsWith("\"")) || (value.startsWith("'") && value.endsWith("'")))
                value = value.slice(1, -1);
            vars[key] = value;
        }
        return vars;
    }

    readonly property string openaiApiKey: envVars["OPENAI_API_KEY"] || ""
    readonly property string geminiApiKey: envVars["GEMINI_API_KEY"] || ""
    readonly property string modelId: envVars["OPENAI_MODEL"] || "gemini-2.0-flash"
}


pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
    id: root
    visible: false

    property string modelId: ""
    property string openaiApiKey: ""
    property string geminiApiKey: ""

    readonly property string currentProvider: modelId.startsWith("gemini") ? "gemini" : "openai"

    readonly property bool busy: proc.running

    signal replyReceived(string reply)
    signal errorOccurred(string message)

    // Reads a single-line JSON payload from stdin, writes a curl config with secrets
    // expanded from env vars, and executes curl with `--config` so secrets never
    // appear in argv.
    readonly property string _runnerScript: [
        "set -eu",
        "IFS= read -r payload || exit 2",
        "tmp=\"${XDG_RUNTIME_DIR:-/tmp}\"",
        "cfg=\"$(mktemp -p \"$tmp\" qs-ai-cfg.XXXXXX)\"",
        "body=\"$(mktemp -p \"$tmp\" qs-ai-body.XXXXXX)\"",
        "cleanup() { rm -f \"$cfg\" \"$body\"; }",
        "trap cleanup EXIT INT TERM",
        "printf '%s' \"$payload\" >\"$body\"",
        "if [ \"${AI_PROVIDER:-}\" = \"gemini\" ]; then",
        "  url=\"https://generativelanguage.googleapis.com/v1beta/models/${AI_MODEL_ID}:generateContent?key=${GEMINI_API_KEY}\"",
        "  printf '%s\\n' \\",
        "    \"url = \\\"$url\\\"\" \\",
        "    \"header = \\\"Content-Type: application/json\\\"\" \\",
        "    \"data-binary = \\\"@$body\\\"\" \\",
        "    \"silent\" \\",
        "    \"show-error\" \\",
        "    >\"$cfg\"",
        "else",
        "  printf '%s\\n' \\",
        "    \"url = \\\"https://api.openai.com/v1/chat/completions\\\"\" \\",
        "    \"header = \\\"Content-Type: application/json\\\"\" \\",
        "    \"header = \\\"Authorization: Bearer ${OPENAI_API_KEY}\\\"\" \\",
        "    \"data-binary = \\\"@$body\\\"\" \\",
        "    \"silent\" \\",
        "    \"show-error\" \\",
        "    >\"$cfg\"",
        "fi",
        "exec curl --config \"$cfg\""
    ].join("\n")

    property string _requestProvider: ""
    property string _stdoutText: ""
    property string _stderrText: ""
    property string _pendingPayload: ""

    function startRequest(history) {
        if (proc.running)
            return;

        _requestProvider = root.currentProvider;
        _stdoutText = "";
        _stderrText = "";

        const provider = _requestProvider;
        const needsOpenAi = provider === "openai";
        const apiKey = needsOpenAi ? root.openaiApiKey : root.geminiApiKey;
        if (!apiKey || apiKey.length === 0) {
            root.errorOccurred(`Missing API key for provider: ${provider}`);
            return;
        }

        let payload = "";
        if (provider === "gemini") {
            const systemMsg = history.find(m => m.role === "system");
            const chatMsgs = history.filter(m => m.role !== "system");
            const contents = chatMsgs.map(m => ({
                        role: m.role === "assistant" ? "model" : "user",
                        parts: [
                            { text: m.content }
                        ]
                    }));

            payload = JSON.stringify({
                contents: contents,
                systemInstruction: systemMsg ? {
                    parts: [
                        { text: systemMsg.content }
                    ]
                } : undefined
            });
        } else {
            payload = JSON.stringify({
                model: root.modelId,
                messages: history
            });
        }

        root._pendingPayload = payload + "\n";

        proc.command = ["sh", "-c", root._runnerScript];
        proc.environment = ({
            AI_PROVIDER: provider,
            AI_MODEL_ID: root.modelId,
            OPENAI_API_KEY: root.openaiApiKey || null,
            GEMINI_API_KEY: root.geminiApiKey || null
        });
        proc.running = true;
    }

    Process {
        id: proc
        stdinEnabled: true

        stdout: StdioCollector {
            onStreamFinished: root._stdoutText = this.text || ""
        }

        stderr: StdioCollector {
            onStreamFinished: root._stderrText = this.text || ""
        }

        onRunningChanged: {
            if (!running)
                return;
            if (root._pendingPayload.length === 0)
                return;

            // Only write once per request.
            const payload = root._pendingPayload;
            root._pendingPayload = "";
            proc.write(payload);
        }

        // qmllint disable signal-handler-parameters
        onExited: function(code) {
            const out = (root._stdoutText || "").trim();
            const err = (root._stderrText || "").trim();
            root._pendingPayload = "";

            if (code !== 0) {
                root.errorOccurred("Backend error: " + (err.length > 0 ? err : (out.length > 0 ? out : `Exited with code ${code}`)));
                return;
            }

            if (out.length === 0) {
                root.errorOccurred(err.length > 0 ? ("Backend error: " + err) : "No response received from the backend.");
                return;
            }

            let data = null;
            try {
                data = JSON.parse(out);
            } catch (parseErr) {
                root.errorOccurred("Failed to parse response: " + parseErr + "\n" + out.substring(0, 200));
                return;
            }

            if (data && data.error) {
                const msg = (data.error.message || data.error.status || JSON.stringify(data.error)).toString();
                root.errorOccurred("Backend error: " + msg);
                return;
            }

            let reply = "";
            try {
                if (root._requestProvider === "gemini") {
                    reply = data.candidates[0].content.parts[0].text;
                } else {
                    reply = data.choices[0].message.content;
                }
            } catch (extractErr) {
                root.errorOccurred("Failed to parse response: " + extractErr + "\n" + out.substring(0, 200));
                return;
            }

            if (!reply || reply.trim().length === 0) {
                root.errorOccurred("Backend returned an empty reply.");
                return;
            }

            root.replyReceived(reply);
        }
        // qmllint enable signal-handler-parameters
    }
}

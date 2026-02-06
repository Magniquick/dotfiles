pragma ComponentBehavior: Bound
import QtQuick

Item {
    id: root
    visible: false

    required property Item store
    required property Item aiClient

    required property var moodPrompts
    required property var moodModels

    property string modelId: ""
    property string currentMood: "default"
    property bool hasApiKey: false
    property string currentProvider: "openai"
    property string openaiApiKey: ""
    property string geminiApiKey: ""
    property bool syntaxHighlightingAvailable: false

    property bool aiBusy: false
    property string backendStatus: root.hasApiKey ? "Ready" : "Missing API key"
    readonly property string connectionStatus: root.hasApiKey ? "online" : "offline"

    property bool showCommandPicker: false
    property string activeCommand: ""

    signal scrollToEndRequested
    signal copyAllRequested

    function _requestStart(history) {
        root.aiBusy = true;
        root.backendStatus = "Thinking...";
        aiClient.startRequest(history);
    }

    function handleCommand(command) {
        const cmd = (command || "").toLowerCase().trim();
        switch (cmd) {
        case "/model":
            root.activeCommand = "model";
            root.showCommandPicker = true;
            return;
        case "/mood":
            root.activeCommand = "mood";
            root.showCommandPicker = true;
            return;
        case "/clear":
            store.clearAll();
            store.appendAssistantInfo("Chat cleared.");
            root.scrollToEndRequested();
            return;
        case "/copy":
            root.copyAllRequested();
            store.appendAssistantInfo("Copied conversation.");
            root.scrollToEndRequested();
            return;
        case "/help":
            store.appendAssistantInfo(
                "Available commands:\n"
                + "/model - Choose AI model\n"
                + "/mood - Set conversation mood\n"
                + "/clear - Clear chat history\n"
                + "/copy - Copy conversation\n"
                + "/help - Show this help\n"
                + "/status - Show current settings"
            );
            root.scrollToEndRequested();
            return;
        case "/status":
            store.appendAssistantInfo(
                `**Current Settings**\n`
                + `- Model: \`${root.modelId}\`\n`
                + `- Provider: ${root.currentProvider}\n`
                + `- Mood: ${root.currentMood}\n`
                + `- OpenAI Key: ${root.openaiApiKey.length > 0 ? "Set" : "Not set"}\n`
                + `- Gemini Key: ${root.geminiApiKey.length > 0 ? "Set" : "Not set"}\n\n`
                + `**Features**\n`
                + `- Syntax Highlighting: ${root.syntaxHighlightingAvailable ? "Available" : "Not available (install ksyntaxhighlighting)"}`
            );
            root.scrollToEndRequested();
            return;
        default:
            store.appendAssistantInfo(`Unknown command: ${command}\nType /help for available commands.`);
            root.scrollToEndRequested();
            return;
        }
    }

    function sendMessage(inputText) {
        const text = (inputText || "").trim();
        if (text.length === 0 || root.aiBusy)
            return;

        store.appendUser(text);
        root.scrollToEndRequested();

        if (!root.hasApiKey) {
            const keyName = root.currentProvider === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY";
            store.appendAssistantInfo(`Set ${keyName} in the environment to enable replies.`);
            root.scrollToEndRequested();
            return;
        }

        root._requestStart([
            { role: "system", content: moodPrompts[root.currentMood] },
            ...store.history
        ]);
    }

    function regenerateMessage(index) {
        if (index < 0 || index >= store.messages.count || root.aiBusy)
            return;
        const msg = store.messages.get(index);
        if (msg.sender !== "assistant")
            return;

        const userMsgIndex = store.findPreviousUserIndex(index);
        if (userMsgIndex < 0)
            return;

        store.truncateMessagesFrom(index);
        const userMsg = store.messages.get(userMsgIndex);
        store.truncateHistoryAfterUserMessage(userMsg.body);

        root._requestStart([
            { role: "system", content: moodPrompts[root.currentMood] },
            ...store.history
        ]);
    }

    function deleteMessage(index) {
        store.deleteMessage(index);
    }

    function editMessage(index, newContent) {
        store.editMessage(index, newContent);
    }
}


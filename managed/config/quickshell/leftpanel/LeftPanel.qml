pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../common" as Common
import "./components" as Components
import "./services" as Services

Item {
    id: root
    focus: true

    FileView {
        id: envFile
        path: Qt.resolvedUrl("./.env")
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
            if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
                value = value.slice(1, -1);
            }
            vars[key] = value;
        }
        return vars;
    }

    readonly property string openaiApiKey: envVars["OPENAI_API_KEY"] || ""
    readonly property string geminiApiKey: envVars["GEMINI_API_KEY"] || ""
    property string modelId: envVars["OPENAI_MODEL"] || "gemini-2.0-flash"

    readonly property string currentProvider: modelId.startsWith("gemini") ? "gemini" : "openai"
    readonly property string activeApiKey: currentProvider === "gemini" ? geminiApiKey : openaiApiKey
    readonly property bool hasApiKey: activeApiKey.length > 0

    property string currentMood: "default"
    property bool aiBusy: false
    property string backendStatus: hasApiKey ? "Ready" : "Missing API key"
    property var chatHistory: []
    property int currentTabIndex: 0
    property string connectionStatus: hasApiKey ? "online" : "offline"
    property bool showCommandPicker: false
    property string activeCommand: ""

    // Check if syntax highlighting is available
    readonly property bool syntaxHighlightingAvailable: syntaxCheckLoader.status === Loader.Ready
    Loader {
        id: syntaxCheckLoader
        active: true
        source: "./components/SyntaxHighlighterWrapper.qml"
    }

    readonly property var tabs: [
        {
            label: "Models",
            icon: "\udb85\udc0c",
            accent: Common.Config.color.primary
        },
        {
            label: "Metrics",
            icon: "\udb80\ude03",
            accent: Common.Config.color.primary
        }
    ]

    readonly property var availableModels: [
        {
            value: "gpt-4o",
            label: "GPT-4o",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Most capable OpenAI",
            accent: Common.Config.color.tertiary
        },
        {
            value: "gpt-4o-mini",
            label: "GPT-4o Mini",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Fast and efficient",
            accent: Common.Config.color.tertiary
        },
        {
            value: "gpt-4-turbo",
            label: "GPT-4 Turbo",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Previous flagship",
            accent: Common.Config.color.tertiary
        },
        {
            value: "gpt-3.5-turbo",
            label: "GPT-3.5 Turbo",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Fastest, cheapest",
            accent: Common.Config.color.tertiary
        },
        {
            value: "gemini-3-flash-preview",
            label: "Gemini 3 Flash",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Next-gen Flash (default)",
            accent: Common.Config.color.primary
        },
        {
            value: "gemini-2.0-flash",
            label: "Gemini 2.0 Flash",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Fast multimodal",
            accent: Common.Config.color.primary
        },
        {
            value: "gemini-2.0-flash-lite",
            label: "Gemini 2.0 Flash Lite",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Cost-efficient",
            accent: Common.Config.color.primary
        },
        {
            value: "gemini-2.0-pro-exp-02-05",
            label: "Gemini 2.0 Pro",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Best for complex tasks",
            accent: Common.Config.color.primary
        }
    ]

    FileView {
        id: configFile
        path: Qt.resolvedUrl("./config.json")
        blockLoading: true
    }

    readonly property var moodsData: {
        try {
            return JSON.parse(configFile.text()).moods || [];
        } catch (e) {
            return [];
        }
    }

    readonly property var availableMoods: moodsData.map(m => ({
                value: m.name.toLowerCase(),
                label: m.name,
                icon: m.icon || "\uf4ff",
                description: m.subtext || ""
            }))

    readonly property var moodPrompts: {
        const prompts = {};
        for (const m of moodsData) {
            prompts[m.name.toLowerCase()] = m.prompt;
        }
        return prompts;
    }

    readonly property var moodModels: {
        const models = {};
        for (const m of moodsData) {
            if (m.default_model) {
                models[m.name.toLowerCase()] = m.default_model;
            }
        }
        return models;
    }

    readonly property string currentMoodIcon: {
        const mood = moodsData.find(m => m.name.toLowerCase() === root.currentMood);
        return mood ? mood.icon : "\uf4c4";
    }

    readonly property string currentMoodName: {
        const mood = moodsData.find(m => m.name.toLowerCase() === root.currentMood);
        return mood ? mood.name : "Assistant";
    }

    readonly property string currentModelLabel: {
        const model = availableModels.find(m => m.value === modelId);
        return model ? model.label : modelId;
    }

    function deleteMessage(index) {
        if (index < 0 || index >= messageModel.count)
            return;
        const msg = messageModel.get(index);
        // Remove from chat history if it's a real message
        const historyIndex = root.chatHistory.findIndex(h => (h.role === "user" && msg.sender === "user" && h.content === msg.body) || (h.role === "assistant" && msg.sender === "assistant" && h.content === msg.body));
        if (historyIndex >= 0) {
            root.chatHistory.splice(historyIndex, 1);
        }
        messageModel.remove(index);
    }

    function editMessage(index, newContent) {
        if (index < 0 || index >= messageModel.count)
            return;
        const msg = messageModel.get(index);
        // Update in chat history
        const historyIndex = root.chatHistory.findIndex(h => (h.role === "user" && msg.sender === "user" && h.content === msg.body) || (h.role === "assistant" && msg.sender === "assistant" && h.content === msg.body));
        if (historyIndex >= 0) {
            root.chatHistory[historyIndex].content = newContent;
        }
        messageModel.setProperty(index, "body", newContent);
    }

    function regenerateMessage(index) {
        if (index < 0 || index >= messageModel.count || aiBusy)
            return;
        const msg = messageModel.get(index);
        if (msg.sender !== "assistant")
            return;

        // Find the user message before this assistant message
        let userMsgIndex = index - 1;
        while (userMsgIndex >= 0 && messageModel.get(userMsgIndex).sender !== "user") {
            userMsgIndex--;
        }
        if (userMsgIndex < 0)
            return;

        // Remove all messages from this assistant message onward
        while (messageModel.count > index) {
            messageModel.remove(messageModel.count - 1);
        }

        // Trim chat history to match
        const userMsg = messageModel.get(userMsgIndex);
        const historyIndex = root.chatHistory.findIndex(h => h.role === "user" && h.content === userMsg.body);
        if (historyIndex >= 0) {
            root.chatHistory.splice(historyIndex + 1);
        }

        // Re-send the request
        aiBusy = true;
        backendStatus = "Thinking...";
        aiClient.startRequest([
            {
                role: "system",
                content: moodPrompts[root.currentMood]
            },
            ...root.chatHistory]);
    }

    onModelIdChanged: {
        messageModel.clear();
        root.chatHistory = [];
        messageModel.append({
            sender: "assistant",
            body: `Switched to ${modelId}. Chat history cleared.`
        });
    }

    function scrollToLatestMessage() {
        Qt.callLater(() => {
            if (chatView) {
                chatView.positionToEnd();
            }
        });
    }

    function handleCommand(command) {
        const cmd = command.toLowerCase().trim();

        switch (cmd) {
        case "/model":
            activeCommand = "model";
            showCommandPicker = true;
            return;
        case "/mood":
            activeCommand = "mood";
            showCommandPicker = true;
            return;
        case "/clear":
            messageModel.clear();
            root.chatHistory = [];
            messageModel.append({
                sender: "assistant",
                body: "Chat cleared."
            });
            return;
        case "/copy":
            if (chatView) {
                chatView.copyAllMessages();
            }
            messageModel.append({
                sender: "assistant",
                body: "Copied conversation."
            });
            return;
        case "/help":
            messageModel.append({
                sender: "assistant",
                body: "Available commands:\n" + "/model - Choose AI model\n" + "/mood - Set conversation mood\n" + "/clear - Clear chat history\n" + "/copy - Copy conversation\n" + "/help - Show this help\n" + "/status - Show current settings"
            });
            break;
        case "/status":
            messageModel.append({
                sender: "assistant",
                body: `**Current Settings**\n` + `- Model: \`${modelId}\`\n` + `- Provider: ${currentProvider}\n` + `- Mood: ${currentMood}\n` + `- OpenAI Key: ${openaiApiKey.length > 0 ? "Set" : "Not set"}\n` + `- Gemini Key: ${geminiApiKey.length > 0 ? "Set" : "Not set"}\n\n` + `**Features**\n` + `- Syntax Highlighting: ${syntaxHighlightingAvailable ? "Available" : "Not available (install ksyntaxhighlighting)"}`
            });
            break;
        default:
            messageModel.append({
                sender: "assistant",
                body: `Unknown command: ${command}\nType /help for available commands.`
            });
        }
        scrollToLatestMessage();
    }

    function sendMessage(inputText) {
        const text = inputText.trim();
        if (text.length === 0 || aiBusy)
            return;

        messageModel.append({
            sender: "user",
            body: text
        });
        chatHistory.push({
            role: "user",
            content: text
        });
        scrollToLatestMessage();

        if (!hasApiKey) {
            const keyName = currentProvider === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY";
            messageModel.append({
                sender: "assistant",
                body: `Set ${keyName} in the environment to enable replies.`
            });
            scrollToLatestMessage();
            return;
        }

        aiBusy = true;
        backendStatus = "Thinking...";
        aiClient.startRequest([
            {
                role: "system",
                content: moodPrompts[currentMood]
            },
            ...chatHistory]);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            Common.GlobalState.leftPanelVisible = false;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Common.Config.color.surface_container
        border.width: 1
        border.color: Common.Config.color.outline
        radius: Common.Config.shape.corner.lg
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: Common.Config.space.md
        }
        spacing: Common.Config.sectionSpacing

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Common.Config.space.xs
        }

        Components.NavPill {
            id: navPill
            Layout.alignment: Qt.AlignHCenter
            tabs: root.tabs
            currentIndex: root.currentTabIndex
            connectionStatus: root.connectionStatus
            onTabSelected: index => root.currentTabIndex = index
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.currentTabIndex

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Components.ChatView {
                    id: chatView
                    anchors.fill: parent
                    messages: messageModel
                    busy: root.aiBusy
                    modelId: root.modelId
                    modelLabel: root.currentModelLabel
                    moodIcon: root.currentMoodIcon
                    moodName: root.currentMoodName
                    connectionOnline: root.connectionStatus === "online"
                    onSendRequested: text => root.sendMessage(text)
                    onCommandTriggered: command => root.handleCommand(command)
                    onRegenerateRequested: index => root.regenerateMessage(index)
                    onDeleteRequested: index => root.deleteMessage(index)
                    onEditRequested: (index, newContent) => root.editMessage(index, newContent)
                }

                // Command Picker Overlay
                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Common.Config.color.surface_dim, 0.92)
                    visible: root.showCommandPicker

                    readonly property bool isModelPicker: root.activeCommand === "model"

                    MouseArea {
                        anchors.fill: parent
                        onClicked: root.showCommandPicker = false
                    }

                    Components.CommandPicker {
                        anchors.centerIn: parent
                        command: parent.isModelPicker ? "/MODEL" : "/MOOD"
                        options: parent.isModelPicker ? root.availableModels : root.availableMoods
                        visible: root.showCommandPicker

                        onOptionSelected: value => {
                            if (root.activeCommand === "model") {
                                root.modelId = value;
                            } else {
                                root.currentMood = value;
                                const newModel = root.moodModels[value];
                                if (newModel && newModel !== root.modelId) {
                                    root.modelId = newModel;
                                }
                                messageModel.append({
                                    sender: "assistant",
                                    body: `Mood: ${value}`
                                });
                            }
                            root.showCommandPicker = false;
                            root.scrollToLatestMessage();
                        }

                        onDismissed: root.showCommandPicker = false
                    }
                }
            }

            Components.MetricsView {
                id: metricsView
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            color: Common.Config.color.surface_container_low
            radius: Common.Config.shape.corner.md
            border.width: 1
            border.color: Qt.alpha(Common.Config.color.on_surface, 0.1)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Common.Config.space.md
                anchors.rightMargin: Common.Config.space.md

                // Chat tab footer
                Row {
                    visible: root.currentTabIndex === 0
                    spacing: Common.Config.space.sm

                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: root.hasApiKey ? Common.Config.color.tertiary : Common.Config.color.error
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "MODEL: " + root.modelId.toUpperCase()
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.7
                    }
                }

                // Metrics tab footer
                Row {
                    visible: root.currentTabIndex === 1
                    spacing: Common.Config.space.sm

                    Text {
                        text: "\uf46e"
                        color: Common.Config.color.primary
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "UPTIME: " + metricsView.uptime.toUpperCase()
                        color: Common.Config.color.on_surface_variant
                        font.family: Common.Config.fontFamily
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        opacity: 0.7
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                // Chat tab right side
                Text {
                    visible: root.currentTabIndex === 0
                    text: "MOOD: " + root.currentMoodName.toUpperCase()
                    color: Common.Config.color.on_surface_variant
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    opacity: 0.7
                }

                // Metrics tab right side
                Item {
                    Layout.preferredHeight: 1
                    Layout.preferredWidth: 1
                    visible: root.currentTabIndex === 1
                }
            }
        }
    }

    Services.AiClient {
        id: aiClient
        modelId: root.modelId
        openaiApiKey: root.openaiApiKey
        geminiApiKey: root.geminiApiKey

        onReplyReceived: function(reply) {
            root.aiBusy = false;
            root.backendStatus = "Ready";

            root.chatHistory.push({
                role: "assistant",
                content: reply
            });
            messageModel.append({
                sender: "assistant",
                body: reply
            });
            root.scrollToLatestMessage();
        }

        onErrorOccurred: function(message) {
            root.aiBusy = false;
            root.backendStatus = "Error";
            messageModel.append({
                sender: "assistant",
                body: message
            });
            root.scrollToLatestMessage();
        }
    }

    ListModel {
        id: messageModel
        ListElement {
            sender: "assistant"
            body: "Hi! This panel is wired to OpenAI chat completions."
        }
        ListElement {
            sender: "assistant"
            body: "Set OPENAI_API_KEY to enable replies."
        }
    }
}

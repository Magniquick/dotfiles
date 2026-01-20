pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "./common" as Common
import "./components" as Components

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
    property string modelId: envVars["OPENAI_MODEL"] || "gpt-4o-mini"
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

    readonly property var tabs: [
        {
            label: "Models",
            icon: "\udb85\udc0c",
            accent: Common.Config.primary
        },
        {
            label: "Metrics",
            icon: "\udb80\ude03",
            accent: Common.Config.m3.info
        }
    ]

    readonly property var availableModels: [
        {
            value: "gpt-4o",
            label: "GPT-4o",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Most capable OpenAI",
            accent: Common.Config.m3.success
        },
        {
            value: "gpt-4o-mini",
            label: "GPT-4o Mini",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Fast and efficient (default)",
            accent: Common.Config.m3.success
        },
        {
            value: "gpt-4-turbo",
            label: "GPT-4 Turbo",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Previous flagship",
            accent: Common.Config.m3.success
        },
        {
            value: "gpt-3.5-turbo",
            label: "GPT-3.5 Turbo",
            iconImage: "./assets/OpenAI-white-monoblossom.svg",
            description: "Fastest, cheapest",
            accent: Common.Config.m3.success
        },
        {
            value: "gemini-2.0-flash",
            label: "Gemini 2.0 Flash",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Fast multimodal",
            accent: Common.Config.m3.info
        },
        {
            value: "gemini-2.0-flash-lite",
            label: "Gemini 2.0 Flash Lite",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Cost-efficient",
            accent: Common.Config.m3.info
        },
        {
            value: "gemini-1.5-pro",
            label: "Gemini 1.5 Pro",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Best for complex tasks",
            accent: Common.Config.m3.tertiary
        },
        {
            value: "gemini-1.5-flash",
            label: "Gemini 1.5 Flash",
            iconImage: "./assets/Google_Gemini_icon_2025.svg.png",
            description: "Fast and versatile",
            accent: Common.Config.m3.tertiary
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
        const mood = moodsData.find(m => m.name.toLowerCase() === currentMood);
        return mood ? mood.icon : "\uf4c4";
    }

    readonly property string currentMoodName: {
        const mood = moodsData.find(m => m.name.toLowerCase() === currentMood);
        return mood ? mood.name : "Assistant";
    }

    onModelIdChanged: {
        messageModel.clear();
        chatHistory = [];
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
            chatHistory = [];
            messageModel.append({
                sender: "assistant",
                body: "Chat cleared."
            });
            return;
        case "/help":
            messageModel.append({
                sender: "assistant",
                body: "Available commands:\n" + "/model - Choose AI model\n" + "/mood - Set conversation mood\n" + "/clear - Clear chat history\n" + "/help - Show this help\n" + "/status - Show current settings"
            });
            break;
        case "/status":
            messageModel.append({
                sender: "assistant",
                body: `Current Settings:\n` + `Model: ${modelId}\n` + `Provider: ${currentProvider}\n` + `Mood: ${currentMood}\n` + `OpenAI Key: ${openaiApiKey.length > 0 ? "Set" : "Not set"}\n` + `Gemini Key: ${geminiApiKey.length > 0 ? "Set" : "Not set"}`
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
        aiProc.startRequest([
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
        border.width: 1
        border.color: Common.Config.m3.outline
        radius: Common.Config.shape.corner.lg
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: Common.Config.m3.surfaceDim
            }
            GradientStop {
                position: 1.0
                color: Common.Config.surfaceContainer
            }
        }
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
                    moodIcon: root.currentMoodIcon
                    moodName: root.currentMoodName
                    connectionOnline: root.connectionStatus === "online"
                    onSendRequested: text => root.sendMessage(text)
                    onCommandTriggered: command => root.handleCommand(command)
                }

                // Command Picker Overlay
                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(Common.Config.m3.surfaceDim, 0.92)
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
            color: "transparent"
            radius: Common.Config.shape.corner.md
            border.width: 1
            border.color: Qt.alpha(Common.Config.textColor, 0.1)

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
                        color: root.hasApiKey ? Common.Config.m3.success : Common.Config.m3.error
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "MODEL: " + root.modelId.toUpperCase()
                        color: Common.Config.textMuted
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
                        color: Common.Config.m3.info
                        font.family: Common.Config.iconFontFamily
                        font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: "UPTIME: " + metricsView.uptime.toUpperCase()
                        color: Common.Config.textMuted
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
                    color: Common.Config.textMuted
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    opacity: 0.7
                }

                // Metrics tab right side
                Text {
                    visible: root.currentTabIndex === 1
                    text: "SYSTEM ACTIVE"
                    color: Common.Config.textMuted
                    font.family: Common.Config.fontFamily
                    font.pixelSize: 9
                    font.weight: Font.Bold
                    font.letterSpacing: 1.5
                    opacity: 0.5
                }
            }
        }
    }

    Process {
        id: aiProc
        property string lastError: ""
        property string requestProvider: ""

        function startRequest(history) {
            requestProvider = root.currentProvider;

            if (root.currentProvider === "gemini") {
                const systemMsg = history.find(m => m.role === "system");
                const chatMsgs = history.filter(m => m.role !== "system");
                const contents = chatMsgs.map(m => ({
                            role: m.role === "assistant" ? "model" : "user",
                            parts: [
                                {
                                    text: m.content
                                }
                            ]
                        }));
                const payload = JSON.stringify({
                    contents: contents,
                    systemInstruction: systemMsg ? {
                        parts: [
                            {
                                text: systemMsg.content
                            }
                        ]
                    } : undefined
                });
                const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${root.modelId}:generateContent?key=${root.geminiApiKey}`;
                command = ["curl", "-sS", endpoint, "-H", "Content-Type: application/json", "-d", payload];
            } else {
                const payload = JSON.stringify({
                    model: root.modelId,
                    messages: history
                });
                command = ["curl", "-sS", "https://api.openai.com/v1/chat/completions", "-H", "Content-Type: application/json", "-H", "Authorization: Bearer " + root.openaiApiKey, "-d", payload];
            }
            running = true;
        }

        stdout: StdioCollector {
            onStreamFinished: {
                root.aiBusy = false;
                root.backendStatus = "Ready";
                if (!text || text.trim().length === 0) {
                    messageModel.append({
                        sender: "assistant",
                        body: "No response received from the backend."
                    });
                    return;
                }
                let reply = "";
                try {
                    const data = JSON.parse(text);
                    if (aiProc.requestProvider === "gemini") {
                        reply = data.candidates[0].content.parts[0].text;
                    } else {
                        reply = data.choices[0].message.content;
                    }
                } catch (err) {
                    messageModel.append({
                        sender: "assistant",
                        body: "Failed to parse response: " + err + "\n" + text.substring(0, 200)
                    });
                    return;
                }
                if (!reply || reply.trim().length === 0) {
                    messageModel.append({
                        sender: "assistant",
                        body: "Backend returned an empty reply."
                    });
                    return;
                }
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
        }

        stderr: StdioCollector {
            onStreamFinished: {
                if (text && text.trim().length > 0) {
                    aiProc.lastError = text.trim();
                }
            }
        }

        onRunningChanged: {
            if (!running && lastError.length > 0) {
                root.aiBusy = false;
                root.backendStatus = "Error";
                messageModel.append({
                    sender: "assistant",
                    body: "Backend error: " + lastError
                });
                aiProc.lastError = "";
                root.scrollToLatestMessage();
            }
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

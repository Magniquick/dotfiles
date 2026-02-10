pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common" as Common
import "./services" as Services
import "./views" as Views
import qsnative

Item {
    id: root

    function focusComposer() {
        if (panelView && panelView.focusComposer)
            panelView.focusComposer();
    }

    function clearTextFocus() {
        if (panelView && panelView.clearTextFocus)
            panelView.clearTextFocus();
    }

    Services.EnvLoader {
        id: envLoader
    }

    readonly property string openaiApiKey: envLoader.openaiApiKey
    readonly property string geminiApiKey: envLoader.geminiApiKey
    property string modelId: envLoader.modelId

    readonly property string currentProvider: modelId.startsWith("gemini") ? "gemini" : "openai"
    readonly property string activeApiKey: currentProvider === "gemini" ? geminiApiKey : openaiApiKey
    readonly property bool hasApiKey: activeApiKey.length > 0

    property string currentMood: "default"
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
        { label: "Models", icon: "\udb85\udc0c", accent: Common.Config.color.primary },
        { label: "Metrics", icon: "\udb80\ude03", accent: Common.Config.color.primary }
    ]

    AiModelCatalog {
        id: modelCatalog
        openai_api_key: root.openaiApiKey
        gemini_api_key: root.geminiApiKey
        openai_base_url: "" // future: openrouter/litellm/etc
    }

    property var availableModels: []

    Services.MoodConfig {
        id: moodConfig
    }

    readonly property var availableMoods: moodConfig.availableMoods
    readonly property var moodPrompts: moodConfig.moodPrompts
    readonly property var moodModels: moodConfig.moodModels

    readonly property string currentMoodIcon: moodConfig.moodIcon(root.currentMood)
    readonly property string currentMoodName: moodConfig.moodName(root.currentMood)

    readonly property string currentModelLabel: {
        const model = availableModels.find(m => m.value === modelId);
        return model ? model.label : modelId;
    }

    function rebuildAvailableModels() {
        let parsed = [];
        try {
            parsed = JSON.parse(modelCatalog.models_json || "[]");
        } catch (e) {
            parsed = [];
        }

        const out = [];
        for (let i = 0; i < parsed.length; i++) {
            const m = parsed[i] || {};
            const value = m.value || "";
            const provider = m.provider || (value.startsWith("gemini-") ? "gemini" : "openai");
            out.push({
                value,
                label: m.label || value,
                description: m.description || "",
                recommended: !!m.recommended,
                iconImage: provider === "gemini"
                    ? "./assets/Google_Gemini_icon_2025.svg.png"
                    : "./assets/OpenAI-white-monoblossom.svg",
                accent: provider === "gemini"
                    ? Common.Config.color.primary
                    : Common.Config.color.tertiary
            });
        }
        root.availableModels = out;
    }

    function closePanel() {
        Common.GlobalState.leftPanelVisible = false;
    }

    AiChatSession {
        id: chatSession
        model_id: root.modelId
        system_prompt: root.moodPrompts[root.currentMood] || ""
        openai_api_key: root.openaiApiKey
        gemini_api_key: root.geminiApiKey
        openai_base_url: "" // future: openrouter/litellm/etc

        onOpenModelPickerRequested: {
            modelCatalog.refresh();
            root.activeCommand = "model";
            root.showCommandPicker = true;
        }
        onOpenMoodPickerRequested: {
            root.activeCommand = "mood";
            root.showCommandPicker = true;
        }
        onScrollToEndRequested: panelView.scrollToEnd()
        onCopyAllRequested: function(text) {
            Quickshell.clipboardText = text;
        }
    }

    Connections {
        target: modelCatalog

        function onModels_jsonChanged() {
            root.rebuildAvailableModels();
        }
    }

    onModelIdChanged: {
        chatSession.resetForModelSwitch(root.modelId);
        panelView.scrollToEnd();
    }

    Views.LeftPanelView {
        id: panelView
        anchors.fill: parent

        tabs: root.tabs
        messagesModel: chatSession
        chatSession: chatSession
        aiBusy: chatSession.busy
        modelId: root.modelId
        modelLabel: root.currentModelLabel
        moodIcon: root.currentMoodIcon
        moodName: root.currentMoodName
        connectionOnline: root.hasApiKey
        connectionStatus: root.hasApiKey ? "online" : "offline"
        showCommandPicker: root.showCommandPicker
        activeCommand: root.activeCommand
        availableModels: root.availableModels
        availableMoods: root.availableMoods

        footerDotColor: panelView.currentTabIndex === 0
            ? (root.hasApiKey ? Common.Config.color.tertiary : Common.Config.color.error)
            : (panelView.metricsHealthy ? Common.Config.color.tertiary : Common.Config.color.secondary)
        footerLeftText: panelView.currentTabIndex === 0
            ? ("MODEL: " + root.modelId.toUpperCase())
            : ("UPTIME: " + panelView.metricsUptime)
        footerRightText: panelView.currentTabIndex === 0
            ? ("MOOD: " + root.currentMoodName.toUpperCase())
            : (panelView.metricsHealthy ? "HEALTH: OK" : "HEALTH: WARN")

        onCloseRequested: root.closePanel()
        onTabSelected: index => panelView.currentTabIndex = index
        onSendRequested: function(text, attachmentsJson) {
            const trimmed = (attachmentsJson || "").trim();
            if (!trimmed || trimmed === "[]")
                chatSession.submitInput(text);
            else
                chatSession.submitInputWithAttachments(text, trimmed);
        }
        onCommandTriggered: command => chatSession.submitInput(command)
        onRegenerateRequested: messageId => chatSession.regenerate(messageId)
        onDeleteRequested: messageId => chatSession.deleteMessage(messageId)
        onEditRequested: (messageId, newContent) => chatSession.editMessage(messageId, newContent)

        onDismissCommandPickerRequested: root.showCommandPicker = false

        onModelSelected: value => {
            root.modelId = value;
            root.showCommandPicker = false;
        }

        onMoodSelected: value => {
            root.currentMood = value;
            const newModel = root.moodModels[value];
            if (newModel && newModel !== root.modelId)
                root.modelId = newModel;
            chatSession.appendInfo(`Mood: ${value}`);
            root.showCommandPicker = false;
            panelView.scrollToEnd();
        }
    }

    Component.onCompleted: {
        // Avoid forcing a network refresh on startup; open the model picker to refresh when needed.
        root.rebuildAvailableModels();
    }
}

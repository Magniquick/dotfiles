pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../common" as Common
import "./services" as Services
import "./stores" as Stores
import "./controllers" as Controllers
import "./views" as Views

Item {
    id: root
    focus: true

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

    readonly property var availableModels: [
        { value: "gpt-4o", label: "GPT-4o", iconImage: "./assets/OpenAI-white-monoblossom.svg", description: "Most capable OpenAI", accent: Common.Config.color.tertiary },
        { value: "gpt-4o-mini", label: "GPT-4o Mini", iconImage: "./assets/OpenAI-white-monoblossom.svg", description: "Fast and efficient", accent: Common.Config.color.tertiary },
        { value: "gpt-4-turbo", label: "GPT-4 Turbo", iconImage: "./assets/OpenAI-white-monoblossom.svg", description: "Previous flagship", accent: Common.Config.color.tertiary },
        { value: "gpt-3.5-turbo", label: "GPT-3.5 Turbo", iconImage: "./assets/OpenAI-white-monoblossom.svg", description: "Fastest, cheapest", accent: Common.Config.color.tertiary },
        { value: "gemini-3-flash-preview", label: "Gemini 3 Flash", iconImage: "./assets/Google_Gemini_icon_2025.svg.png", description: "Next-gen Flash (default)", accent: Common.Config.color.primary },
        { value: "gemini-2.0-flash", label: "Gemini 2.0 Flash", iconImage: "./assets/Google_Gemini_icon_2025.svg.png", description: "Fast multimodal", accent: Common.Config.color.primary },
        { value: "gemini-2.0-flash-lite", label: "Gemini 2.0 Flash Lite", iconImage: "./assets/Google_Gemini_icon_2025.svg.png", description: "Cost-efficient", accent: Common.Config.color.primary },
        { value: "gemini-2.0-pro-exp-02-05", label: "Gemini 2.0 Pro", iconImage: "./assets/Google_Gemini_icon_2025.svg.png", description: "Best for complex tasks", accent: Common.Config.color.primary }
    ]

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

    function closePanel() {
        Common.GlobalState.leftPanelVisible = false;
    }

    Stores.ChatStore {
        id: chatStore
    }

    Services.AiClient {
        id: aiClient
        modelId: root.modelId
        openaiApiKey: root.openaiApiKey
        geminiApiKey: root.geminiApiKey

        onReplyReceived: function(reply) {
            chatController.aiBusy = false;
            chatController.backendStatus = "Ready";
            chatStore.appendAssistant(reply);
            panelView.scrollToEnd();
        }

        onErrorOccurred: function(message) {
            chatController.aiBusy = false;
            chatController.backendStatus = "Error";
            chatStore.appendAssistantInfo(message);
            panelView.scrollToEnd();
        }
    }

    Controllers.ChatController {
        id: chatController
        store: chatStore
        aiClient: aiClient
        moodPrompts: root.moodPrompts
        moodModels: root.moodModels
        modelId: root.modelId
        currentMood: root.currentMood
        hasApiKey: root.hasApiKey
        currentProvider: root.currentProvider
        openaiApiKey: root.openaiApiKey
        geminiApiKey: root.geminiApiKey
        syntaxHighlightingAvailable: root.syntaxHighlightingAvailable

        onScrollToEndRequested: panelView.scrollToEnd()
        onCopyAllRequested: panelView.copyAllMessages()
    }

    onModelIdChanged: {
        chatStore.resetForModelSwitch(root.modelId);
        panelView.scrollToEnd();
    }

    Views.LeftPanelView {
        id: panelView
        anchors.fill: parent

        tabs: root.tabs
        messages: chatStore.messages
        aiBusy: chatController.aiBusy
        modelId: root.modelId
        modelLabel: root.currentModelLabel
        moodIcon: root.currentMoodIcon
        moodName: root.currentMoodName
        connectionOnline: chatController.connectionStatus === "online"
        connectionStatus: chatController.connectionStatus
        showCommandPicker: chatController.showCommandPicker
        activeCommand: chatController.activeCommand
        availableModels: root.availableModels
        availableMoods: root.availableMoods

        footerDotColor: root.hasApiKey ? Common.Config.color.tertiary : Common.Config.color.error
        footerLeftText: panelView.currentTabIndex === 0 ? ("MODEL: " + root.modelId.toUpperCase()) : ""
        footerRightText: panelView.currentTabIndex === 0 ? ("MOOD: " + root.currentMoodName.toUpperCase()) : ""

        onCloseRequested: root.closePanel()
        onTabSelected: index => panelView.currentTabIndex = index
        onSendRequested: text => chatController.sendMessage(text)
        onCommandTriggered: command => chatController.handleCommand(command)
        onRegenerateRequested: index => chatController.regenerateMessage(index)
        onDeleteRequested: index => chatController.deleteMessage(index)
        onEditRequested: (index, newContent) => chatController.editMessage(index, newContent)

        onDismissCommandPickerRequested: chatController.showCommandPicker = false

        onModelSelected: value => {
            root.modelId = value;
            chatController.showCommandPicker = false;
        }

        onMoodSelected: value => {
            root.currentMood = value;
            const newModel = root.moodModels[value];
            if (newModel && newModel !== root.modelId)
                root.modelId = newModel;
            chatStore.appendAssistantInfo(`Mood: ${value}`);
            chatController.showCommandPicker = false;
            panelView.scrollToEnd();
        }
    }
}

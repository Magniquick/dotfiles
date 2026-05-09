pragma ComponentBehavior: Bound
import QtQuick
import "../common" as Common
import "./components" as Components
import "./services" as Services
import "./views" as Views
import qsgo

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

    function setLatestVisibleToolExpanded(expanded) {
        return panelView && panelView.setLatestVisibleToolExpanded
            ? panelView.setLatestVisibleToolExpanded(expanded)
            : false;
    }

    function setClipboardText(text) {
        // qmllint disable unqualified
        Quickshell.clipboardText = text;
        // qmllint enable unqualified
    }

    Services.EnvLoader {
        id: envLoader
    }

    Services.McpConfig {
        id: mcpConfig
    }

    readonly property var providerConfig: envLoader.providerConfig
    readonly property var mcpConfigList: mcpConfig.servers
    property string modelId: envLoader.modelId

    readonly property color _linkColor: Common.Config.color.primary
    on_LinkColorChanged: chatSession.setAppLinkColor(_linkColor)

    readonly property string currentProvider: {
        const parts = String(modelId || "").split("/");
        return parts.length > 1 ? parts[0] : "";
    }
    readonly property var activeProviderConfig: providerConfig[currentProvider] || ({})
    readonly property string activeApiKey: activeProviderConfig.api_key || ""
    readonly property bool hasApiKey: activeApiKey.length > 0

    property string currentMood: "default"
    property bool showCommandPicker: false
    property bool showMcpAddDialog: false
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

    Services.MoodConfig {
        id: moodConfig
    }

    Services.ModelConfig {
        id: modelConfig
        providerConfig: root.providerConfig
    }

    readonly property var availableMoods: moodConfig.availableMoods
    readonly property var moodPrompts: moodConfig.moodPrompts
    readonly property var moodModels: moodConfig.moodModels
    readonly property var availableModels: modelConfig.availableModels

    readonly property string currentMoodIcon: moodConfig.moodIcon(root.currentMood)
    readonly property string currentMoodName: moodConfig.moodName(root.currentMood)

    readonly property string currentModelLabel: {
        const model = availableModels.find(m => m.value === modelId);
        return model ? model.label : (String(modelId || "").split("/").slice(1).join("/") || modelId);
    }

    function closePanel() {
        Common.GlobalState.leftPanelVisible = false;
    }

    function canonicalModelId(rawId) {
        const trimmed = String(rawId || "").trim();
        if (!trimmed)
            return root.modelId;
        if (trimmed.indexOf("/") !== -1)
            return trimmed;
        const provider = trimmed.startsWith("gemini-") ? "gemini" : (trimmed.startsWith("gpt-5.") ? "local" : "openai");
        return provider + "/" + trimmed;
    }

    AiChatSession {
        id: chatSession
        model_id: String(root.modelId)
        system_prompt: root.moodPrompts[root.currentMood] || ""
        provider_config: root.providerConfig
        mcp_config: root.mcpConfigList

        onOpenModelPickerRequested: {
            root.showMcpAddDialog = false;
            root.activeCommand = "model";
            root.showCommandPicker = true;
        }
        onOpenMoodPickerRequested: {
            root.showMcpAddDialog = false;
            root.activeCommand = "mood";
            root.showCommandPicker = true;
        }
        onOpenResumePickerRequested: {
            root.showMcpAddDialog = false;
            root.activeCommand = "resume";
            root.showCommandPicker = true;
        }
        onOpenMcpAddRequested: {
            root.showCommandPicker = false;
            root.showMcpAddDialog = true;
            Qt.callLater(() => {
                if (mcpAddDialog && mcpAddDialog.visible && mcpAddDialog.focusPrimaryField)
                    mcpAddDialog.focusPrimaryField();
            });
        }
        onScrollToEndRequested: panelView.scrollToEnd()
        onCopyAllRequested: function(text) {
            root.setClipboardText(text);
        }
        Component.onCompleted: restoreHistory()
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
        resumeConversations: chatSession.resume_conversations

        footerDotColor: panelView.currentTabIndex === 0
            ? (root.hasApiKey ? Common.Config.color.tertiary : Common.Config.color.error)
            : (panelView.metricsHealthy ? Common.Config.color.tertiary : Common.Config.color.secondary)
        footerLeftText: panelView.currentTabIndex === 0
            ? ("MODEL: " + root.currentModelLabel.toUpperCase())
            : ("UPTIME: " + panelView.metricsUptime)
        footerRightText: panelView.currentTabIndex === 0
            ? ("PROVIDER: " + root.currentProvider.toUpperCase())
            : (panelView.metricsHealthy ? "HEALTH: OK" : "HEALTH: WARN")

        onCloseRequested: root.closePanel()
        onTabSelected: index => panelView.currentTabIndex = index
        onSendRequested: function(text, attachments) {
            if (!attachments || attachments.length === 0)
                chatSession.submitInput(text);
            else
                chatSession.submitInputWithAttachments(text, attachments);
        }
        onCommandTriggered: command => chatSession.submitInput(command)
        onRegenerateRequested: messageId => chatSession.regenerate(messageId)
        onDeleteRequested: messageId => chatSession.deleteMessage(messageId)
        onEditRequested: (messageId, newContent) => chatSession.editMessage(messageId, newContent)

        onDismissCommandPickerRequested: root.showCommandPicker = false

        onModelSelected: value => {
            root.modelId = root.canonicalModelId(value);
            root.showCommandPicker = false;
        }

        onMoodSelected: value => {
            root.currentMood = value;
            const newModel = root.moodModels[value];
            if (newModel && root.canonicalModelId(newModel) !== root.modelId)
                root.modelId = root.canonicalModelId(newModel);
            chatSession.appendInfo(`Mood: ${value}`);
            root.showCommandPicker = false;
            panelView.scrollToEnd();
        }

        onResumeSelected: value => {
            if (chatSession.resumeConversation(value)) {
                root.showCommandPicker = false;
                panelView.scrollToEnd();
            }
        }

        onResumeSearchChanged: query => chatSession.refreshResumeConversations(query)
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Common.Config.color.surface_dim, 0.92)
        visible: root.showMcpAddDialog
        z: 10

        MouseArea {
            id: mcpOverlayDismissArea
            anchors.fill: parent
            onClicked: mouse => {
                if (!mcpAddDialog || !mcpAddDialog.visible) {
                    root.showMcpAddDialog = false;
                    return;
                }
                const p = mcpAddDialog.mapFromItem(mcpOverlayDismissArea, mouse.x, mouse.y);
                const inside = p.x >= 0 && p.y >= 0 && p.x <= mcpAddDialog.width && p.y <= mcpAddDialog.height;
                if (!inside)
                    root.showMcpAddDialog = false;
            }
        }

        Components.McpAddDialog {
            id: mcpAddDialog
            anchors.centerIn: parent
            visible: root.showMcpAddDialog

            onDismissed: {
                clearForm();
                root.showMcpAddDialog = false;
            }

            onSubmitted: function(url, label) {
                errorText = "";
                const result = mcpConfig.addServer(url, label);
                if (!result || !result.ok) {
                    errorText = result && result.error ? result.error : "Failed to add MCP server.";
                    return;
                }

                clearForm();
                root.showMcpAddDialog = false;
                chatSession.refreshMcp();
                const server = result.server || {};
                const labelText = server.label || server.id || "MCP server";
                const idText = server.id || "(generated)";
                chatSession.appendInfo(
                    `Added MCP server **${labelText}** (\`${idText}\`).\n\n` +
                    `Advanced auth and custom headers can be edited in \`leftpanel/mcp_servers.json\`.`
                );
            }
        }
    }
}

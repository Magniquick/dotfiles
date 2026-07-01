pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "../common" as Common
import "../common/JsonUtils.js" as JsonUtils
import "./services" as Services
import "./views" as Views
import qsnative

Item {
  id: root

  function focusComposer() {
    if (panelView && panelView.focusComposer)
      panelView.focusComposer()
  }

  function clearTextFocus() {
    if (panelView && panelView.clearTextFocus)
      panelView.clearTextFocus()
  }

  function setLatestVisibleToolExpanded(expanded) {
    return panelView && panelView.setLatestVisibleToolExpanded ? panelView.setLatestVisibleToolExpanded(expanded) : false
  }

  function setClipboardText(text) {
    Quickshell.clipboardText = text
  }

  Services.EnvLoader {
    id: envLoader
  }

  readonly property var providerConfig: envLoader.providerConfig
  property var providerOrder: ["local", "openai", "gemini"]
  property var disabledToolServers: []
  property string modelId: envLoader.modelId

  FileView {
    id: leftpanelConfigFile
    path: Qt.resolvedUrl("config.json")
    blockLoading: true
    blockWrites: true
  }

  function providerOrderFromConfig(order) {
    const out = []
    const add = value => {
      const provider = String(value || "").trim()
      if (provider && out.indexOf(provider) < 0)
        out.push(provider)
    }
    if (Array.isArray(order)) {
      for (const provider of order)
        add(provider)
    }
    return out.length > 0 ? out : ["local", "openai", "gemini"]
  }

  function loadPanelConfig() {
    const payload = JsonUtils.parseObject(leftpanelConfigFile.text()) || {}
    root.providerOrder = root.providerOrderFromConfig(payload.provider_order)
    root.disabledToolServers = root.toolServersFromConfig(payload.disabled_tool_servers)
    const lastModel = String(payload.last_model_id || "").trim()
    if (lastModel)
      root.modelId = root.canonicalModelId(lastModel)
  }

  function saveProviderOrder() {
    const payload = JsonUtils.parseObject(leftpanelConfigFile.text())
    if (!payload)
      return
    payload.provider_order = root.providerOrder
    leftpanelConfigFile.setText(JSON.stringify(payload, null, "\t") + "\n")
    leftpanelConfigFile.reload()
  }

  function saveLastModel() {
    const payload = JsonUtils.parseObject(leftpanelConfigFile.text())
    if (!payload)
      return
    payload.last_model_id = root.modelId
    leftpanelConfigFile.setText(JSON.stringify(payload, null, "\t") + "\n")
    leftpanelConfigFile.reload()
  }

  function toolServersFromConfig(servers) {
    const out = []
    const add = value => {
      const server = String(value || "").trim()
      if (server && out.indexOf(server) < 0)
        out.push(server)
    }
    if (Array.isArray(servers)) {
      for (const server of servers)
        add(server)
    }
    return out
  }

  function saveDisabledToolServers() {
    const payload = JsonUtils.parseObject(leftpanelConfigFile.text())
    if (!payload)
      return
    payload.disabled_tool_servers = root.disabledToolServers
    leftpanelConfigFile.setText(JSON.stringify(payload, null, "\t") + "\n")
    leftpanelConfigFile.reload()
  }

  Component.onCompleted: root.loadPanelConfig()

  readonly property color _linkColor: Common.Config.color.primary
  on_LinkColorChanged: chatSession.setAppLinkColor(_linkColor)

  readonly property string currentProvider: {
    const parts = String(modelId || "").split("/")
    return parts.length > 1 ? parts[0] : ""
  }
  readonly property var activeProviderConfig: providerConfig[currentProvider] || ({})
  readonly property bool providerOnline: currentProvider === "local" ? String(activeProviderConfig.base_url || "").trim().length > 0 : String(activeProviderConfig.api_key || "").trim().length > 0

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

  Services.MoodConfig {
    id: moodConfig
  }

  Services.ModelConfig {
    id: modelConfig
    modelBackend: chatSession
    providerOrder: root.providerOrder
  }

  readonly property var availableMoods: moodConfig.availableMoods
  readonly property var moodPrompts: moodConfig.moodPrompts
  readonly property var moodModels: moodConfig.moodModels
  readonly property var availableModels: modelConfig.availableModels
  readonly property var availableProviders: modelConfig.availableProviders
  readonly property var availableTools: root.toolOptions()

  readonly property string currentMoodIcon: moodConfig.moodIcon(root.currentMood)
  readonly property string currentMoodName: moodConfig.moodName(root.currentMood)
  readonly property var currentModel: root.modelEntry(root.modelId)

  readonly property string currentModelLabel: {
    if (root.currentModel)
      return root.currentModel.label
    return root.modelRawId(root.modelId) || root.modelId
  }

  function closePanel() {
    Common.GlobalState.leftPanelVisible = false
  }

  function modelRawId(model) {
    const trimmed = String(model || "").trim()
    if (trimmed.indexOf("/") !== -1)
      return trimmed.split("/").slice(1).join("/")
    return trimmed
  }

  function modelEntry(value) {
    const rawId = root.modelRawId(value)
    const entry = availableModels.find(m => m.rawId === rawId)
    return entry || null
  }

  function canonicalModelId(model) {
    const trimmed = String(model || "").trim()
    if (!trimmed)
      return root.modelId
    const entry = root.modelEntry(trimmed)
    return entry && entry.canonicalId ? entry.canonicalId : trimmed
  }

  function refreshCurrentModelProvider() {
    const next = root.canonicalModelId(root.modelId)
    if (next && next !== root.modelId)
      root.modelId = next
  }

  function openProviderPicker() {
    root.activeCommand = "providers"
    root.showCommandPicker = true
  }

  function openToolPicker() {
    root.activeCommand = "tools"
    root.showCommandPicker = true
  }

  function toolDisabled(serverId) {
    return root.disabledToolServers.indexOf(String(serverId || "").trim()) >= 0
  }

  function toolOptions() {
    const base = [
      {
        value: "provider_search",
        label: "Web grounding",
        description: root.toolDisabled("provider_search") ? "Disabled - models will not be offered hosted web grounding" : "Enabled - supported providers may search and cite the web",
        icon: "\uf349",
        accent: root.toolDisabled("provider_search") ? Common.Config.color.error : Common.Config.color.tertiary,
        recommended: true
      },
      {
        value: "builtin",
        label: "Shell",
        description: root.toolDisabled("builtin") ? "Disabled - shell_command hidden from models" : "Enabled - shell_command available",
        icon: "\uf120",
        accent: root.toolDisabled("builtin") ? Common.Config.color.error : Common.Config.color.secondary,
        recommended: true
      },
      {
        value: "email",
        label: "Email",
        description: root.toolDisabled("email") ? "Disabled - email tools hidden from models" : "Enabled - read-only email tools available",
        icon: "\uf0e0",
        accent: root.toolDisabled("email") ? Common.Config.color.error : Common.Config.color.primary,
        recommended: true
      }
    ]
    return base
  }

  function toggleToolServer(serverId) {
    const server = String(serverId || "").trim()
    if (!server)
      return
    if (root.toolDisabled(server))
      root.disabledToolServers = root.disabledToolServers.filter(value => value !== server)
    else
      root.disabledToolServers = root.disabledToolServers.concat([server])
    root.saveDisabledToolServers()
  }

  function showModelCatalogStatus() {
    const id = "model_catalog"
    chatSession.appendToolStatus(id, "model_catalog", "Model catalog", "model_catalog", "Model catalog", "running", "checking model catalog...", "reading configured local, OpenAI, and Gemini models")
    Qt.callLater(() => {
      chatSession.appendToolStatus(id, "model_catalog", "Model catalog", "model_catalog", "Model catalog", "success", `found ${root.availableModels.length} models`, `${root.availableProviders.length} providers checked`)
    })
  }

  function promoteProvider(providerId) {
    const provider = String(providerId || "").trim()
    if (!provider)
      return
    root.providerOrder = [provider].concat(root.providerOrder.filter(p => p !== provider))
    root.saveProviderOrder()
    root.refreshCurrentModelProvider()
  }

  function moveProviderBefore(providerId, beforeProviderId) {
    const provider = String(providerId || "").trim()
    const before = String(beforeProviderId || "").trim()
    if (!provider || provider === before)
      return
    const ordered = root.providerOrder.filter(p => p !== provider)
    const beforeIndex = before ? ordered.indexOf(before) : -1
    if (beforeIndex >= 0)
      ordered.splice(beforeIndex, 0, provider)
    else
      ordered.push(provider)
    root.providerOrder = ordered
    root.saveProviderOrder()
    root.refreshCurrentModelProvider()
  }

  AiChatSession {
    id: chatSession
    model_id: String(root.modelId)
    system_prompt: root.moodPrompts[root.currentMood] || ""
    provider_config: root.providerConfig
    disabled_tool_servers: root.disabledToolServers

    onOpenModelPickerRequested: {
      root.showModelCatalogStatus()
      root.activeCommand = "model"
      root.showCommandPicker = true
    }
    onOpenMoodPickerRequested: {
      root.activeCommand = "mood"
      root.showCommandPicker = true
    }
    onOpenResumePickerRequested: {
      root.activeCommand = "resume"
      root.showCommandPicker = true
    }
    onOpenProviderPickerRequested: root.openProviderPicker()
    onOpenToolPickerRequested: root.openToolPicker()
    onScrollToEndRequested: panelView.scrollToEnd()
    onStreamDone: root.saveLastModel()
    onCopyAllRequested: function (text) {
      root.setClipboardText(text)
    }
    Component.onCompleted: restoreHistory()
  }

  onModelIdChanged: {
    chatSession.resetForModelSwitch(root.modelId)
    panelView.scrollToEnd()
  }

  onAvailableModelsChanged: root.refreshCurrentModelProvider()

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
    connectionOnline: root.providerOnline
    connectionStatus: root.providerOnline ? "online" : "offline"
    showCommandPicker: root.showCommandPicker
    activeCommand: root.activeCommand
    availableModels: root.availableModels
    availableProviders: root.availableProviders
    availableTools: root.availableTools
    availableMoods: root.availableMoods
    resumeConversations: chatSession.resume_conversations

    footerDotColor: panelView.currentTabIndex === 0 ? (root.providerOnline ? Common.Config.color.tertiary : Common.Config.color.error) : (panelView.metricsHealthy ? Common.Config.color.tertiary : Common.Config.color.secondary)
    footerLeftText: panelView.currentTabIndex === 0 ? ("MODEL: " + root.currentModelLabel.toUpperCase()) : ("UPTIME: " + panelView.metricsUptime)
    footerRightText: panelView.currentTabIndex === 0 ? ("PROVIDER: " + root.currentProvider.toUpperCase()) : (panelView.metricsHealthy ? "HEALTH: OK" : "HEALTH: WARN")

    onCloseRequested: root.closePanel()
    onTabSelected: index => panelView.currentTabIndex = index
    onSendRequested: function (text, attachments) {
      if (!attachments || attachments.length === 0)
        chatSession.submitInput(text)
      else
        chatSession.submitInputWithAttachments(text, attachments)
    }
    onCommandTriggered: command => chatSession.submitInput(command)
    onRegenerateRequested: messageId => chatSession.regenerate(messageId)
    onDeleteRequested: messageId => chatSession.deleteMessage(messageId)
    onEditRequested: (messageId, newContent) => chatSession.editMessage(messageId, newContent)

    onDismissCommandPickerRequested: root.showCommandPicker = false

    onModelSelected: value => {
      root.modelId = root.canonicalModelId(value)
      root.showCommandPicker = false
    }

    onProviderSelected: value => {
      root.promoteProvider(value)
      chatSession.appendInfo(`Provider priority: ${root.providerOrder.join(" -> ")}`)
    }

    onProviderMoved: (value, beforeValue) => {
      root.moveProviderBefore(value, beforeValue)
      chatSession.appendInfo(`Provider priority: ${root.providerOrder.join(" -> ")}`)
    }

    onToolToggled: value => root.toggleToolServer(value)

    onMoodSelected: value => {
      root.currentMood = value
      const newModel = root.moodModels[value]
      if (newModel && root.canonicalModelId(newModel) !== root.modelId)
        root.modelId = root.canonicalModelId(newModel)
      chatSession.appendInfo(`Mood: ${value}`)
      root.showCommandPicker = false
      panelView.scrollToEnd()
    }

    onResumeSelected: value => {
      if (chatSession.resumeConversation(value)) {
        root.showCommandPicker = false
        panelView.scrollToEnd()
      }
    }

    onResumeSearchChanged: query => chatSession.refreshResumeConversations(query)
  }
}

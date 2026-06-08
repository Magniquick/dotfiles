pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../../common" as Common
import "../../common/JsonUtils.js" as JsonUtils

Item {
  id: root
  visible: false

  property url configFileUrl: Qt.resolvedUrl("../models.json")
  property var providerConfig: ({})

  FileView {
    id: configFile
    path: root.configFileUrl
    blockLoading: true
  }

  readonly property var modelsData: {
    const payload = JsonUtils.parseObject(configFile.text())
    return payload && Array.isArray(payload.models) ? payload.models : []
  }

  readonly property var defaultCapabilities: ({
      supports_images: true,
      supports_tools: true,
      supports_multimodal: true
    })

  readonly property var availableModels: modelsData.map(m => {
    const providerId = String(m.provider || "").trim()
    const rawId = String(m.raw_id || "").trim()
    const value = providerId && rawId ? providerId + "/" + rawId : ""
    const providerEntry = root.providerConfig[providerId] || {}
    const enabled = providerId === "test" || String(providerEntry.api_key || "").length > 0
    const providerLabel = m.provider_label || providerId
    const label = m.label || rawId || value
    const capabilities = m.capabilities || root.defaultCapabilities

    return {
      value,
      label,
      description: m.description || "",
      recommended: m.recommended !== false,
      provider: providerId,
      capabilities,
      rawId,
      providerLabel,
      enabled,
      model: {
        id: value,
        raw_id: rawId,
        provider: providerId,
        label,
        description: m.description || "",
        recommended: m.recommended !== false,
        capabilities
      },
      providerEntry: {
        id: providerId,
        label: providerLabel,
        enabled
      },
      iconImage: providerId === "gemini" ? "./assets/Google_Gemini_icon_2025.svg.png" : "./assets/OpenAI-white-monoblossom.svg",
      accent: providerId === "gemini" ? Common.Config.color.primary : Common.Config.color.tertiary
    }
  }).filter(m => m.value.length > 0)
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import "../../common" as Common
import "../../common/JsonUtils.js" as JsonUtils

Item {
  id: root
  visible: false

  property url configFileUrl: Qt.resolvedUrl("../models.json")
  property var modelBackend: null
  property var providerOrder: ["local", "openai", "gemini"]

  FileView {
    id: configFile
    path: root.configFileUrl
    blockLoading: true
  }

  readonly property var modelsData: {
    const payload = JsonUtils.parseObject(configFile.text())
    return payload && Array.isArray(payload.models) ? payload.models : []
  }

  function accentColor(role) {
    if (role === "primary")
      return Common.Config.color.primary
    if (role === "secondary")
      return Common.Config.color.secondary
    return Common.Config.color.tertiary
  }

  function withAccent(items) {
    return (items || []).map(item => Object.assign({}, item, {
          accent: root.accentColor(item.accentRole)
        }))
  }

  readonly property var catalog: root.modelBackend && root.modelBackend.modelCatalog
    ? root.modelBackend.modelCatalog(root.modelsData, root.providerOrder)
    : ({ models: [], providers: [] })

  readonly property var availableModels: root.withAccent(root.catalog.models)
  readonly property var availableProviders: root.withAccent(root.catalog.providers)
}

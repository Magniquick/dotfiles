pragma ComponentBehavior: Bound
import QtQuick
import qsgo

Item {
  id: root
  visible: false

  ConfigResolver {
    id: configResolver
    Component.onCompleted: refresh()
  }

  readonly property var envVars: configResolver.values

  readonly property string openaiApiKey: envVars["OPENAI_API_KEY"] || ""
  readonly property string geminiApiKey: envVars["GEMINI_API_KEY"] || ""
  readonly property string localApiKey: envVars["LOCAL_API_KEY"] || ""
  readonly property string openaiBaseUrl: envVars["OPENAI_BASE_URL"] || ""
  readonly property string localBaseUrl: envVars["LOCAL_BASE_URL"] || "http://127.0.0.1:8317/v1"

  function canonicalModelId(rawId) {
    const trimmed = String(rawId || "").trim()
    if (!trimmed)
      return "local/gpt-5.4-mini"
    if (trimmed.indexOf("/") !== -1)
      return trimmed
    if (trimmed === "test")
      return "test/test"
    if (trimmed.startsWith("gpt-5."))
      return "local/" + trimmed
    return trimmed.startsWith("gemini-") ? ("gemini/" + trimmed) : ("openai/" + trimmed)
  }

  readonly property var providerConfig: ({
      local: {
        api_key: localApiKey,
        base_url: localBaseUrl
      },
      openai: {
        api_key: openaiApiKey,
        base_url: openaiBaseUrl
      },
      gemini: {
        api_key: geminiApiKey
      },
      test: {
        api_key: "test"
      }
    })

  // Default model when leftpanel/config.toml does not set one.
  readonly property string modelId: canonicalModelId(envVars["OPENAI_MODEL"] || "local/gpt-5.4-mini")
}

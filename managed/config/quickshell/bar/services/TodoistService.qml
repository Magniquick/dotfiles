pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../common/JsonUtils.js" as JsonUtils
import qsnative

Item {
  id: root
  visible: false

  readonly property string todoistCachePath: Quickshell.cachePath("todoist/tasks_cache.json")

  property var payload: ({})
  property string lastUpdatedLabel: ""
  property bool loading: false
  property bool parseError: false
  property string error: ""
  property bool usingCache: false
  property string lastRefreshReason: "startup"
  property string syncedAt: ""
  property double syncedAtMs: 0
  readonly property int viewRefreshStaleMs: 60000

  function shouldPreferCache(reason) {
    return false
  }

  function shouldRefreshView() {
    if (root.loading)
      return false
    if (root.usingCache)
      return true
    if (!root.syncedAtMs || !isFinite(root.syncedAtMs))
      return true

    return (Date.now() - root.syncedAtMs) >= root.viewRefreshStaleMs
  }

  function refresh(reason) {
    root.lastRefreshReason = String(reason || "unknown")
    client.prefer_cache = root.shouldPreferCache(root.lastRefreshReason)
    client.refresh()
  }

  function completeTask(id) {
    root.lastRefreshReason = "action"
    client.prefer_cache = false
    client.action("close", JSON.stringify({
      id: String(id)
    }))
  }

  function deleteTask(id) {
    root.lastRefreshReason = "action"
    client.prefer_cache = false
    client.action("delete", JSON.stringify({
      id: String(id)
    }))
  }

  function addTask(content, projectId, description, dueString) {
    root.lastRefreshReason = "action"
    client.prefer_cache = false
    const args = {
      content: String(content || "")
    }
    if (projectId)
      args.project_id = String(projectId)
    if (description)
      args.description = String(description)
    if (dueString)
      args.due_string = String(dueString)
    client.action("add", JSON.stringify(args))
  }

  function updateTask(id, content, description, dueString) {
    root.lastRefreshReason = "action"
    client.prefer_cache = false
    const args = {
      id: String(id || "")
    }
    if (content)
      args.content = String(content)
    if (description)
      args.description = String(description)
    if (dueString)
      args.due_string = String(dueString)
    client.action("update", JSON.stringify(args))
  }

  TodoistClient {
    id: client
    cache_path: String(root.todoistCachePath)
    prefer_cache: false
  }

  Timer {
    interval: 300000 // 5 minutes
    repeat: true
    running: true
    triggeredOnStart: true

    onTriggered: root.refresh("timer")
  }

  Connections {
    target: client

    function onLoadingChanged() {
      root.loading = client.loading
    }

    function onErrorChanged() {
      root.error = client.error || ""
      root.parseError = root.error !== ""
    }

    function onDataChanged() {
      const parsed = JsonUtils.parseObject(client.data || "")
      if (!parsed) {
        root.parseError = true
        root.error = "Failed to parse todoist payload"
        console.log("[TodoistService] parse error: invalid payload")
        return
      }
      root.payload = parsed
      root.usingCache = parsed.using_cache === true
      root.error = parsed.error ? String(parsed.error) : ""
      root.parseError = root.error !== ""
      root.syncedAt = parsed.synced_at ? String(parsed.synced_at) : ""

      const syncedAt = root.syncedAt ? new Date(root.syncedAt) : null
      root.syncedAtMs = syncedAt && !isNaN(syncedAt.getTime()) ? syncedAt.getTime() : 0

      const source = root.usingCache ? "cache" : "live"
      const status = root.error ? (" (error: " + root.error + ")") : ""
      console.log("[TodoistService] refresh=" + root.lastRefreshReason + " preferCache=" + client.prefer_cache + " source=" + source + " syncedAt=" + (root.syncedAt || "none") + " cachePath=" + root.todoistCachePath + status)

      const updatedAt = parsed.last_updated ? new Date(parsed.last_updated) : null
      if (updatedAt && !isNaN(updatedAt.getTime()))
        root.lastUpdatedLabel = Qt.formatDateTime(updatedAt, "hh:mm ap")
    }

    function onLast_updatedChanged() {
      const ts = client.last_updated
      if (!ts)
        return
      const d = new Date(ts)
      if (!isNaN(d.getTime()))
        root.lastUpdatedLabel = Qt.formatDateTime(d, "hh:mm ap")
    }
  }
}

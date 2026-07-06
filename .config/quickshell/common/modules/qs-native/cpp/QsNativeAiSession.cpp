#include "QsNativeAiSession.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QBuffer>
#include <QClipboard>
#include <QDateTime>
#include <QGuiApplication>
#include <QIODevice>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeData>
#include <QPalette>
#include <QThreadPool>
#include <QUuid>
#include <algorithm>

namespace {

auto jsonStringValue(const QJsonObject& object, const QString& key) -> QString {
  const QJsonValue value = object.value(key);
  if (value.isString()) {
    return value.toString().trimmed();
  }
  if (value.isDouble()) {
    return QString::number(value.toDouble());
  }
  if (value.isBool()) {
    return value.toBool() ? QStringLiteral("true") : QStringLiteral("false");
  }
  return {};
}

} // namespace

// ── QAbstractListModel ────────────────────────────────────────────────────────

QsNativeAiSession::QsNativeAiSession(QObject* parent) : QAbstractListModel(parent) {}

namespace {

[[nodiscard]] auto rowCountAsInt(qsizetype size) -> int {
  return static_cast<int>(size);
}

} // namespace

void QsNativeAiSession::setAppLinkColor(const QColor& color) {
  QPalette pal = QGuiApplication::palette();
  pal.setColor(QPalette::Link, color);
  QGuiApplication::setPalette(pal);
}

auto QsNativeAiSession::rowCount(const QModelIndex& parent) const -> int {
  if (parent.isValid()) {
    return 0;
  }
  return rowCountAsInt(m_messages.size());
}

auto QsNativeAiSession::data(const QModelIndex& index, int role) const -> QVariant {
  if (!index.isValid() || index.row() < 0 || index.row() >= m_messages.size()) {
    return {};
  }
  const Message& msg = m_messages.at(index.row());
  switch (role) {
    case IdRole:
      return msg.id;
    case SenderRole:
      return msg.sender;
    case BodyRole:
      return msg.body;
    case KindRole:
      return msg.kind;
    case MetricsRole:
      return msg.metrics;
    case AttachmentsRole:
      return msg.attachments;
    case ToolRole:
      return msg.tool;
    case ShowHeaderRole:
      return msg.showHeader;
    default:
      return {};
  }
}

auto QsNativeAiSession::roleNames() const -> QHash<int, QByteArray> {
  return {
      {IdRole, "messageId"}, {SenderRole, "sender"},         {BodyRole, "body"},
      {KindRole, "kind"},    {MetricsRole, "metrics"},       {AttachmentsRole, "attachments"},
      {ToolRole, "tool"},    {ShowHeaderRole, "showHeader"},
  };
}

// ── Property setters ──────────────────────────────────────────────────────────

void QsNativeAiSession::setModelId(const QString& v) {
  if (v != m_modelId) {
    m_modelId = v;
    emit modelIdChanged();
  }
}

void QsNativeAiSession::setSystemPrompt(const QString& v) {
  if (v != m_systemPrompt) {
    m_systemPrompt = v;
    emit systemPromptChanged();
  }
}

void QsNativeAiSession::setProviderConfig(const QVariantMap& v) {
  if (v != m_providerConfig) {
    m_providerConfig = v;
    emit providerConfigChanged();
  }
}

void QsNativeAiSession::setDisabledToolServers(const QVariantList& v) {
  if (v != m_disabledToolServers) {
    m_disabledToolServers = v;
    emit disabledToolServersChanged();
  }
}

void QsNativeAiSession::setBusy(bool v) {
  if (v != m_busy) {
    m_busy = v;
    emit busyChanged();
  }
}

void QsNativeAiSession::setStatus(const QString& v) {
  if (v != m_status) {
    m_status = v;
    emit statusChanged();
  }
}

void QsNativeAiSession::setError(const QString& v) {
  if (v != m_error) {
    m_error = v;
    emit errorChanged();
  }
}

// ── Invokables ────────────────────────────────────────────────────────────────

void QsNativeAiSession::submitInput(const QString& text) {
  const QString trimmed = text.trimmed();
  if (trimmed.isEmpty()) {
    return;
  }

  if (trimmed.startsWith('/')) {
    handleSlashCommand(trimmed.toLower());
    return;
  }
  if (m_busy) {
    return;
  }
  startStream(trimmed, QVariantList{});
}

void QsNativeAiSession::submitInputWithAttachments(const QString& text,
                                                   const QVariantList& attachments) {
  if (m_busy) {
    return;
  }
  startStream(text.trimmed(), attachments);
}

void QsNativeAiSession::startStream(const QString& text, const QVariantList& attachments) {
  if (!ensureHistoryConversation()) {
    setError(QStringLiteral("Failed to open conversation history"));
    return;
  }

  const QByteArray providerConfigJson = buildProviderConfigJson();
  const QByteArray attachmentsJson =
      QJsonDocument::fromVariant(attachments).toJson(QJsonDocument::Compact);
  const QByteArray disabledToolServersJson =
      QJsonDocument::fromVariant(m_disabledToolServers).toJson(QJsonDocument::Compact);

  // Append user message.
  const int userRow = rowCountAsInt(m_messages.size());
  beginInsertRows({}, userRow, userRow);
  m_messages.append({QUuid::createUuid().toString(QUuid::WithoutBraces), "user", text, "chat",
                     QVariantMap{}, attachments, QVariantMap{}, true});
  endInsertRows();
  m_currentTurnId = m_messages.at(userRow).id;
  m_currentTurnOrdinal = userRow;
  m_nextReplayItemOrdinal = 0;
  persistMessageAt(userRow, QStringLiteral("complete"), utcNow());

  // Append empty assistant message (filled by tokens).
  const int asstRow = rowCountAsInt(m_messages.size());
  beginInsertRows({}, asstRow, asstRow);
  m_messages.append({QUuid::createUuid().toString(QUuid::WithoutBraces), "assistant", QString(),
                     "chat", QVariantMap{}, QVariantList{}, QVariantMap{}, true});
  endInsertRows();
  persistMessageAt(asstRow, QStringLiteral("streaming"));

  emit scrollToEndRequested();

  setBusy(true);
  setError(QString());
  setStatus(QStringLiteral("Streaming..."));

  m_sessionId = QsNative_AiChat_Stream(
      m_modelId.toUtf8().constData(), providerConfigJson.constData(),
      m_systemPrompt.toUtf8().constData(), m_conversationId.toUtf8().constData(),
      text.toUtf8().constData(), attachmentsJson.constData(), disabledToolServersJson.constData(),
      &QsNativeAiSession::tokenCallback, this);
}

void QsNativeAiSession::cancel() {
  if (m_sessionId >= 0) {
    QsNative_AiChat_Cancel(m_sessionId);
    m_sessionId = -1;
  }
  m_currentTurnId.clear();
  m_currentTurnOrdinal = -1;
  m_nextReplayItemOrdinal = 0;
  const int row = lastAssistantChatIndex();
  if (row >= 0) {
    persistMessageAt(row, QStringLiteral("complete"), utcNow());
  }
  setBusy(false);
  setStatus(QStringLiteral("Cancelled"));
}

void QsNativeAiSession::regenerate(const QString& messageId) {
  if (m_busy) {
    return;
  }

  // Find the assistant message and the user message before it.
  int const asstIdx = indexOfMessage(messageId);
  if (asstIdx < 0) {
    return;
  }

  // Look backwards for the last user message.
  int userIdx = -1;
  for (int i = asstIdx - 1; i >= 0; --i) {
    if (m_messages.at(i).sender == QStringLiteral("user")) {
      userIdx = i;
      break;
    }
  }
  if (userIdx < 0) {
    return;
  }

  const QString userText = m_messages.at(userIdx).body;
  const QVariantList userAttachments = m_messages.at(userIdx).attachments;
  persistDeletedFromOrdinal(userIdx);

  // Remove from userIdx onwards.
  beginRemoveRows({}, userIdx, rowCountAsInt(m_messages.size()) - 1);
  while (m_messages.size() > userIdx) {
    m_messages.removeLast();
  }
  endRemoveRows();

  startStream(userText, userAttachments);
}

void QsNativeAiSession::deleteMessage(const QString& messageId) {
  const int idx = indexOfMessage(messageId);
  if (idx < 0) {
    return;
  }
  const QVariantMap result =
      qsn::takeObject(QsNative_AiHistory_MarkMessageDeleted(messageId.toUtf8().constData()));
  Q_UNUSED(result);
  if (m_currentTurnOrdinal == idx) {
    m_currentTurnId.clear();
    m_currentTurnOrdinal = -1;
    m_nextReplayItemOrdinal = 0;
  } else if (m_currentTurnOrdinal > idx) {
    --m_currentTurnOrdinal;
  }
  beginRemoveRows({}, idx, idx);
  m_messages.removeAt(idx);
  endRemoveRows();
}

void QsNativeAiSession::editMessage(const QString& messageId, const QString& newBody) {
  const int idx = indexOfMessage(messageId);
  if (idx < 0) {
    return;
  }
  m_messages[idx].body = newBody;
  const QModelIndex mi = index(idx, 0);
  emit dataChanged(mi, mi, {BodyRole});
  persistMessageAt(idx, QStringLiteral("complete"));
}

void QsNativeAiSession::resetForModelSwitch(const QString& newModelId) {
  closeHistoryConversation();
  if (!m_messages.isEmpty()) {
    beginRemoveRows({}, 0, rowCountAsInt(m_messages.size()) - 1);
    m_messages.clear();
    endRemoveRows();
  }
  m_currentTurnId.clear();
  m_currentTurnOrdinal = -1;
  m_nextReplayItemOrdinal = 0;
  setModelId(newModelId);
  if (m_busy) {
    cancel();
  }
  setBusy(false);
  setError(QString());
  setStatus(QString());
}

void QsNativeAiSession::appendInfo(const QString& text) {
  ensureHistoryConversation();
  const int row = rowCountAsInt(m_messages.size());
  beginInsertRows({}, row, row);
  m_messages.append({QUuid::createUuid().toString(QUuid::WithoutBraces), "assistant", text, "info",
                     QVariantMap{}, QVariantList{}, QVariantMap{}, true});
  endInsertRows();
  persistMessageAt(row, QStringLiteral("complete"), utcNow());
  emit scrollToEndRequested();
}

void QsNativeAiSession::appendToolStatus(const QString& toolCallId, const QString& toolName,
                                         const QString& toolTitle, const QString& serverId,
                                         const QString& serverLabel, const QString& status,
                                         const QString& summary, const QString& subtitle) {
  const bool running = status == QStringLiteral("running");
  const bool error = status == QStringLiteral("error");
  const QVariantMap event{
      {QStringLiteral("kind"), QStringLiteral("tool")},
      {QStringLiteral("phase"),
       running ? QStringLiteral("tool_start")
               : (error ? QStringLiteral("tool_error") : QStringLiteral("tool_done"))},
      {QStringLiteral("tool_call_id"), toolCallId},
      {QStringLiteral("tool_name"), toolName},
      {QStringLiteral("tool_title"), toolTitle},
      {QStringLiteral("server_id"), serverId},
      {QStringLiteral("server_label"), serverLabel},
      {QStringLiteral("status"), running ? QStringLiteral("running") : status},
      {QStringLiteral("summary"), summary},
      {QStringLiteral("subtitle"), subtitle},
      {QStringLiteral("is_error"), error},
      {QStringLiteral("read_only"), true},
      {QStringLiteral("risk"), QStringLiteral("read")},
  };
  const QByteArray json = QJsonDocument::fromVariant(event).toJson(QJsonDocument::Compact);
  handleToolEventJson(QString::fromUtf8(json));
}

auto QsNativeAiSession::copyAllText() const -> QString {
  QStringList parts;
  for (const Message& msg : m_messages) {
    if (msg.kind == QStringLiteral("info") || msg.kind == QStringLiteral("tool")) {
      continue;
    }
    parts << (msg.sender == QStringLiteral("user") ? QStringLiteral("You: ")
                                                   : QStringLiteral("Assistant: ")) +
                 msg.body;
  }
  return parts.join(QStringLiteral("\n\n"));
}

auto QsNativeAiSession::pasteImageFromClipboard() -> QVariantList {
  const QClipboard* cb = QGuiApplication::clipboard();
  const QMimeData* mime = cb->mimeData();
  if ((mime == nullptr) || !mime->hasImage()) {
    return {};
  }

  const QImage img = cb->image();
  if (img.isNull()) {
    return {};
  }

  QByteArray ba;
  QBuffer buf(&ba);
  buf.open(QIODevice::WriteOnly);
  img.save(&buf, "PNG");
  buf.close();

  return QVariantList{QVariantMap{
      {QStringLiteral("mime"), QStringLiteral("image/png")},
      {QStringLiteral("b64"), QString::fromLatin1(ba.toBase64())},
  }};
}

auto QsNativeAiSession::pasteAttachmentFromClipboard() -> QVariantList {
  const QClipboard* cb = QGuiApplication::clipboard();
  const QMimeData* mime = cb->mimeData();
  if (mime == nullptr) {
    return {};
  }

  if (mime->hasUrls()) {
    QVariantList out;
    for (const QUrl& url : mime->urls()) {
      if (!url.isLocalFile()) {
        continue;
      }
      out.append(QVariantMap{{QStringLiteral("path"), url.toLocalFile()}});
    }
    if (!out.isEmpty()) {
      return out;
    }
  }
  return {};
}

// ── Command catalog ───────────────────────────────────────────────────────────

auto QsNativeAiSession::commands() -> QVariantList {
  return QVariantList{
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/model")},
                  {QStringLiteral("description"), QStringLiteral("Change model")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/providers")},
                  {QStringLiteral("description"), QStringLiteral("Order provider priority")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/mood")},
                  {QStringLiteral("description"), QStringLiteral("Change mood / persona")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/resume")},
                  {QStringLiteral("description"), QStringLiteral("Resume previous chat")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/clear")},
                  {QStringLiteral("description"), QStringLiteral("Clear chat history")}},
      QVariantMap{
          {QStringLiteral("name"), QStringLiteral("/copy")},
          {QStringLiteral("description"), QStringLiteral("Copy all messages to clipboard")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/status")},
                  {QStringLiteral("description"), QStringLiteral("Show model & connection info")}},
      QVariantMap{
          {QStringLiteral("name"), QStringLiteral("/mcp")},
          {QStringLiteral("description"), QStringLiteral("Show MCP server and tool status")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/tools")},
                  {QStringLiteral("description"), QStringLiteral("Enable or disable tools")}},
      QVariantMap{
          {QStringLiteral("name"), QStringLiteral("/debug")},
          {QStringLiteral("description"), QStringLiteral("Show detailed session diagnostics")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/help")},
                  {QStringLiteral("description"), QStringLiteral("Show available commands")}},
  };
}

// ── Slash commands ────────────────────────────────────────────────────────────

void QsNativeAiSession::handleSlashCommand(const QString& cmd) {
  if (cmd == QStringLiteral("/clear")) {
    closeHistoryConversation();
    if (!m_messages.isEmpty()) {
      beginRemoveRows({}, 0, rowCountAsInt(m_messages.size()) - 1);
      m_messages.clear();
      endRemoveRows();
    }
  } else if (cmd == QStringLiteral("/model")) {
    emit openModelPickerRequested();
  } else if (cmd == QStringLiteral("/providers")) {
    emit openProviderPickerRequested();
  } else if (cmd == QStringLiteral("/tools")) {
    refreshMcp();
    emit openToolPickerRequested();
  } else if (cmd == QStringLiteral("/mood")) {
    emit openMoodPickerRequested();
  } else if (cmd == QStringLiteral("/resume")) {
    if (m_busy) {
      appendInfo(QStringLiteral("Cannot resume while a response is streaming."));
      return;
    }
    refreshResumeConversations(QString());
    emit openResumePickerRequested();
  } else if (cmd.startsWith(QStringLiteral("/copy"))) {
    const QString text = copyAllText();
    emit copyAllRequested(text);
  } else if (cmd == QStringLiteral("/help")) {
    appendInfo(QStringLiteral("**Commands**\n\n"
                              "| Command | Description |\n"
                              "|---|---|\n"
                              "| `/model` | Change model |\n"
                              "| `/providers` | Order provider priority |\n"
                              "| `/mood` | Change mood / persona |\n"
                              "| `/resume` | Resume previous chat |\n"
                              "| `/clear` | Clear chat history |\n"
                              "| `/copy` | Copy all messages to clipboard |\n"
                              "| `/status` | Show model & connection info |\n"
                              "| `/mcp` | Show MCP server and tool status |\n"
                              "| `/tools` | Enable or disable tools |\n"
                              "| `/debug` | Show detailed session diagnostics |\n"
                              "| `/help` | Show this message |"));
  } else if (cmd == QStringLiteral("/mcp")) {
    const int connectedCount = static_cast<int>(std::count_if(
        m_mcpServers.cbegin(), m_mcpServers.cend(), [](const QVariant& value) -> bool {
          return value.toMap().value(QStringLiteral("connected")).toBool();
        }));
    appendInfo(QStringLiteral("**MCP**\n\n"
                              "- **Servers:** %1 total  •  %2 connected\n"
                              "- **Tools:** %3\n"
                              "- **Status:** %4%5")
                   .arg(m_mcpServers.size())
                   .arg(connectedCount)
                   .arg(m_mcpTools.size())
                   .arg(m_mcpStatus.isEmpty() ? QStringLiteral("(unknown)") : m_mcpStatus)
                   .arg(m_mcpError.isEmpty()
                            ? QString()
                            : QStringLiteral("\n- **Error:** %1").arg(m_mcpError)));
  } else if (cmd == QStringLiteral("/status")) {
    const QString providerId = activeProviderId();
    const QString provider = providerId.isEmpty()
                                 ? QStringLiteral("(unknown)")
                                 : (providerId.left(1).toUpper() + providerId.mid(1));
    const QVariantMap config = activeProviderConfig();
    const bool hasKey = !config.value(QStringLiteral("api_key")).toString().isEmpty();
    const QString keyStatus = hasKey ? QStringLiteral("✓ set") : QStringLiteral("✗ not set");
    const QString baseUrl = config.value(QStringLiteral("base_url")).toString().isEmpty()
                                ? QStringLiteral("(default)")
                                : config.value(QStringLiteral("base_url")).toString();
    const QString prompt =
        m_systemPrompt.isEmpty()
            ? QStringLiteral("(none)")
            : (m_systemPrompt.length() > 120 ? m_systemPrompt.left(120) + QStringLiteral("…")
                                             : m_systemPrompt);
    appendInfo(QStringLiteral("**Status**\n\n"
                              "- **Model:** %1\n"
                              "- **Provider:** %2  •  API key: %3\n"
                              "- **Base URL:** %4\n"
                              "- **MCP:** %5 servers  •  %6 tools\n"
                              "- **Mood prompt:** %7")
                   .arg(m_modelId.isEmpty() ? QStringLiteral("(none)") : m_modelId)
                   .arg(provider)
                   .arg(keyStatus)
                   .arg(baseUrl)
                   .arg(m_mcpServers.size())
                   .arg(m_mcpTools.size())
                   .arg(prompt));
  } else if (cmd == QStringLiteral("/debug")) {
    const QString providerId = activeProviderId();
    const QString provider = providerId.isEmpty()
                                 ? QStringLiteral("(unknown)")
                                 : (providerId.left(1).toUpper() + providerId.mid(1));
    const QVariantMap activeConfig = activeProviderConfig();
    const QString activeKey = activeConfig.value(QStringLiteral("api_key")).toString();
    const QString keyPreview = activeKey.isEmpty() ? QStringLiteral("✗ not set")
                                                   : QStringLiteral("✓ %1…").arg(activeKey.left(8));
    const QVariantMap geminiConfig = m_providerConfig.value(QStringLiteral("gemini")).toMap();
    const QVariantMap openaiConfig = m_providerConfig.value(QStringLiteral("openai")).toMap();
    const QString geminiKeyPreview =
        geminiConfig.value(QStringLiteral("api_key")).toString().isEmpty()
            ? QStringLiteral("✗ not set")
            : QStringLiteral("✓ %1…").arg(
                  geminiConfig.value(QStringLiteral("api_key")).toString().left(8));
    const QString openaiKeyPreview =
        openaiConfig.value(QStringLiteral("api_key")).toString().isEmpty()
            ? QStringLiteral("✗ not set")
            : QStringLiteral("✓ %1…").arg(
                  openaiConfig.value(QStringLiteral("api_key")).toString().left(8));
    int chatCount = 0;
    int infoCount = 0;
    for (const Message& msg : m_messages) {
      if (msg.kind == QStringLiteral("chat")) {
        ++chatCount;
      } else {
        ++infoCount;
      }
    }
    const QString prompt =
        m_systemPrompt.isEmpty()
            ? QStringLiteral("(none)")
            : (m_systemPrompt.length() > 80 ? m_systemPrompt.left(80) + QStringLiteral("…")
                                            : m_systemPrompt);
    const QString baseUrl = activeConfig.value(QStringLiteral("base_url")).toString().isEmpty()
                                ? QStringLiteral("(default)")
                                : activeConfig.value(QStringLiteral("base_url")).toString();

    // Pull last-stream metrics from the native backend.
    QString metricsSection = QStringLiteral("*(no stream yet)*");
    {
      const QJsonDocument doc = qsn::takeDoc(QsNative_AiChat_LastMetrics());
      if (doc.isObject()) {
        const QJsonObject o = doc.object();
        const double ttf = o["ttf_ms"].toDouble(-1);
        const double total = o["total_ms"].toDouble(0);
        const int chunks = o["chunk_count"].toInt(0);
        const int ptok = o["prompt_tokens"].toInt(0);
        const int otok = o["output_tokens"].toInt(0);
        const bool fin = o["finished"].toBool(false);
        const QString errStr = o["error"].toString();
        const QString lastModel = o["model"].toString();

        const QString ttfStr = ttf < 0 ? QStringLiteral("—")
                                       : QStringLiteral("%1 ms").arg(QString::number(ttf, 'f', 0));
        const QString totStr = QStringLiteral("%1 ms").arg(QString::number(total, 'f', 0));
        const QString tokStr =
            ptok > 0 || otok > 0
                ? QStringLiteral("%1 in / %2 out").arg(ptok).arg(otok)
                : QStringLiteral("%1 chunks (provider didn't report tokens)").arg(chunks);
        const QString status =
            fin ? QStringLiteral("✓ completed")
                : (errStr.isEmpty() ? QStringLiteral("✗ cancelled") : QStringLiteral("✗ error"));

        metricsSection = QStringLiteral("- Model: `%1`  •  %2\n"
                                        "- TTFT: %3  •  Total: %4\n"
                                        "- Tokens: %5")
                             .arg(lastModel)
                             .arg(status)
                             .arg(ttfStr)
                             .arg(totStr)
                             .arg(tokStr);

        if (!errStr.isEmpty()) {
          metricsSection += QStringLiteral("\n- Error: %1").arg(errStr);
        }
      }
    }

    appendInfo(QStringLiteral("**Debug**\n\n"
                              "**Model & connection**\n"
                              "- Model: `%1`  •  Provider: %2\n"
                              "- Active key: %3\n"
                              "- Gemini key: %4\n"
                              "- OpenAI key: %5\n"
                              "- Base URL: %6\n"
                              "- MCP status: %7  •  Servers: %8  •  Tools: %9\n\n"
                              "**Session**\n"
                              "- Messages: %10 chat + %11 info\n"
                              "- Busy: %12  •  Session ID: %13\n\n"
                              "**Last stream**\n"
                              "%14\n\n"
                              "**System prompt**\n"
                              "%15")
                   .arg(m_modelId.isEmpty() ? QStringLiteral("(none)") : m_modelId)
                   .arg(provider)
                   .arg(keyPreview)
                   .arg(geminiKeyPreview)
                   .arg(openaiKeyPreview)
                   .arg(baseUrl)
                   .arg(m_mcpStatus.isEmpty() ? QStringLiteral("(unknown)") : m_mcpStatus)
                   .arg(m_mcpServers.size())
                   .arg(m_mcpTools.size())
                   .arg(chatCount)
                   .arg(infoCount)
                   .arg(m_busy ? QStringLiteral("yes") : QStringLiteral("no"))
                   .arg(m_sessionId)
                   .arg(metricsSection)
                   .arg(prompt));
  } else {
    appendInfo(QStringLiteral("Unknown command: %1\nType /help for available commands.").arg(cmd));
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

auto QsNativeAiSession::restoreHistory() -> bool {
  if (m_historyLoaded) {
    return true;
  }

  const QVariantMap result = qsn::takeObject(QsNative_AiHistory_Restore(
      m_modelId.toUtf8().constData(), activeProviderId().toUtf8().constData(),
      m_systemPrompt.toUtf8().constData()));
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }

  const QVariantMap conv = result.value(QStringLiteral("conversation")).toMap();
  m_conversationId = conv.value(QStringLiteral("id")).toString();
  restoreMessages(result.value(QStringLiteral("messages")).toList());
  m_historyLoaded = true;
  return true;
}

auto QsNativeAiSession::ensureHistoryConversation() -> bool {
  if (!m_conversationId.isEmpty()) {
    return true;
  }
  if (!restoreHistory()) {
    return false;
  }
  if (!m_conversationId.isEmpty()) {
    return true;
  }
  return createHistoryConversation();
}

auto QsNativeAiSession::createHistoryConversation() -> bool {
  const QVariantMap result = qsn::takeObject(QsNative_AiHistory_Create(
      m_modelId.toUtf8().constData(), activeProviderId().toUtf8().constData(),
      m_systemPrompt.toUtf8().constData()));
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }
  const QVariantMap conv = result.value(QStringLiteral("conversation")).toMap();
  m_conversationId = conv.value(QStringLiteral("id")).toString();
  m_currentTurnId.clear();
  m_currentTurnOrdinal = -1;
  m_nextReplayItemOrdinal = 0;
  m_historyLoaded = true;
  return !m_conversationId.isEmpty();
}

auto QsNativeAiSession::refreshResumeConversations(const QString& query) -> bool {
  const QVariantMap result = qsn::takeObject(QsNative_AiHistory_ListResume(
      m_modelId.toUtf8().constData(), activeProviderId().toUtf8().constData(),
      m_conversationId.toUtf8().constData(), query.toUtf8().constData(), 50));
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }

  QVariantList options;
  const QVariantList summaries = result.value(QStringLiteral("conversations")).toList();
  for (const QVariant& item : summaries) {
    const QVariantMap option = resumeOptionFromSummary(item.toMap());
    if (!option.isEmpty()) {
      options.append(option);
    }
  }
  m_resumeConversations = options;
  emit resumeConversationsChanged();
  return true;
}

auto QsNativeAiSession::resumeConversation(const QString& conversationId) -> bool {
  if (m_busy) {
    return false;
  }
  return resumeHistoryConversation(conversationId);
}

auto QsNativeAiSession::resumeHistoryConversation(const QString& conversationId) -> bool {
  const QVariantMap result = qsn::takeObject(QsNative_AiHistory_Resume(
      m_modelId.toUtf8().constData(), activeProviderId().toUtf8().constData(),
      m_systemPrompt.toUtf8().constData(), m_conversationId.toUtf8().constData(),
      conversationId.toUtf8().constData()));
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }

  if (!m_messages.isEmpty()) {
    beginRemoveRows({}, 0, rowCountAsInt(m_messages.size()) - 1);
    m_messages.clear();
    endRemoveRows();
  }

  const QVariantMap conv = result.value(QStringLiteral("conversation")).toMap();
  m_conversationId = conv.value(QStringLiteral("id")).toString();
  m_historyLoaded = true;
  restoreMessages(result.value(QStringLiteral("messages")).toList());
  return !m_conversationId.isEmpty();
}

auto QsNativeAiSession::closeHistoryConversation() -> bool {
  if (m_conversationId.isEmpty()) {
    return true;
  }
  const QVariantMap result =
      qsn::takeObject(QsNative_AiHistory_Close(m_conversationId.toUtf8().constData()));
  m_conversationId.clear();
  m_currentTurnId.clear();
  m_currentTurnOrdinal = -1;
  m_nextReplayItemOrdinal = 0;
  m_historyLoaded = false;
  return result.value(QStringLiteral("ok")).toBool();
}

auto QsNativeAiSession::messageToHistoryMap(const Message& msg, int ordinal,
                                            const QString& statusOverride,
                                            const QString& completedAt) const -> QVariantMap {
  const QString status =
      statusOverride.isEmpty()
          ? (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("assistant") &&
                     msg.body.isEmpty()
                 ? QStringLiteral("streaming")
                 : QStringLiteral("complete"))
          : statusOverride;
  QVariantMap out{
      {QStringLiteral("id"), msg.id},
      {QStringLiteral("conversation_id"), m_conversationId},
      {QStringLiteral("ordinal"), ordinal},
      {QStringLiteral("sender"), msg.sender},
      {QStringLiteral("kind"), msg.kind},
      {QStringLiteral("status"), status},
      {QStringLiteral("body"), msg.body},
      {QStringLiteral("metrics_json"), metricsForMessage(msg)},
      {QStringLiteral("extra_json"), extraForMessage(msg)},
  };
  if (!completedAt.isEmpty()) {
    out.insert(QStringLiteral("completed_at"), completedAt);
  }
  if (status == QStringLiteral("complete") || status == QStringLiteral("error")) {
    out.insert(QStringLiteral("updated_at"), utcNow());
  }
  return out;
}

void QsNativeAiSession::persistMessageAt(int row, const QString& statusOverride,
                                         const QString& completedAt) {
  if (m_restoringHistory || row < 0 || row >= m_messages.size()) {
    return;
  }
  if (!ensureHistoryConversation()) {
    return;
  }
  const Message& msg = m_messages.at(row);
  const QByteArray messageJson =
      QJsonDocument::fromVariant(messageToHistoryMap(msg, row, statusOverride, completedAt))
          .toJson(QJsonDocument::Compact);
  const QVariantMap result =
      qsn::takeObject(QsNative_AiHistory_UpsertMessage(messageJson.constData()));
  Q_UNUSED(result);
}

void QsNativeAiSession::persistToolCallAt(int row) {
  if (m_restoringHistory || row < 0 || row >= m_messages.size()) {
    return;
  }
  const Message& msg = m_messages.at(row);
  if (msg.kind != QStringLiteral("tool") || msg.tool.isEmpty()) {
    return;
  }

  QVariantMap payload = msg.tool;
  payload.remove(QStringLiteral("show_header"));
  payload.remove(QStringLiteral("agent_payload"));
  payload.remove(QStringLiteral("replay_items"));
  const QString phase = payload.value(QStringLiteral("phase")).toString();
  const QString toolCallId = payload.value(QStringLiteral("tool_call_id")).toString();
  const QString status = payload.value(QStringLiteral("status")).toString();
  const QVariantMap toolCall{
      {QStringLiteral("id"), toolCallId.isEmpty() ? msg.id : toolCallId},
      {QStringLiteral("message_id"), msg.id},
      {QStringLiteral("tool_call_id"), toolCallId.isEmpty() ? msg.id : toolCallId},
      {QStringLiteral("tool_name"), payload.value(QStringLiteral("tool_name")).toString()},
      {QStringLiteral("phase"), phase.isEmpty() ? QStringLiteral("tool_start") : phase},
      {QStringLiteral("status"), status.isEmpty() ? QStringLiteral("running") : status},
      {QStringLiteral("is_error"), payload.value(QStringLiteral("is_error")).toBool()},
      {QStringLiteral("summary"), payload.value(QStringLiteral("summary")).toString()},
      {QStringLiteral("subtitle"), payload.value(QStringLiteral("subtitle")).toString()},
      {QStringLiteral("payload_json"), payload},
      {QStringLiteral("updated_at"), utcNow()},
  };
  const QByteArray toolCallJson =
      QJsonDocument::fromVariant(toolCall).toJson(QJsonDocument::Compact);
  const QVariantMap result =
      qsn::takeObject(QsNative_AiHistory_UpsertToolCall(toolCallJson.constData()));
  Q_UNUSED(result);
}

void QsNativeAiSession::persistResponseItems(const QJsonArray& items, const QString& source) {
  if (m_restoringHistory || m_conversationId.isEmpty() || m_currentTurnId.isEmpty() ||
      m_currentTurnOrdinal < 0 || items.isEmpty()) {
    return;
  }

  QVariantList apiItems;
  for (const QJsonValue& value : items) {
    if (!value.isObject()) {
      continue;
    }
    const QJsonObject raw = value.toObject();
    const QString itemType = jsonStringValue(raw, QStringLiteral("type"));
    const QString callId = jsonStringValue(raw, QStringLiteral("call_id"));
    const int itemOrdinal = m_nextReplayItemOrdinal++;

    apiItems.append(QVariantMap{
        {QStringLiteral("item_ordinal"), itemOrdinal},
        {QStringLiteral("source"), source},
        {QStringLiteral("item_type"), itemType},
        {QStringLiteral("call_id"), callId},
        {QStringLiteral("raw"), raw.toVariantMap()},
    });
  }
  if (apiItems.isEmpty()) {
    return;
  }

  const QByteArray responseItemsJson =
      QJsonDocument::fromVariant(apiItems).toJson(QJsonDocument::Compact);
  const QVariantMap result = qsn::takeObject(QsNative_AiHistory_UpsertResponseItems(
      m_conversationId.toUtf8().constData(), m_currentTurnId.toUtf8().constData(),
      m_currentTurnOrdinal, responseItemsJson.constData()));
  if (!result.value(QStringLiteral("ok")).toBool()) {
    setError(result.value(QStringLiteral("error")).toString());
  }
}

void QsNativeAiSession::persistDeletedFromOrdinal(int ordinal) {
  if (m_conversationId.isEmpty()) {
    return;
  }
  const QVariantMap result = qsn::takeObject(
      QsNative_AiHistory_DeleteFromOrdinal(m_conversationId.toUtf8().constData(), ordinal));
  Q_UNUSED(result);
  if (m_currentTurnOrdinal >= ordinal) {
    m_currentTurnId.clear();
    m_currentTurnOrdinal = -1;
    m_nextReplayItemOrdinal = 0;
  }
}

auto QsNativeAiSession::extraForMessage(const Message& msg) -> QVariantMap {
  QVariantMap out;
  if (!msg.attachments.isEmpty()) {
    out.insert(QStringLiteral("attachments"), msg.attachments);
  }
  return out;
}

auto QsNativeAiSession::metricsForMessage(const Message& msg) -> QVariantMap {
  return msg.metrics;
}

auto QsNativeAiSession::utcNow() -> QString {
  return QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss.zzzZ"));
}

void QsNativeAiSession::restoreMessages(const QVariantList& messages) {
  if (messages.isEmpty() || !m_messages.isEmpty()) {
    return;
  }

  m_restoringHistory = true;
  QList<Message> restored;
  for (const QVariant& item : messages) {
    const QVariantMap raw = item.toMap();
    Message msg;
    msg.id = raw.value(QStringLiteral("id")).toString();
    msg.sender = raw.value(QStringLiteral("sender")).toString();
    msg.kind = raw.value(QStringLiteral("kind")).toString();
    msg.body = raw.value(QStringLiteral("body")).toString();
    const QString status = raw.value(QStringLiteral("status")).toString();
    if (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("assistant") &&
        status == QStringLiteral("streaming") && msg.body.trimmed().isEmpty()) {
      continue;
    }

    const QJsonDocument metricsDoc =
        QJsonDocument::fromJson(raw.value(QStringLiteral("metrics_json")).toString().toUtf8());
    msg.metrics = metricsDoc.isObject() ? metricsDoc.object().toVariantMap() : QVariantMap{};

    const QJsonDocument extraDoc =
        QJsonDocument::fromJson(raw.value(QStringLiteral("extra_json")).toString().toUtf8());
    const QVariantMap extra =
        extraDoc.isObject() ? extraDoc.object().toVariantMap() : QVariantMap{};
    msg.attachments = extra.value(QStringLiteral("attachments")).toList();

    const QVariantList toolCalls = raw.value(QStringLiteral("tool_calls")).toList();
    if (!toolCalls.isEmpty()) {
      const QVariantMap call = toolCalls.first().toMap();
      const QJsonDocument payloadDoc =
          QJsonDocument::fromJson(call.value(QStringLiteral("payload_json")).toString().toUtf8());
      msg.tool = payloadDoc.isObject() ? payloadDoc.object().toVariantMap() : QVariantMap{};
    }

    bool showHeader = true;
    if (!restored.isEmpty()) {
      const Message& previous = restored.last();
      if (msg.kind == QStringLiteral("tool")) {
        if (previous.kind == QStringLiteral("tool")) {
          showHeader = false;
        } else if (previous.kind == QStringLiteral("chat") &&
                   previous.sender == QStringLiteral("assistant")) {
          showHeader = previous.body.trimmed().isEmpty();
        }
      } else if (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("assistant") &&
                 previous.kind == QStringLiteral("tool")) {
        showHeader = false;
      }
    }
    msg.showHeader = showHeader;
    if (msg.kind == QStringLiteral("tool")) {
      msg.tool.insert(QStringLiteral("show_header"), showHeader);
    }
    restored.append(msg);
  }
  if (restored.isEmpty()) {
    m_restoringHistory = false;
    return;
  }
  beginInsertRows({}, 0, rowCountAsInt(restored.size()) - 1);
  m_messages.append(restored);
  endInsertRows();
  m_restoringHistory = false;
  emit scrollToEndRequested();
}

auto QsNativeAiSession::buildProviderConfigJson() const -> QByteArray {
  return QJsonDocument::fromVariant(m_providerConfig).toJson(QJsonDocument::Compact);
}

auto QsNativeAiSession::modelCatalog(const QVariantList& configuredModels,
                                     const QVariantList& providerOrder) const -> QVariantMap {
  const QByteArray providerConfigJson = buildProviderConfigJson();
  const QByteArray providerOrderJson =
      QJsonDocument::fromVariant(providerOrder).toJson(QJsonDocument::Compact);
  const QByteArray configuredModelsJson =
      QJsonDocument::fromVariant(configuredModels).toJson(QJsonDocument::Compact);
  return qsn::takeObject(QsNative_AiModels_Catalog(providerConfigJson.constData(),
                                                   providerOrderJson.constData(),
                                                   configuredModelsJson.constData()));
}

auto QsNativeAiSession::refreshMcp() -> bool {
  refreshMcpStateAsync();
  return true;
}

void QsNativeAiSession::refreshMcpStateAsync() {
  QThreadPool::globalInstance()->start([this]() -> void {
    const QJsonDocument doc = qsn::takeDoc(QsNative_AiMcp_Refresh());

    qsn::postToObject(this, [this, doc]() -> void {
      if (!doc.isObject()) {
        m_mcpStatus = QStringLiteral("error");
        m_mcpError = QStringLiteral("Invalid MCP response");
        emit mcpStateChanged();
        return;
      }
      const QJsonObject obj = doc.object();
      m_mcpServers = obj.value(QLatin1String("servers")).toArray().toVariantList();
      m_mcpTools = obj.value(QLatin1String("tools")).toArray().toVariantList();
      m_mcpStatus = obj.value(QLatin1String("status")).toString();
      m_mcpError = obj.value(QLatin1String("error")).toString();
      emit mcpStateChanged();
    });
  });
}

auto QsNativeAiSession::activeProviderId() const -> QString {
  const int slash = static_cast<int>(m_modelId.indexOf(QLatin1Char('/')));
  if (slash <= 0) {
    return {};
  }
  return m_modelId.left(slash);
}

auto QsNativeAiSession::activeProviderConfig() const -> QVariantMap {
  return m_providerConfig.value(activeProviderId()).toMap();
}

auto QsNativeAiSession::resumeOptionFromSummary(const QVariantMap& summary) -> QVariantMap {
  const QString id = summary.value(QStringLiteral("id")).toString();
  if (id.isEmpty()) {
    return {};
  }

  QString title = summary.value(QStringLiteral("title")).toString().trimmed();
  QString preview = summary.value(QStringLiteral("preview")).toString().simplified();
  if (preview.length() > 90) {
    preview = preview.left(90) + QStringLiteral("...");
  }
  if (title.isEmpty()) {
    title = preview.isEmpty() ? QStringLiteral("Untitled chat") : preview;
  }
  if (title.length() > 48) {
    title = title.left(48) + QStringLiteral("...");
  }

  const int messageCount = summary.value(QStringLiteral("message_count")).toInt();
  const QString closedAt = summary.value(QStringLiteral("closed_at")).toString();
  const QString updatedAt = summary.value(QStringLiteral("updated_at")).toString();
  const QString when = closedAt.isEmpty() ? updatedAt : closedAt;
  QString description = QStringLiteral("%1 messages").arg(messageCount);
  if (!when.isEmpty()) {
    description += QStringLiteral("  •  %1").arg(when);
  }
  if (!preview.isEmpty() && preview != title) {
    description += QStringLiteral("  •  %1").arg(preview);
  }

  return QVariantMap{
      {QStringLiteral("label"), title},
      {QStringLiteral("value"), id},
      {QStringLiteral("description"), description},
      {QStringLiteral("icon"), QStringLiteral("\uf1da")},
  };
}

auto QsNativeAiSession::indexOfMessage(const QString& id) const -> int {
  for (int i = 0; i < m_messages.size(); ++i) {
    if (m_messages.at(i).id == id) {
      return i;
    }
  }
  return -1;
}

auto QsNativeAiSession::indexOfToolCall(const QString& toolCallId) const -> int {
  if (toolCallId.isEmpty()) {
    return -1;
  }
  for (int i = 0; i < m_messages.size(); ++i) {
    const Message& msg = m_messages.at(i);
    if (msg.kind == QStringLiteral("tool") &&
        msg.tool.value(QStringLiteral("tool_call_id")).toString() == toolCallId) {
      return i;
    }
  }
  return -1;
}

auto QsNativeAiSession::lastAssistantChatIndex() const -> int {
  for (int i = rowCountAsInt(m_messages.size()) - 1; i >= 0; --i) {
    const Message& msg = m_messages.at(i);
    if (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("assistant")) {
      return i;
    }
  }
  return -1;
}

void QsNativeAiSession::handleToolEventJson(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (!doc.isObject()) {
    return;
  }

  const QJsonObject object = doc.object();
  if (object.value(QStringLiteral("kind")).toString() == QStringLiteral("raw_response_items")) {
    persistResponseItems(object.value(QStringLiteral("items")).toArray(),
                         QStringLiteral("model_output"));
    return;
  }

  const QJsonArray replayItems = object.value(QStringLiteral("replay_items")).toArray();
  QVariantMap tool = object.toVariantMap();
  tool.remove(QStringLiteral("agent_payload"));
  tool.remove(QStringLiteral("replay_items"));
  const QString phase = tool.value(QStringLiteral("phase")).toString();
  const QString toolCallId = tool.value(QStringLiteral("tool_call_id")).toString();
  const int existing = indexOfToolCall(toolCallId);

  if (phase == QStringLiteral("tool_start") || existing < 0) {
    int row = rowCountAsInt(m_messages.size());
    bool replaceEmptyAssistant = false;
    QString rowId =
        toolCallId.isEmpty() ? QUuid::createUuid().toString(QUuid::WithoutBraces) : toolCallId;
    if (row > 0) {
      const Message& current = m_messages.at(row - 1);
      if (current.kind == QStringLiteral("chat") && current.sender == QStringLiteral("assistant") &&
          current.body.trimmed().isEmpty()) {
        row = row - 1;
        rowId = current.id;
        replaceEmptyAssistant = true;
      }
    }
    bool showHeader = true;
    if (row > 0) {
      const Message& previous = m_messages.at(row - 1);
      if (previous.kind == QStringLiteral("tool")) {
        showHeader = false;
      } else if (previous.kind == QStringLiteral("chat") &&
                 previous.sender == QStringLiteral("assistant")) {
        showHeader = previous.body.trimmed().isEmpty();
      }
    }
    tool.insert(QStringLiteral("show_header"), showHeader);
    if (replaceEmptyAssistant) {
      m_messages[row] = {rowId,         QStringLiteral("tool"), QString(), QStringLiteral("tool"),
                         QVariantMap{}, QVariantList{},         tool,      showHeader};
      const QModelIndex idx = index(row, 0);
      emit dataChanged(
          idx, idx,
          {SenderRole, BodyRole, KindRole, MetricsRole, AttachmentsRole, ToolRole, ShowHeaderRole});
    } else {
      beginInsertRows({}, row, row);
      m_messages.append({rowId, QStringLiteral("tool"), QString(), QStringLiteral("tool"),
                         QVariantMap{}, QVariantList{}, tool, showHeader});
      endInsertRows();
    }
    persistMessageAt(row, phase == QStringLiteral("tool_start") ? QStringLiteral("streaming")
                                                                : QStringLiteral("complete"));
    persistToolCallAt(row);
    persistResponseItems(replayItems, QStringLiteral("tool_output"));
    emit scrollToEndRequested();
    return;
  }

  tool.insert(QStringLiteral("show_header"),
              m_messages[existing].tool.value(QStringLiteral("show_header"), false));
  m_messages[existing].tool = tool;
  const QModelIndex idx = index(existing, 0);
  emit dataChanged(idx, idx, {ToolRole});
  persistMessageAt(existing,
                   tool.value(QStringLiteral("is_error")).toBool() ? QStringLiteral("error")
                                                                   : QStringLiteral("complete"),
                   utcNow());
  persistToolCallAt(existing);
  persistResponseItems(replayItems, QStringLiteral("tool_output"));
  emit scrollToEndRequested();
}

// ── Token callback (called from the backend worker → queued to Qt thread) ─────

void QsNativeAiSession::tokenCallback(void* ctx, const char* token, int done) {
  auto* self = static_cast<QsNativeAiSession*>(ctx);
  QString const tok = (token != nullptr) ? QString::fromUtf8(token) : QString();

  qsn::postToObject(self, [self, tok, done]() -> void {
    if (done == 1) {
      // Stream finished successfully.
      self->m_sessionId = -1;
      self->m_currentTurnId.clear();
      self->m_currentTurnOrdinal = -1;
      self->m_nextReplayItemOrdinal = 0;
      self->setBusy(false);
      self->setStatus(QStringLiteral("Ready"));

      // Capture per-message metrics onto the last assistant message.
      const int metricsRow = self->lastAssistantChatIndex();
      if (metricsRow >= 0) {
        char* raw = QsNative_AiChat_LastMetrics();
        if (raw) {
          const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(raw));
          self->m_messages[metricsRow].metrics =
              doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
          QsNative_Free(raw);
          const QModelIndex idx = self->index(metricsRow, 0);
          emit self->dataChanged(idx, idx, {MetricsRole});
        }
        self->persistMessageAt(metricsRow, QStringLiteral("complete"), QsNativeAiSession::utcNow());
      }

      emit self->streamDone();
    } else if (done == 2) {
      self->handleToolEventJson(tok);
    } else if (done == -1) {
      // Error.
      self->m_sessionId = -1;
      self->m_currentTurnId.clear();
      self->m_currentTurnOrdinal = -1;
      self->m_nextReplayItemOrdinal = 0;
      self->setBusy(false);
      self->setStatus(QStringLiteral("Error"));
      self->setError(tok);
      // Mark the last assistant message as an error indicator.
      const int row = self->lastAssistantChatIndex();
      if (row >= 0) {
        if (self->m_messages[row].body.isEmpty()) {
          self->m_messages[row].body = QStringLiteral("⚠ ") + tok;
        }
        const QModelIndex idx = self->index(row, 0);
        emit self->dataChanged(idx, idx, {BodyRole});
        self->persistMessageAt(row, QStringLiteral("error"), QsNativeAiSession::utcNow());
      }
    } else {
      // Normal token: append to last assistant message.
      int row = rowCountAsInt(self->m_messages.size()) - 1;
      if (row < 0 || self->m_messages.at(row).sender != QStringLiteral("assistant") ||
          self->m_messages.at(row).kind != QStringLiteral("chat")) {
        const bool showHeader = row < 0 || self->m_messages.at(row).kind != QStringLiteral("tool");
        row = rowCountAsInt(self->m_messages.size());
        self->beginInsertRows({}, row, row);
        self->m_messages.append({QUuid::createUuid().toString(QUuid::WithoutBraces),
                                 QStringLiteral("assistant"), QString(), QStringLiteral("chat"),
                                 QVariantMap{}, QVariantList{}, QVariantMap{}, showHeader});
        self->endInsertRows();
        self->persistMessageAt(row, QStringLiteral("streaming"));
      }
      self->m_messages[row].body += tok;
      const QModelIndex idx = self->index(row, 0);
      emit self->dataChanged(idx, idx, {BodyRole});
      emit self->scrollToEndRequested();
    }
  });
}

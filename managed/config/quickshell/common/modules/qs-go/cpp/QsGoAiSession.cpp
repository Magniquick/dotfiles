#include "QsGoAiSession.h"
#include "qsgo_go_api.h"

#include <QBuffer>
#include <QClipboard>
#include <QDateTime>
#include <QGuiApplication>
#include <QHash>
#include <QIODevice>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QMimeData>
#include <QPalette>
#include <QSet>
#include <QThreadPool>
#include <QUuid>
#include <algorithm>

namespace {

auto chatHistoryObject(const QsGoAiSession::Message& msg) -> QJsonObject {
  QJsonObject obj;
  obj[QStringLiteral("sender")] = msg.sender;
  obj[QStringLiteral("body")] = msg.body;
  if (!msg.attachments.isEmpty()) {
    obj[QStringLiteral("attachments")] = QJsonArray::fromVariantList(msg.attachments);
  }
  return obj;
}

auto rawItemsHistoryObject(const QJsonArray& rawItems) -> QJsonObject {
  return QJsonObject{{QStringLiteral("raw_items"), rawItems}};
}

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

QsGoAiSession::QsGoAiSession(QObject* parent) : QAbstractListModel(parent) {}

void QsGoAiSession::setAppLinkColor(const QColor& color) {
  QPalette pal = QGuiApplication::palette();
  pal.setColor(QPalette::Link, color);
  QGuiApplication::setPalette(pal);
}

auto QsGoAiSession::rowCount(const QModelIndex& parent) const -> int {
  if (parent.isValid()) {
    return 0;
  }
  return m_messages.size();
}

auto QsGoAiSession::data(const QModelIndex& index, int role) const -> QVariant {
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

auto QsGoAiSession::roleNames() const -> QHash<int, QByteArray> {
  return {
      {IdRole, "messageId"}, {SenderRole, "sender"},         {BodyRole, "body"},
      {KindRole, "kind"},    {MetricsRole, "metrics"},       {AttachmentsRole, "attachments"},
      {ToolRole, "tool"},    {ShowHeaderRole, "showHeader"},
  };
}

// ── Property setters ──────────────────────────────────────────────────────────

void QsGoAiSession::setModelId(const QString& v) {
  if (v != m_modelId) {
    m_modelId = v;
    emit modelIdChanged();
  }
}

void QsGoAiSession::setSystemPrompt(const QString& v) {
  if (v != m_systemPrompt) {
    m_systemPrompt = v;
    emit systemPromptChanged();
  }
}

void QsGoAiSession::setProviderConfig(const QVariantMap& v) {
  if (v != m_providerConfig) {
    m_providerConfig = v;
    emit providerConfigChanged();
  }
}

void QsGoAiSession::setMcpConfig(const QVariantList& v) {
  if (v == m_mcpConfig) {
    return;
  }
  m_mcpConfig = v;
  emit mcpConfigChanged();
  refreshMcpStateAsync();
}

void QsGoAiSession::setBusy(bool v) {
  if (v != m_busy) {
    m_busy = v;
    emit busyChanged();
  }
}

void QsGoAiSession::setStatus(const QString& v) {
  if (v != m_status) {
    m_status = v;
    emit statusChanged();
  }
}

void QsGoAiSession::setError(const QString& v) {
  if (v != m_error) {
    m_error = v;
    emit errorChanged();
  }
}

// ── Invokables ────────────────────────────────────────────────────────────────

void QsGoAiSession::submitInput(const QString& text) {
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

void QsGoAiSession::submitInputWithAttachments(const QString& text,
                                               const QVariantList& attachments) {
  if (m_busy) {
    return;
  }
  startStream(text.trimmed(), attachments);
}

void QsGoAiSession::startStream(const QString& text, const QVariantList& attachments) {
  if (!ensureHistoryConversation()) {
    setError(QStringLiteral("Failed to open conversation history"));
    return;
  }

  // Build history from current messages BEFORE appending new ones.
  const QString histJson = buildHistoryJson();
  const QByteArray providerConfigJson = buildProviderConfigJson();
  const QByteArray mcpConfigJson = buildMcpConfigJson();
  const QByteArray attachmentsJson =
      QJsonDocument::fromVariant(attachments).toJson(QJsonDocument::Compact);

  // Append user message.
  const int userRow = m_messages.size();
  beginInsertRows({}, userRow, userRow);
  m_messages.append({QUuid::createUuid().toString(QUuid::WithoutBraces), "user", text, "chat",
                     QVariantMap{}, attachments});
  endInsertRows();
  m_currentTurnId = m_messages.at(userRow).id;
  m_currentTurnOrdinal = userRow;
  m_nextReplayItemOrdinal = 0;
  persistMessageAt(userRow, QStringLiteral("complete"), utcNow());

  // Append empty assistant message (filled by tokens).
  const int asstRow = m_messages.size();
  beginInsertRows({}, asstRow, asstRow);
  m_messages.append(
      {QUuid::createUuid().toString(QUuid::WithoutBraces), "assistant", QString(), "chat"});
  endInsertRows();
  persistMessageAt(asstRow, QStringLiteral("streaming"));

  emit scrollToEndRequested();

  setBusy(true);
  setError(QString());
  setStatus(QStringLiteral("Streaming..."));

  m_sessionId = QsGo_AiChat_Stream(
      m_modelId.toUtf8().constData(), providerConfigJson.constData(), mcpConfigJson.constData(),
      m_systemPrompt.toUtf8().constData(), histJson.toUtf8().constData(), text.toUtf8().constData(),
      attachmentsJson.constData(), &QsGoAiSession::tokenCallback, this);
}

void QsGoAiSession::cancel() {
  if (m_sessionId >= 0) {
    QsGo_AiChat_Cancel(m_sessionId);
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

void QsGoAiSession::regenerate(const QString& messageId) {
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
  beginRemoveRows({}, userIdx, m_messages.size() - 1);
  while (m_messages.size() > userIdx) {
    m_messages.removeLast();
  }
  endRemoveRows();

  startStream(userText, userAttachments);
}

void QsGoAiSession::deleteMessage(const QString& messageId) {
  const int idx = indexOfMessage(messageId);
  if (idx < 0) {
    return;
  }
  applyHistoryAction(QVariantMap{{QStringLiteral("action"), QStringLiteral("mark_message_deleted")},
                                 {QStringLiteral("message_id"), messageId}});
  beginRemoveRows({}, idx, idx);
  m_messages.removeAt(idx);
  endRemoveRows();
}

void QsGoAiSession::editMessage(const QString& messageId, const QString& newBody) {
  const int idx = indexOfMessage(messageId);
  if (idx < 0) {
    return;
  }
  m_messages[idx].body = newBody;
  const QModelIndex mi = index(idx, 0);
  emit dataChanged(mi, mi, {BodyRole});
  persistMessageAt(idx, QStringLiteral("complete"));
}

void QsGoAiSession::resetForModelSwitch(const QString& newModelId) {
  closeHistoryConversation();
  if (!m_messages.isEmpty()) {
    beginRemoveRows({}, 0, m_messages.size() - 1);
    m_messages.clear();
    endRemoveRows();
  }
  m_replayItems.clear();
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

void QsGoAiSession::appendInfo(const QString& text) {
  ensureHistoryConversation();
  const int row = m_messages.size();
  beginInsertRows({}, row, row);
  m_messages.append(
      {QUuid::createUuid().toString(QUuid::WithoutBraces), "assistant", text, "info"});
  endInsertRows();
  persistMessageAt(row, QStringLiteral("complete"), utcNow());
  emit scrollToEndRequested();
}

auto QsGoAiSession::copyAllText() const -> QString {
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

auto QsGoAiSession::pasteImageFromClipboard() -> QVariantList {
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

auto QsGoAiSession::pasteAttachmentFromClipboard() -> QVariantList {
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

auto QsGoAiSession::commands() -> QVariantList {
  return QVariantList{
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/model")},
                  {QStringLiteral("description"), QStringLiteral("Change model")}},
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
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/mcp add")},
                  {QStringLiteral("description"), QStringLiteral("Add a new MCP server")}},
      QVariantMap{
          {QStringLiteral("name"), QStringLiteral("/debug")},
          {QStringLiteral("description"), QStringLiteral("Show detailed session diagnostics")}},
      QVariantMap{{QStringLiteral("name"), QStringLiteral("/help")},
                  {QStringLiteral("description"), QStringLiteral("Show available commands")}},
  };
}

// ── Slash commands ────────────────────────────────────────────────────────────

void QsGoAiSession::handleSlashCommand(const QString& cmd) {
  if (cmd == QStringLiteral("/clear")) {
    closeHistoryConversation();
    if (!m_messages.isEmpty()) {
      beginRemoveRows({}, 0, m_messages.size() - 1);
      m_messages.clear();
      endRemoveRows();
    }
  } else if (cmd == QStringLiteral("/model")) {
    emit openModelPickerRequested();
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
                              "| `/mood` | Change mood / persona |\n"
                              "| `/resume` | Resume previous chat |\n"
                              "| `/clear` | Clear chat history |\n"
                              "| `/copy` | Copy all messages to clipboard |\n"
                              "| `/status` | Show model & connection info |\n"
                              "| `/mcp` | Show MCP server and tool status |\n"
                              "| `/mcp add` | Add a new MCP server |\n"
                              "| `/debug` | Show detailed session diagnostics |\n"
                              "| `/help` | Show this message |"));
  } else if (cmd == QStringLiteral("/mcp add")) {
    emit openMcpAddRequested();
  } else if (cmd.startsWith(QStringLiteral("/mcp add "))) {
    appendInfo(QStringLiteral("`/mcp add` opens the add-server form.\n\n"
                              "Auth tokens and custom headers still need to be edited manually in "
                              "`leftpanel/mcp_servers.json`."));
  } else if (cmd == QStringLiteral("/mcp")) {
    const int connectedCount = std::count_if(
        m_mcpServers.cbegin(), m_mcpServers.cend(), [](const QVariant& value) -> bool {
          return value.toMap().value(QStringLiteral("connected")).toBool();
        });
    appendInfo(QStringLiteral("**MCP**\n\n"
                              "- **Servers:** %1 total  •  %2 connected\n"
                              "- **Tools:** %3\n"
                              "- **Prompts:** %4\n"
                              "- **Resources:** %5\n"
                              "- **Status:** %6%7")
                   .arg(m_mcpServers.size())
                   .arg(connectedCount)
                   .arg(m_mcpTools.size())
                   .arg(m_mcpPrompts.size())
                   .arg(m_mcpResources.size())
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

    // Pull last-stream metrics from Go.
    QString metricsSection = QStringLiteral("*(no stream yet)*");
    {
      char* raw = QsGo_AiChat_LastMetrics();
      const QByteArray json(raw);
      QsGo_Free(raw);
      const auto doc = QJsonDocument::fromJson(json);
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

auto QsGoAiSession::restoreHistory() -> bool {
  if (m_historyLoaded) {
    return true;
  }

  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("restore_conversation")},
      {QStringLiteral("model_id"), m_modelId},
      {QStringLiteral("provider_id"), activeProviderId()},
      {QStringLiteral("system_prompt"), m_systemPrompt},
  });
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }

  const QVariantMap conv = result.value(QStringLiteral("conversation")).toMap();
  m_conversationId = conv.value(QStringLiteral("id")).toString();
  restoreReplayItems();
  restoreMessages(result.value(QStringLiteral("messages")).toList());
  m_historyLoaded = true;
  return true;
}

auto QsGoAiSession::ensureHistoryConversation() -> bool {
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

auto QsGoAiSession::createHistoryConversation() -> bool {
  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("create_conversation")},
      {QStringLiteral("model_id"), m_modelId},
      {QStringLiteral("provider_id"), activeProviderId()},
      {QStringLiteral("system_prompt"), m_systemPrompt},
  });
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }
  const QVariantMap conv = result.value(QStringLiteral("conversation")).toMap();
  m_conversationId = conv.value(QStringLiteral("id")).toString();
  m_replayItems.clear();
  m_currentTurnId.clear();
  m_currentTurnOrdinal = -1;
  m_nextReplayItemOrdinal = 0;
  m_historyLoaded = true;
  return !m_conversationId.isEmpty();
}

auto QsGoAiSession::refreshResumeConversations(const QString& query) -> bool {
  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("list_resume_conversations")},
      {QStringLiteral("model_id"), m_modelId},
      {QStringLiteral("provider_id"), activeProviderId()},
      {QStringLiteral("current_conversation_id"), m_conversationId},
      {QStringLiteral("query"), query},
      {QStringLiteral("limit"), 50},
  });
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

auto QsGoAiSession::resumeConversation(const QString& conversationId) -> bool {
  if (m_busy) {
    return false;
  }
  return resumeHistoryConversation(conversationId);
}

auto QsGoAiSession::resumeHistoryConversation(const QString& conversationId) -> bool {
  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("resume_conversation")},
      {QStringLiteral("model_id"), m_modelId},
      {QStringLiteral("provider_id"), activeProviderId()},
      {QStringLiteral("system_prompt"), m_systemPrompt},
      {QStringLiteral("current_conversation_id"), m_conversationId},
      {QStringLiteral("conversation_id"), conversationId},
  });
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return false;
  }

  if (!m_messages.isEmpty()) {
    beginRemoveRows({}, 0, m_messages.size() - 1);
    m_messages.clear();
    endRemoveRows();
  }

  const QVariantMap conv = result.value(QStringLiteral("conversation")).toMap();
  m_conversationId = conv.value(QStringLiteral("id")).toString();
  m_historyLoaded = true;
  restoreReplayItems();
  restoreMessages(result.value(QStringLiteral("messages")).toList());
  return !m_conversationId.isEmpty();
}

auto QsGoAiSession::closeHistoryConversation() -> bool {
  if (m_conversationId.isEmpty()) {
    return true;
  }
  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("close_conversation")},
      {QStringLiteral("conversation_id"), m_conversationId},
  });
  m_conversationId.clear();
  m_replayItems.clear();
  m_currentTurnId.clear();
  m_currentTurnOrdinal = -1;
  m_nextReplayItemOrdinal = 0;
  m_historyLoaded = false;
  return result.value(QStringLiteral("ok")).toBool();
}

auto QsGoAiSession::applyHistoryAction(const QVariantMap& action) -> QVariantMap {
  const QByteArray rawAction = QJsonDocument::fromVariant(action).toJson(QJsonDocument::Compact);
  char* raw = QsGo_AiHistory_Apply(rawAction.constData());
  const QByteArray rawResult((raw != nullptr) ? raw : "");
  QsGo_Free(raw);

  const QJsonDocument doc = QJsonDocument::fromJson(rawResult);
  if (!doc.isObject()) {
    return QVariantMap{{QStringLiteral("ok"), false},
                       {QStringLiteral("error"), QStringLiteral("invalid history response")}};
  }
  return doc.object().toVariantMap();
}

auto QsGoAiSession::messageToHistoryMap(const Message& msg, int ordinal,
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

void QsGoAiSession::persistMessageAt(int row, const QString& statusOverride,
                                     const QString& completedAt) {
  if (m_restoringHistory || row < 0 || row >= m_messages.size()) {
    return;
  }
  if (!ensureHistoryConversation()) {
    return;
  }
  const Message& msg = m_messages.at(row);
  applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("upsert_message")},
      {QStringLiteral("message"), messageToHistoryMap(msg, row, statusOverride, completedAt)},
  });
}

void QsGoAiSession::persistToolCallAt(int row) {
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
  applyHistoryAction(QVariantMap{{QStringLiteral("action"), QStringLiteral("upsert_tool_call")},
                                 {QStringLiteral("tool_call"), toolCall}});
}

void QsGoAiSession::persistResponseItems(const QJsonArray& items, const QString& source) {
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
    m_replayItems.append(ReplayItem{
        QString(),
        m_currentTurnId,
        m_currentTurnOrdinal,
        itemOrdinal,
        source,
        itemType,
        callId,
        raw,
    });
  }
  if (apiItems.isEmpty()) {
    return;
  }

  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("upsert_response_items")},
      {QStringLiteral("conversation_id"), m_conversationId},
      {QStringLiteral("turn_id"), m_currentTurnId},
      {QStringLiteral("turn_ordinal"), m_currentTurnOrdinal},
      {QStringLiteral("response_items"), apiItems},
  });
  if (!result.value(QStringLiteral("ok")).toBool()) {
    setError(result.value(QStringLiteral("error")).toString());
  }
}

void QsGoAiSession::persistDeletedFromOrdinal(int ordinal) {
  if (m_conversationId.isEmpty()) {
    return;
  }
  applyHistoryAction(QVariantMap{{QStringLiteral("action"), QStringLiteral("delete_from_ordinal")},
                                 {QStringLiteral("conversation_id"), m_conversationId},
                                 {QStringLiteral("ordinal"), ordinal}});
  for (int i = m_replayItems.size() - 1; i >= 0; --i) {
    if (m_replayItems.at(i).turnOrdinal >= ordinal) {
      m_replayItems.removeAt(i);
    }
  }
  if (m_currentTurnOrdinal >= ordinal) {
    m_currentTurnId.clear();
    m_currentTurnOrdinal = -1;
    m_nextReplayItemOrdinal = 0;
  }
}

auto QsGoAiSession::extraForMessage(const Message& msg) -> QVariantMap {
  QVariantMap out;
  if (!msg.attachments.isEmpty()) {
    out.insert(QStringLiteral("attachments"), msg.attachments);
  }
  return out;
}

auto QsGoAiSession::metricsForMessage(const Message& msg) -> QVariantMap {
  return msg.metrics;
}

auto QsGoAiSession::utcNow() -> QString {
  return QDateTime::currentDateTimeUtc().toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss.zzzZ"));
}

void QsGoAiSession::restoreMessages(const QVariantList& messages) {
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
  beginInsertRows({}, 0, restored.size() - 1);
  m_messages.append(restored);
  endInsertRows();
  m_restoringHistory = false;
  emit scrollToEndRequested();
}

void QsGoAiSession::restoreReplayItems() {
  m_replayItems.clear();
  if (m_conversationId.isEmpty()) {
    return;
  }

  const QVariantMap result = applyHistoryAction(QVariantMap{
      {QStringLiteral("action"), QStringLiteral("list_response_items")},
      {QStringLiteral("conversation_id"), m_conversationId},
  });
  if (!result.value(QStringLiteral("ok")).toBool()) {
    return;
  }

  const QVariantList items = result.value(QStringLiteral("response_items")).toList();
  for (const QVariant& value : items) {
    const QVariantMap rawItem = value.toMap();
    const QString rawJson = rawItem.value(QStringLiteral("raw_json")).toString();
    const QJsonDocument rawDoc = QJsonDocument::fromJson(rawJson.toUtf8());
    if (!rawDoc.isObject()) {
      continue;
    }
    m_replayItems.append(ReplayItem{
        rawItem.value(QStringLiteral("id")).toString(),
        rawItem.value(QStringLiteral("turn_id")).toString(),
        rawItem.value(QStringLiteral("turn_ordinal")).toInt(),
        rawItem.value(QStringLiteral("item_ordinal")).toInt(),
        rawItem.value(QStringLiteral("source")).toString(),
        rawItem.value(QStringLiteral("item_type")).toString(),
        rawItem.value(QStringLiteral("call_id")).toString(),
        rawDoc.object(),
    });
  }
}

auto QsGoAiSession::buildHistoryJson() const -> QString {
  QJsonArray arr;
  QHash<QString, QJsonArray> replayByTurn;
  QSet<QString> replayTurnsWithMessage;
  QList<QString> replayTurnOrder;
  for (const ReplayItem& item : m_replayItems) {
    if (item.turnId.isEmpty() || item.raw.isEmpty()) {
      continue;
    }
    if (!replayByTurn.contains(item.turnId)) {
      replayTurnOrder.append(item.turnId);
    }
    replayByTurn[item.turnId].append(item.raw);
    if (jsonStringValue(item.raw, QStringLiteral("type")) == QStringLiteral("message")) {
      replayTurnsWithMessage.insert(item.turnId);
    }
  }

  QSet<QString> consumedReplayTurns;
  bool activeTurnHasReplay = false;
  bool activeTurnHasRawMessage = false;
  for (const Message& msg : m_messages) {
    const QJsonArray replayItems = replayByTurn.value(msg.id);
    if (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("user")) {
      arr.append(chatHistoryObject(msg));
      if (!replayItems.isEmpty()) {
        arr.append(rawItemsHistoryObject(replayItems));
        consumedReplayTurns.insert(msg.id);
        activeTurnHasReplay = true;
        activeTurnHasRawMessage = replayTurnsWithMessage.contains(msg.id);
      } else {
        activeTurnHasReplay = false;
        activeTurnHasRawMessage = false;
      }
      continue;
    }
    if (!replayItems.isEmpty()) {
      arr.append(rawItemsHistoryObject(replayItems));
      consumedReplayTurns.insert(msg.id);
      activeTurnHasReplay = true;
      activeTurnHasRawMessage = replayTurnsWithMessage.contains(msg.id);
      continue;
    }
    if (activeTurnHasReplay) {
      if (msg.kind == QStringLiteral("tool")) {
        continue;
      }
      if (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("assistant") &&
          activeTurnHasRawMessage) {
        continue;
      }
    }
    if (msg.kind != QStringLiteral("chat")) {
      continue;
    }
    if (msg.sender == QStringLiteral("assistant") && msg.body.trimmed().isEmpty()) {
      continue;
    }
    arr.append(chatHistoryObject(msg));
  }
  for (const QString& turnId : replayTurnOrder) {
    if (consumedReplayTurns.contains(turnId)) {
      continue;
    }
    const QJsonArray replayItems = replayByTurn.value(turnId);
    if (!replayItems.isEmpty()) {
      arr.append(rawItemsHistoryObject(replayItems));
      consumedReplayTurns.insert(turnId);
    }
  }
  return QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}

auto QsGoAiSession::buildProviderConfigJson() const -> QByteArray {
  return QJsonDocument::fromVariant(m_providerConfig).toJson(QJsonDocument::Compact);
}

auto QsGoAiSession::buildMcpConfigJson() const -> QByteArray {
  return QJsonDocument::fromVariant(m_mcpConfig).toJson(QJsonDocument::Compact);
}

auto QsGoAiSession::refreshMcp() -> bool {
  refreshMcpStateAsync();
  return true;
}

void QsGoAiSession::refreshMcpStateAsync() {
  const QByteArray mcpConfigJson = buildMcpConfigJson();
  QThreadPool::globalInstance()->start([this, mcpConfigJson]() -> void {
    char* raw = QsGo_AiMcp_Refresh(mcpConfigJson.constData());
    QByteArray const json(raw);
    QsGo_Free(raw);

    QMetaObject::invokeMethod(
        this,
        [this, json]() -> void {
          const QJsonDocument doc = QJsonDocument::fromJson(json);
          if (!doc.isObject()) {
            m_mcpStatus = QStringLiteral("error");
            m_mcpError = QStringLiteral("Invalid MCP response");
            emit mcpStateChanged();
            return;
          }
          const QJsonObject obj = doc.object();
          m_mcpServers = obj.value(QLatin1String("servers")).toArray().toVariantList();
          m_mcpTools = obj.value(QLatin1String("tools")).toArray().toVariantList();
          m_mcpPrompts = obj.value(QLatin1String("prompts")).toArray().toVariantList();
          m_mcpResources = obj.value(QLatin1String("resources")).toArray().toVariantList();
          m_mcpStatus = obj.value(QLatin1String("status")).toString();
          m_mcpError = obj.value(QLatin1String("error")).toString();
          emit mcpStateChanged();
        },
        Qt::QueuedConnection);
  });
}

auto QsGoAiSession::getMcpPrompt(const QString& serverId, const QString& promptName,
                                 const QVariantMap& arguments) -> QVariantMap {
  const QByteArray mcpConfigJson = buildMcpConfigJson();
  const QByteArray argsJson = QJsonDocument::fromVariant(arguments).toJson(QJsonDocument::Compact);
  char* raw = QsGo_AiMcp_GetPrompt(mcpConfigJson.constData(), serverId.toUtf8().constData(),
                                   promptName.toUtf8().constData(), argsJson.constData());
  const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(raw));
  QsGo_Free(raw);
  return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

auto QsGoAiSession::readMcpResource(const QString& serverId, const QString& uri) -> QVariantMap {
  const QByteArray mcpConfigJson = buildMcpConfigJson();
  char* raw = QsGo_AiMcp_ReadResource(mcpConfigJson.constData(), serverId.toUtf8().constData(),
                                      uri.toUtf8().constData());
  const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(raw));
  QsGo_Free(raw);
  return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

auto QsGoAiSession::activeProviderId() const -> QString {
  const int slash = m_modelId.indexOf(QLatin1Char('/'));
  if (slash <= 0) {
    return {};
  }
  return m_modelId.left(slash);
}

auto QsGoAiSession::activeProviderConfig() const -> QVariantMap {
  return m_providerConfig.value(activeProviderId()).toMap();
}

auto QsGoAiSession::resumeOptionFromSummary(const QVariantMap& summary) -> QVariantMap {
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

auto QsGoAiSession::indexOfMessage(const QString& id) const -> int {
  for (int i = 0; i < m_messages.size(); ++i) {
    if (m_messages.at(i).id == id) {
      return i;
    }
  }
  return -1;
}

auto QsGoAiSession::indexOfToolCall(const QString& toolCallId) const -> int {
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

auto QsGoAiSession::lastAssistantChatIndex() const -> int {
  for (int i = m_messages.size() - 1; i >= 0; --i) {
    const Message& msg = m_messages.at(i);
    if (msg.kind == QStringLiteral("chat") && msg.sender == QStringLiteral("assistant")) {
      return i;
    }
  }
  return -1;
}

void QsGoAiSession::handleToolEventJson(const QString& json) {
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
    int row = m_messages.size();
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

// ── Token callback (called from Go goroutine → queued to Qt thread) ───────────

void QsGoAiSession::tokenCallback(void* ctx, const char* token, int done) {
  auto* self = static_cast<QsGoAiSession*>(ctx);
  QString const tok = (token != nullptr) ? QString::fromUtf8(token) : QString();

  QMetaObject::invokeMethod(
      self,
      [self, tok, done]() -> void {
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
            char* raw = QsGo_AiChat_LastMetrics();
            if (raw) {
              const QJsonDocument doc = QJsonDocument::fromJson(QByteArray(raw));
              self->m_messages[metricsRow].metrics =
                  doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
              QsGo_Free(raw);
              const QModelIndex idx = self->index(metricsRow, 0);
              emit self->dataChanged(idx, idx, {MetricsRole});
            }
            self->persistMessageAt(metricsRow, QStringLiteral("complete"), QsGoAiSession::utcNow());
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
            self->persistMessageAt(row, QStringLiteral("error"), QsGoAiSession::utcNow());
          }
        } else {
          // Normal token: append to last assistant message.
          int row = self->m_messages.size() - 1;
          if (row < 0 || self->m_messages.at(row).sender != QStringLiteral("assistant") ||
              self->m_messages.at(row).kind != QStringLiteral("chat")) {
            const bool showHeader =
                row < 0 || self->m_messages.at(row).kind != QStringLiteral("tool");
            row = self->m_messages.size();
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
      },
      Qt::QueuedConnection);
}

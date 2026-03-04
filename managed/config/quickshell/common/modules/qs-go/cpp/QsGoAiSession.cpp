#include "QsGoAiSession.h"
#include "qsgo_go_api.h"

#include <QBuffer>
#include <QClipboard>
#include <QGuiApplication>
#include <QPalette>
#include <QImage>
#include <QIODevice>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QMimeData>
#include <QUuid>

// ── QAbstractListModel ────────────────────────────────────────────────────────

QsGoAiSession::QsGoAiSession(QObject* parent) : QAbstractListModel(parent) {}

void QsGoAiSession::setAppLinkColor(const QColor& color) {
QPalette pal = QGuiApplication::palette();
    pal.setColor(QPalette::Link, color);
    QGuiApplication::setPalette(pal);
}

int QsGoAiSession::rowCount(const QModelIndex& parent) const
{
  if (parent.isValid()) return 0;
  return m_messages.size();
}

QVariant QsGoAiSession::data(const QModelIndex& index, int role) const
{
  if (!index.isValid() || index.row() < 0 || index.row() >= m_messages.size())
    return {};
  const Message& msg = m_messages.at(index.row());
  switch (role) {
  case IdRole:          return msg.id;
  case SenderRole:      return msg.sender;
  case BodyRole:        return msg.body;
  case KindRole:        return msg.kind;
  case MetricsRole:     return msg.metrics;
  case AttachmentsRole: return msg.attachments;
  default:              return {};
  }
}

QHash<int, QByteArray> QsGoAiSession::roleNames() const
{
  return {
    { IdRole,          "messageId"   },
    { SenderRole,      "sender"      },
    { BodyRole,        "body"        },
    { KindRole,        "kind"        },
    { MetricsRole,     "metrics"     },
    { AttachmentsRole, "attachments" },
  };
}

// ── Property setters ──────────────────────────────────────────────────────────

void QsGoAiSession::setModelId(const QString& v)
{ if (v != m_modelId) { m_modelId = v; emit modelIdChanged(); } }

void QsGoAiSession::setSystemPrompt(const QString& v)
{ if (v != m_systemPrompt) { m_systemPrompt = v; emit systemPromptChanged(); } }

void QsGoAiSession::setOpenaiApiKey(const QString& v)
{ if (v != m_openaiApiKey) { m_openaiApiKey = v; emit openaiApiKeyChanged(); } }

void QsGoAiSession::setGeminiApiKey(const QString& v)
{ if (v != m_geminiApiKey) { m_geminiApiKey = v; emit geminiApiKeyChanged(); } }

void QsGoAiSession::setOpenaiBaseUrl(const QString& v)
{ if (v != m_openaiBaseUrl) { m_openaiBaseUrl = v; emit openaiBaseUrlChanged(); } }

void QsGoAiSession::setBusy(bool v)
{ if (v != m_busy) { m_busy = v; emit busyChanged(); } }

void QsGoAiSession::setStatus(const QString& v)
{ if (v != m_status) { m_status = v; emit statusChanged(); } }

void QsGoAiSession::setError(const QString& v)
{ if (v != m_error) { m_error = v; emit errorChanged(); } }

// ── Invokables ────────────────────────────────────────────────────────────────

void QsGoAiSession::submitInput(const QString& text)
{
  const QString trimmed = text.trimmed();
  if (trimmed.isEmpty()) return;

  if (trimmed.startsWith('/')) {
    handleSlashCommand(trimmed.toLower());
    return;
  }
  if (m_busy) return;
  startStream(trimmed, QString());
}

void QsGoAiSession::submitInputWithAttachments(const QString& text, const QString& attachmentsJson)
{
  if (m_busy) return;
  startStream(text.trimmed(), attachmentsJson);
}

void QsGoAiSession::startStream(const QString& text, const QString& attachmentsJson)
{
  // Build history from current messages BEFORE appending new ones.
  const QString histJson = buildHistoryJson();

  // Append user message.
  const int userRow = m_messages.size();
  beginInsertRows({}, userRow, userRow);
  m_messages.append({ QUuid::createUuid().toString(QUuid::WithoutBraces), "user", text, "chat", QString(), attachmentsJson });
  endInsertRows();

  // Append empty assistant message (filled by tokens).
  const int asstRow = m_messages.size();
  beginInsertRows({}, asstRow, asstRow);
  m_messages.append({ QUuid::createUuid().toString(QUuid::WithoutBraces), "assistant", QString(), "chat" });
  endInsertRows();

  emit scrollToEndRequested();

  setBusy(true);
  setError(QString());
  setStatus(QStringLiteral("Streaming..."));

  m_sessionId = QsGo_AiChat_Stream(
    m_modelId.toUtf8().constData(),
    m_openaiApiKey.toUtf8().constData(),
    m_geminiApiKey.toUtf8().constData(),
    m_openaiBaseUrl.toUtf8().constData(),
    m_systemPrompt.toUtf8().constData(),
    histJson.toUtf8().constData(),
    text.toUtf8().constData(),
    attachmentsJson.toUtf8().constData(),
    &QsGoAiSession::tokenCallback,
    this
  );
}

void QsGoAiSession::cancel()
{
  if (m_sessionId >= 0) {
    QsGo_AiChat_Cancel(m_sessionId);
    m_sessionId = -1;
  }
  setBusy(false);
  setStatus(QStringLiteral("Cancelled"));
}

void QsGoAiSession::regenerate(const QString& messageId)
{
  if (m_busy) return;

  // Find the assistant message and the user message before it.
  int asstIdx = indexOfMessage(messageId);
  if (asstIdx < 0) return;

  // Look backwards for the last user message.
  int userIdx = -1;
  for (int i = asstIdx - 1; i >= 0; --i) {
    if (m_messages.at(i).sender == QStringLiteral("user")) {
      userIdx = i;
      break;
    }
  }
  if (userIdx < 0) return;

  const QString userText = m_messages.at(userIdx).body;

  // Remove from userIdx onwards.
  beginRemoveRows({}, userIdx, m_messages.size() - 1);
  while (m_messages.size() > userIdx)
    m_messages.removeLast();
  endRemoveRows();

  startStream(userText, QString());
}

void QsGoAiSession::deleteMessage(const QString& messageId)
{
  const int idx = indexOfMessage(messageId);
  if (idx < 0) return;
  beginRemoveRows({}, idx, idx);
  m_messages.removeAt(idx);
  endRemoveRows();
}

void QsGoAiSession::editMessage(const QString& messageId, const QString& newBody)
{
  const int idx = indexOfMessage(messageId);
  if (idx < 0) return;
  m_messages[idx].body = newBody;
  const QModelIndex mi = index(idx, 0);
  emit dataChanged(mi, mi, { BodyRole });
}

void QsGoAiSession::resetForModelSwitch(const QString& newModelId)
{
  if (!m_messages.isEmpty()) {
    beginRemoveRows({}, 0, m_messages.size() - 1);
    m_messages.clear();
    endRemoveRows();
  }
  setModelId(newModelId);
  if (m_busy) {
    cancel();
  }
  setBusy(false);
  setError(QString());
  setStatus(QString());
}

void QsGoAiSession::appendInfo(const QString& text)
{
  const int row = m_messages.size();
  beginInsertRows({}, row, row);
  m_messages.append({ QUuid::createUuid().toString(QUuid::WithoutBraces), "assistant", text, "info" });
  endInsertRows();
  emit scrollToEndRequested();
}

QString QsGoAiSession::copyAllText() const
{
  QStringList parts;
  for (const Message& msg : m_messages) {
    if (msg.kind == QStringLiteral("info")) continue;
    parts << (msg.sender == QStringLiteral("user") ? QStringLiteral("You: ") : QStringLiteral("Assistant: "))
               + msg.body;
  }
  return parts.join(QStringLiteral("\n\n"));
}

QString QsGoAiSession::pasteImageFromClipboard()
{
  const QClipboard* cb = QGuiApplication::clipboard();
  const QMimeData* mime = cb->mimeData();
  if (!mime || !mime->hasImage()) return QString();

  const QImage img = cb->image();
  if (img.isNull()) return QString();

  QByteArray ba;
  QBuffer buf(&ba);
  buf.open(QIODevice::WriteOnly);
  img.save(&buf, "PNG");
  buf.close();

  const QString b64 = QString::fromLatin1(ba.toBase64());
  QJsonObject obj;
  obj[QStringLiteral("mime")] = QStringLiteral("image/png");
  obj[QStringLiteral("b64")]  = b64;
  QJsonArray arr;
  arr.append(obj);
  return QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}

QString QsGoAiSession::pasteAttachmentFromClipboard()
{
  const QClipboard* cb = QGuiApplication::clipboard();
  const QMimeData* mime = cb->mimeData();
  if (!mime) return QString();

  if (mime->hasUrls()) {
    QJsonArray arr;
    for (const QUrl& url : mime->urls()) {
      if (!url.isLocalFile()) continue;
      QJsonObject obj;
      obj[QStringLiteral("path")] = url.toLocalFile();
      arr.append(obj);
    }
    if (!arr.isEmpty())
      return QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
  }
  return QString();
}

// ── Command catalog ───────────────────────────────────────────────────────────

QString QsGoAiSession::commandsJson() const
{
  static const QString json = QStringLiteral(
    "["
    "{\"name\":\"/model\",\"description\":\"Change model\"},"
    "{\"name\":\"/mood\",\"description\":\"Change mood / persona\"},"
    "{\"name\":\"/clear\",\"description\":\"Clear chat history\"},"
    "{\"name\":\"/copy\",\"description\":\"Copy all messages to clipboard\"},"
    "{\"name\":\"/status\",\"description\":\"Show model & connection info\"},"
    "{\"name\":\"/debug\",\"description\":\"Show detailed session diagnostics\"},"
    "{\"name\":\"/help\",\"description\":\"Show available commands\"}"
    "]"
  );
  return json;
}

// ── Slash commands ────────────────────────────────────────────────────────────

void QsGoAiSession::handleSlashCommand(const QString& cmd)
{
  if (cmd == QStringLiteral("/clear")) {
    if (!m_messages.isEmpty()) {
      beginRemoveRows({}, 0, m_messages.size() - 1);
      m_messages.clear();
      endRemoveRows();
    }
  } else if (cmd == QStringLiteral("/model")) {
    emit openModelPickerRequested();
  } else if (cmd == QStringLiteral("/mood")) {
    emit openMoodPickerRequested();
  } else if (cmd.startsWith(QStringLiteral("/copy"))) {
    const QString text = copyAllText();
    emit copyAllRequested(text);
  } else if (cmd == QStringLiteral("/help")) {
    appendInfo(QStringLiteral(
      "**Commands**\n\n"
      "| Command | Description |\n"
      "|---|---|\n"
      "| `/model` | Change model |\n"
      "| `/mood` | Change mood / persona |\n"
      "| `/clear` | Clear chat history |\n"
      "| `/copy` | Copy all messages to clipboard |\n"
      "| `/status` | Show model & connection info |\n"
      "| `/debug` | Show detailed session diagnostics |\n"
      "| `/help` | Show this message |"
    ));
  } else if (cmd == QStringLiteral("/status")) {
    const QString provider = m_modelId.startsWith(QStringLiteral("gemini")) ? QStringLiteral("Gemini") : QStringLiteral("OpenAI");
    const bool hasKey = m_modelId.startsWith(QStringLiteral("gemini"))
      ? !m_geminiApiKey.isEmpty()
      : !m_openaiApiKey.isEmpty();
    const QString keyStatus = hasKey ? QStringLiteral("✓ set") : QStringLiteral("✗ not set");
    const QString baseUrl = m_openaiBaseUrl.isEmpty() ? QStringLiteral("(default)") : m_openaiBaseUrl;
    const QString prompt = m_systemPrompt.isEmpty()
      ? QStringLiteral("(none)")
      : (m_systemPrompt.length() > 120 ? m_systemPrompt.left(120) + QStringLiteral("…") : m_systemPrompt);
    appendInfo(QStringLiteral(
      "**Status**\n\n"
      "- **Model:** %1\n"
      "- **Provider:** %2  •  API key: %3\n"
      "- **Base URL:** %4\n"
      "- **Mood prompt:** %5"
    ).arg(m_modelId.isEmpty() ? QStringLiteral("(none)") : m_modelId)
     .arg(provider).arg(keyStatus).arg(baseUrl).arg(prompt));
  } else if (cmd == QStringLiteral("/debug")) {
    const QString provider = m_modelId.startsWith(QStringLiteral("gemini")) ? QStringLiteral("Gemini") : QStringLiteral("OpenAI");
    const QString& activeKey = m_modelId.startsWith(QStringLiteral("gemini")) ? m_geminiApiKey : m_openaiApiKey;
    const QString keyPreview = activeKey.isEmpty()
      ? QStringLiteral("✗ not set")
      : QStringLiteral("✓ %1…").arg(activeKey.left(8));
    const QString geminiKeyPreview = m_geminiApiKey.isEmpty()
      ? QStringLiteral("✗ not set")
      : QStringLiteral("✓ %1…").arg(m_geminiApiKey.left(8));
    const QString openaiKeyPreview = m_openaiApiKey.isEmpty()
      ? QStringLiteral("✗ not set")
      : QStringLiteral("✓ %1…").arg(m_openaiApiKey.left(8));
    int chatCount = 0, infoCount = 0;
    for (const Message& msg : m_messages) {
      if (msg.kind == QStringLiteral("chat")) ++chatCount;
      else ++infoCount;
    }
    const QString prompt = m_systemPrompt.isEmpty()
      ? QStringLiteral("(none)")
      : (m_systemPrompt.length() > 80 ? m_systemPrompt.left(80) + QStringLiteral("…") : m_systemPrompt);
    const QString baseUrl = m_openaiBaseUrl.isEmpty() ? QStringLiteral("(default)") : m_openaiBaseUrl;

    // Pull last-stream metrics from Go.
    QString metricsSection = QStringLiteral("*(no stream yet)*");
    {
      char* raw = QsGo_AiChat_LastMetrics();
      const QByteArray json(raw);
      QsGo_Free(raw);
      const auto doc = QJsonDocument::fromJson(json);
      if (doc.isObject()) {
        const QJsonObject o = doc.object();
        const double ttf   = o["ttf_ms"].toDouble(-1);
        const double total = o["total_ms"].toDouble(0);
        const int chunks   = o["chunk_count"].toInt(0);
        const int ptok     = o["prompt_tokens"].toInt(0);
        const int otok     = o["output_tokens"].toInt(0);
        const bool fin     = o["finished"].toBool(false);
        const QString errStr = o["error"].toString();
        const QString lastModel = o["model"].toString();

        const QString ttfStr  = ttf  < 0 ? QStringLiteral("—")
                                          : QStringLiteral("%1 ms").arg(QString::number(ttf,  'f', 0));
        const QString totStr  = QStringLiteral("%1 ms").arg(QString::number(total, 'f', 0));
        const QString tokStr  = ptok > 0 || otok > 0
          ? QStringLiteral("%1 in / %2 out").arg(ptok).arg(otok)
          : QStringLiteral("%1 chunks (provider didn't report tokens)").arg(chunks);
        const QString status  = fin ? QStringLiteral("✓ completed")
                                    : (errStr.isEmpty() ? QStringLiteral("✗ cancelled") : QStringLiteral("✗ error"));

        metricsSection = QStringLiteral(
          "- Model: `%1`  •  %2\n"
          "- TTFT: %3  •  Total: %4\n"
          "- Tokens: %5"
        ).arg(lastModel).arg(status).arg(ttfStr).arg(totStr).arg(tokStr);

        if (!errStr.isEmpty())
          metricsSection += QStringLiteral("\n- Error: %1").arg(errStr);
      }
    }

    appendInfo(QStringLiteral(
      "**Debug**\n\n"
      "**Model & connection**\n"
      "- Model: `%1`  •  Provider: %2\n"
      "- Active key: %3\n"
      "- Gemini key: %4\n"
      "- OpenAI key: %5\n"
      "- Base URL: %6\n\n"
      "**Session**\n"
      "- Messages: %7 chat + %8 info\n"
      "- Busy: %9  •  Session ID: %10\n\n"
      "**Last stream**\n"
      "%11\n\n"
      "**System prompt**\n"
      "%12"
    ).arg(m_modelId.isEmpty() ? QStringLiteral("(none)") : m_modelId)
     .arg(provider).arg(keyPreview)
     .arg(geminiKeyPreview).arg(openaiKeyPreview).arg(baseUrl)
     .arg(chatCount).arg(infoCount)
     .arg(m_busy ? QStringLiteral("yes") : QStringLiteral("no"))
     .arg(m_sessionId)
     .arg(metricsSection)
     .arg(prompt));
  } else {
    appendInfo(QStringLiteral("Unknown command: %1\nType /help for available commands.").arg(cmd));
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

QString QsGoAiSession::buildHistoryJson() const
{
  QJsonArray arr;
  for (const Message& msg : m_messages) {
    if (msg.kind != QStringLiteral("chat")) continue;
    QJsonObject obj;
    obj[QStringLiteral("sender")] = msg.sender;
    obj[QStringLiteral("body")]   = msg.body;
    arr.append(obj);
  }
  return QString::fromUtf8(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}

int QsGoAiSession::indexOfMessage(const QString& id) const
{
  for (int i = 0; i < m_messages.size(); ++i) {
    if (m_messages.at(i).id == id) return i;
  }
  return -1;
}

// ── Token callback (called from Go goroutine → queued to Qt thread) ───────────

void QsGoAiSession::tokenCallback(void* ctx, const char* token, int done)
{
  auto* self = static_cast<QsGoAiSession*>(ctx);
  QString tok = token ? QString::fromUtf8(token) : QString();

  QMetaObject::invokeMethod(self, [self, tok, done]() {
    if (done == 1) {
      // Stream finished successfully.
      self->m_sessionId = -1;
      self->setBusy(false);
      self->setStatus(QStringLiteral("Ready"));

      // Capture per-message metrics onto the last assistant message.
      if (!self->m_messages.isEmpty() && self->m_messages.last().sender == QStringLiteral("assistant")) {
        char* raw = QsGo_AiChat_LastMetrics();
        if (raw) {
          self->m_messages.last().metrics = QString::fromUtf8(raw);
          QsGo_Free(raw);
          const int row = self->m_messages.size() - 1;
          const QModelIndex idx = self->index(row, 0);
          emit self->dataChanged(idx, idx, { MetricsRole });
        }
      }

      emit self->streamDone();
    } else if (done == -1) {
      // Error.
      self->m_sessionId = -1;
      self->setBusy(false);
      self->setStatus(QStringLiteral("Error"));
      self->setError(tok);
      // Mark the last assistant message as an error indicator.
      if (!self->m_messages.isEmpty() && self->m_messages.last().sender == QStringLiteral("assistant")) {
        if (self->m_messages.last().body.isEmpty())
          self->m_messages.last().body = QStringLiteral("⚠ ") + tok;
        const int row = self->m_messages.size() - 1;
        const QModelIndex idx = self->index(row, 0);
        emit self->dataChanged(idx, idx, { BodyRole });
      }
    } else {
      // Normal token: append to last assistant message.
      if (!self->m_messages.isEmpty() && self->m_messages.last().sender == QStringLiteral("assistant")) {
        self->m_messages.last().body += tok;
        const int row = self->m_messages.size() - 1;
        const QModelIndex idx = self->index(row, 0);
        emit self->dataChanged(idx, idx, { BodyRole });
        emit self->scrollToEndRequested();
      }
    }
  }, Qt::QueuedConnection);
}

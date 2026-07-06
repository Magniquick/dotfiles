#include "QsNativeTodoist.h"
#include "QsNativeGlue.h"

#include <QJsonDocument>
#include <QJsonObject>

QsNativeTodoist::QsNativeTodoist(QObject* parent)
    : QObject(parent), m_handle(QsNative_Todoist_New()) {}

QsNativeTodoist::~QsNativeTodoist() {
  QsNative_Todoist_Delete(m_handle);
}

void QsNativeTodoist::setCachePath(const QString& value) {
  if (value != m_cachePath) {
    m_cachePath = value;
    emit cache_pathChanged();
  }
}

void QsNativeTodoist::setPreferCache(bool value) {
  if (value != m_preferCache) {
    m_preferCache = value;
    emit prefer_cacheChanged();
  }
}

auto QsNativeTodoist::refresh() -> bool {
  if (m_loading) {
    return false;
  }
  setLoading(true);
  setError(QString());

  const QByteArray cachePath = m_cachePath.toUtf8();
  QsNative_Todoist_Refresh(m_handle, cachePath.constData(), m_preferCache, this,
                           &QsNativeTodoist::resultCallback);
  return true;
}

auto QsNativeTodoist::action(const QString& verb, const QString& args_json) -> bool {
  if (m_loading) {
    return false;
  }
  setLoading(true);
  setError(QString());

  const QByteArray verbUtf8 = verb.toUtf8();
  const QByteArray argsUtf8 = args_json.toUtf8();
  const QByteArray cachePath = m_cachePath.toUtf8();
  QsNative_Todoist_Action(m_handle, verbUtf8.constData(), argsUtf8.constData(),
                          cachePath.constData(), this, &QsNativeTodoist::resultCallback);
  return true;
}

void QsNativeTodoist::resultCallback(void* ctx, const char* json) {
  auto* self = static_cast<QsNativeTodoist*>(ctx);
  const QString payload = (json != nullptr) ? QString::fromUtf8(json) : QString();
  qsn::postToObject(self, [self, payload]() { self->applyResult(payload); });
}

void QsNativeTodoist::applyResult(const QString& json) {
  const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
  if (doc.isObject()) {
    const QJsonObject o = doc.object();
    setError(o.value(QStringLiteral("error")).toString());
    setLastUpdated(o.value(QStringLiteral("last_updated")).toString());
    setData(o.value(QStringLiteral("data")).toString());
  }
  setLoading(false);
}

void QsNativeTodoist::setLoading(bool value) {
  if (value != m_loading) {
    m_loading = value;
    emit loadingChanged();
  }
}

void QsNativeTodoist::setError(const QString& value) {
  if (value != m_error) {
    m_error = value;
    emit errorChanged();
  }
}

void QsNativeTodoist::setLastUpdated(const QString& value) {
  if (value != m_lastUpdated) {
    m_lastUpdated = value;
    emit last_updatedChanged();
  }
}

void QsNativeTodoist::setData(const QString& value) {
  if (value != m_data) {
    m_data = value;
    emit dataChanged();
  }
}

#include "QsGoConfigResolver.h"
#include "qsgo_go_api.h"

#include <QJsonDocument>
#include <QJsonObject>

QsGoConfigResolver::QsGoConfigResolver(QObject* parent) : QObject(parent) {}

auto QsGoConfigResolver::refresh() -> bool {
  char* raw = QsGo_Config_Resolve();
  QByteArray const json(raw);
  QsGo_Free(raw);

  const QJsonDocument doc = QJsonDocument::fromJson(json);
  if (!doc.isObject()) {
    return false;
  }

  const QVariantMap next = doc.object().toVariantMap();
  if (next == m_values) {
    return true;
  }
  m_values = next;
  emit valuesChanged();
  return true;
}

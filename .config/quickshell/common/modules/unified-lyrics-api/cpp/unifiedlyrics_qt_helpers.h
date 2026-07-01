#pragma once

#include <QList>
#include <QMap>
#include <QString>
#include <QVariant>

inline QVariant unifiedlyrics_variant_from_map(const QMap<QString, QVariant>& map) {
  return QVariant::fromValue(map);
}

inline QVariant unifiedlyrics_variant_from_list(const QList<QVariant>& list) {
  return QVariant::fromValue(list);
}

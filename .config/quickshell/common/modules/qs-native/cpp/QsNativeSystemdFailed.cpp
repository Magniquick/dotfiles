#include "QsNativeSystemdFailed.h"

#include <QVariantMap>

namespace qsnative::systemd_failed {

auto failedUnitVariant(const QString& unit, const QString& load, const QString& active,
                       const QString& sub, const QString& description) -> QVariant {
  QVariantMap map;
  map.insert(QStringLiteral("unit"), unit);
  map.insert(QStringLiteral("load"), load);
  map.insert(QStringLiteral("active"), active);
  map.insert(QStringLiteral("sub"), sub);
  map.insert(QStringLiteral("description"), description);
  return map;
}

} // namespace qsnative::systemd_failed

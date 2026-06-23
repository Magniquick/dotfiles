#pragma once

#include <QString>
#include <QVariant>

namespace qsnative::systemd_failed {

[[nodiscard]] auto failedUnitVariant(const QString& unit, const QString& load,
                                     const QString& active, const QString& sub,
                                     const QString& description) -> QVariant;

} // namespace qsnative::systemd_failed

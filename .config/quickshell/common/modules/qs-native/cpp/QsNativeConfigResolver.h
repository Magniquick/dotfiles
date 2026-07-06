#pragma once

#include <QObject>
#include <QVariantMap>

struct ConfigEntryC;

// Resolves AI provider config + Secret Service keys into a string map exposed to
// QML as `values` (QVariantMap). refresh() resolves on a Rust worker thread
// (Secret Service blocks on D-Bus) and delivers a #[repr(C)] ConfigEntryC array;
// `values` updates reactively via valuesChanged, so QML just calls refresh().
class QsNativeConfigResolver : public QObject {
  Q_OBJECT

  Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)

public:
  explicit QsNativeConfigResolver(QObject* parent = nullptr) : QObject(parent) {}

  [[nodiscard]] auto values() const -> QVariantMap { return m_values; }

  Q_INVOKABLE auto refresh() -> bool;

signals:
  void valuesChanged();

private:
  static void entriesCallback(void* ctx, const ConfigEntryC* entries, size_t len);
  void applyValues(const QVariantMap& values);

  QVariantMap m_values;
};

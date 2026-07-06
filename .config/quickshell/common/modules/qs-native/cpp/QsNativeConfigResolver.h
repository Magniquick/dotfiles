#pragma once

#include <QObject>
#include <QVariantMap>

struct ConfigResolverHandle;

// Resolves AI provider config + Secret Service keys into a string map exposed to
// QML as `values` (QVariantMap). refresh() loads synchronously on the GUI thread;
// there is no worker or file watcher, so QML must call refresh() explicitly.
//
// TODO(stage2): the Rust backend is currently a stub, so `values` stays empty
// and AI provider config/keys are temporarily unavailable.
class QsNativeConfigResolver : public QObject {
  Q_OBJECT

  Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)

public:
  explicit QsNativeConfigResolver(QObject* parent = nullptr);
  ~QsNativeConfigResolver() override;

  [[nodiscard]] auto values() const -> QVariantMap { return m_values; }

  Q_INVOKABLE auto refresh() -> bool;

signals:
  void valuesChanged();

private:
  ConfigResolverHandle* m_handle;
  QVariantMap m_values;
};

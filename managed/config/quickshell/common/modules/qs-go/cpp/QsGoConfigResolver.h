#pragma once
#include <QObject>
#include <QVariantMap>

class QsGoConfigResolver : public QObject {
  Q_OBJECT

  Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)

public:
  explicit QsGoConfigResolver(QObject* parent = nullptr);

  [[nodiscard]] auto values() const -> QVariantMap {
    return m_values;
  }

  Q_INVOKABLE auto refresh() -> bool;

signals:
  void valuesChanged();

private:
  QVariantMap m_values;
};

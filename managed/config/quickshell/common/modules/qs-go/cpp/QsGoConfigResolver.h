#pragma once
#include <QObject>
#include <QVariantMap>

class QsGoConfigResolver : public QObject {
  Q_OBJECT

  Q_PROPERTY(QVariantMap values READ values NOTIFY valuesChanged)

public:
  explicit QsGoConfigResolver(QObject* parent = nullptr);

  QVariantMap values() const {
    return m_values;
  }

  Q_INVOKABLE bool refresh();

signals:
  void valuesChanged();

private:
  QVariantMap m_values;
};

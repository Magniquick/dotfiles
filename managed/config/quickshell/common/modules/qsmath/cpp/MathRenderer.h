#pragma once

#include <QObject>
#include <QString>

class MathRenderer : public QObject {
  Q_OBJECT

public:
  explicit MathRenderer(QObject* parent = nullptr);

  Q_INVOKABLE void renderMarkdown(const QString& requestId, const QString& markdown,
                                  const QString& cacheDir, int maxWidth, qreal textSize,
                                  qreal padding, const QString& foreground);

signals:
  void requestFinished(const QString& requestId, const QString& html);
  void requestFailed(const QString& requestId, const QString& error);
};

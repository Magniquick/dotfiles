#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

class CaptureProvider : public QObject {
  Q_OBJECT

public:
  explicit CaptureProvider(QObject *parent = nullptr);

  Q_INVOKABLE void captureOutput(const QString &requestId, const QString &outputName, const QString &filePath, bool includeCursor = false);
  Q_INVOKABLE void captureRegion(const QString &requestId, int x, int y, int width, int height, const QString &filePath, double scale = 1.0, bool includeCursor = false);
  Q_INVOKABLE void captureToplevel(const QString &requestId, const QString &identifier, const QString &filePath, bool includeCursor = false);
  Q_INVOKABLE void captureToplevelBatch(const QString &requestId, const QVariantList &requests, bool includeCursor = false);
  Q_INVOKABLE void cropImageFile(const QString &requestId, const QString &sourcePath, int x, int y, int width, int height, double scale, const QString &filePath);
  Q_INVOKABLE void copyImageFile(const QString &requestId, const QString &sourcePath, const QString &filePath);

signals:
  void requestFinished(const QString &requestId, const QString &filePath);
  void requestFailed(const QString &requestId, const QString &error);
  void batchFinished(const QString &requestId);
  void batchFailed(const QString &requestId, const QString &error, int completedCount);
};

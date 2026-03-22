#include "CaptureProvider.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QImage>
#include <QMetaObject>
#include <QPointer>
#include <QtConcurrent/QtConcurrent>
#include <vector>

extern "C" {
#include "../vendor/grim/include/capture_core.h"
}

CaptureProvider::CaptureProvider(QObject *parent)
    : QObject(parent)
{
}

static QString errorToQString(char *error)
{
  QString text = error ? QString::fromUtf8(error) : QStringLiteral("Unknown capture error");
  qs_capture_free_error(error);
  return text;
}

static bool ensureParentDirectory(const QString &filePath, QString *errorMessage = nullptr)
{
  const QFileInfo fileInfo(filePath);
  const QDir directory = fileInfo.dir();
  if (directory.exists())
    return true;
  if (QDir().mkpath(directory.absolutePath()))
    return true;
  if (errorMessage)
    *errorMessage = QStringLiteral("Failed to create output directory: %1").arg(directory.absolutePath());
  return false;
}

void CaptureProvider::captureOutput(const QString &requestId, const QString &outputName, const QString &filePath, bool includeCursor)
{
  QPointer<CaptureProvider> self(this);
  (void)QtConcurrent::run([self, requestId, outputName, filePath, includeCursor]() {
    QString directoryError;
    if (!ensureParentDirectory(filePath, &directoryError)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, directoryError]() {
          if (self)
            emit self->requestFailed(requestId, directoryError);
        }, Qt::QueuedConnection);
      }
      return;
    }

    char *error = nullptr;
    const int rc = qs_capture_capture_output(outputName.toUtf8().constData(), filePath.toUtf8().constData(), includeCursor, &error);
    if (!self)
      return;
    if (rc == 0) {
      QMetaObject::invokeMethod(self, [self, requestId, filePath]() {
        if (self)
          emit self->requestFinished(requestId, filePath);
      }, Qt::QueuedConnection);
      return;
    }

    const QString message = errorToQString(error);
    QMetaObject::invokeMethod(self, [self, requestId, message]() {
      if (self)
        emit self->requestFailed(requestId, message);
    }, Qt::QueuedConnection);
  });
}

void CaptureProvider::captureRegion(const QString &requestId, int x, int y, int width, int height, const QString &filePath, double scale, bool includeCursor)
{
  QPointer<CaptureProvider> self(this);
  (void)QtConcurrent::run([self, requestId, x, y, width, height, filePath, scale, includeCursor]() {
    QString directoryError;
    if (!ensureParentDirectory(filePath, &directoryError)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, directoryError]() {
          if (self)
            emit self->requestFailed(requestId, directoryError);
        }, Qt::QueuedConnection);
      }
      return;
    }

    char *error = nullptr;
    const int rc = qs_capture_capture_region(x, y, width, height, scale, filePath.toUtf8().constData(), includeCursor, &error);
    if (!self)
      return;
    if (rc == 0) {
      QMetaObject::invokeMethod(self, [self, requestId, filePath]() {
        if (self)
          emit self->requestFinished(requestId, filePath);
      }, Qt::QueuedConnection);
      return;
    }

    const QString message = errorToQString(error);
    QMetaObject::invokeMethod(self, [self, requestId, message]() {
      if (self)
        emit self->requestFailed(requestId, message);
    }, Qt::QueuedConnection);
  });
}

void CaptureProvider::captureToplevel(const QString &requestId, const QString &identifier, const QString &filePath, bool includeCursor)
{
  QPointer<CaptureProvider> self(this);
  (void)QtConcurrent::run([self, requestId, identifier, filePath, includeCursor]() {
    QString directoryError;
    if (!ensureParentDirectory(filePath, &directoryError)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, directoryError]() {
          if (self)
            emit self->requestFailed(requestId, directoryError);
        }, Qt::QueuedConnection);
      }
      return;
    }

    char *error = nullptr;
    const int rc = qs_capture_capture_toplevel(identifier.toUtf8().constData(), filePath.toUtf8().constData(), includeCursor, &error);
    if (!self)
      return;
    if (rc == 0) {
      QMetaObject::invokeMethod(self, [self, requestId, filePath]() {
        if (self)
          emit self->requestFinished(requestId, filePath);
      }, Qt::QueuedConnection);
      return;
    }

    const QString message = errorToQString(error);
    QMetaObject::invokeMethod(self, [self, requestId, message]() {
      if (self)
        emit self->requestFailed(requestId, message);
    }, Qt::QueuedConnection);
  });
}

void CaptureProvider::captureToplevelBatch(const QString &requestId, const QVariantList &requests, bool includeCursor)
{
  QPointer<CaptureProvider> self(this);
  (void)QtConcurrent::run([self, requestId, requests, includeCursor]() {
    QList<QByteArray> identifiers;
    QList<QByteArray> filePaths;
    std::vector<qs_capture_toplevel_request> nativeRequests;
    nativeRequests.reserve(static_cast<size_t>(requests.size()));

    for (const QVariant &entry : requests) {
      const QVariantMap map = entry.toMap();
      const QByteArray identifier = map.value(QStringLiteral("identifier")).toString().toUtf8();
      const QByteArray filePath = map.value(QStringLiteral("filePath")).toString().toUtf8();
      if (identifier.isEmpty() || filePath.isEmpty())
        continue;
      QString directoryError;
      if (!ensureParentDirectory(QString::fromUtf8(filePath), &directoryError)) {
        if (self) {
          QMetaObject::invokeMethod(self, [self, requestId, directoryError]() {
            if (self)
              emit self->requestFailed(requestId, directoryError);
          }, Qt::QueuedConnection);
        }
        return;
      }
      identifiers.push_back(identifier);
      filePaths.push_back(filePath);
    }

    nativeRequests.reserve(static_cast<size_t>(identifiers.size()));
    for (int index = 0; index < identifiers.size(); ++index) {
      qs_capture_toplevel_request request {};
      request.identifier = identifiers.at(index).constData();
      request.file_path = filePaths.at(index).constData();
      nativeRequests.push_back(request);
    }

    size_t completedCount = 0;
    char *error = nullptr;
    const int rc = qs_capture_capture_toplevel_batch(nativeRequests.data(), nativeRequests.size(), includeCursor, &completedCount, &error);
    if (!self)
      return;
    if (rc == 0) {
      QMetaObject::invokeMethod(self, [self, requestId]() {
        if (self)
          emit self->batchFinished(requestId);
      }, Qt::QueuedConnection);
      return;
    }

    const QString message = errorToQString(error);
    QMetaObject::invokeMethod(self, [self, requestId, message, completedCount]() {
      if (self)
        emit self->batchFailed(requestId, message, static_cast<int>(completedCount));
    }, Qt::QueuedConnection);
  });
}

void CaptureProvider::cropImageFile(const QString &requestId, const QString &sourcePath, int x, int y, int width, int height, double scale, const QString &filePath)
{
  QPointer<CaptureProvider> self(this);
  (void)QtConcurrent::run([self, requestId, sourcePath, x, y, width, height, scale, filePath]() {
    QString directoryError;
    if (!ensureParentDirectory(filePath, &directoryError)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, directoryError]() {
          if (self)
            emit self->requestFailed(requestId, directoryError);
        }, Qt::QueuedConnection);
      }
      return;
    }

    QImage image(sourcePath);
    if (image.isNull()) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, sourcePath]() {
          if (self)
            emit self->requestFailed(requestId, QStringLiteral("Failed to load source image: %1").arg(sourcePath));
        }, Qt::QueuedConnection);
      }
      return;
    }

    const double usedScale = scale > 0 ? scale : 1.0;
    const QRect rect(qRound(x * usedScale), qRound(y * usedScale), qRound(width * usedScale), qRound(height * usedScale));
    const QImage cropped = image.copy(rect);
    if (cropped.isNull() || !cropped.save(filePath)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, filePath]() {
          if (self)
            emit self->requestFailed(requestId, QStringLiteral("Failed to save cropped image: %1").arg(filePath));
        }, Qt::QueuedConnection);
      }
      return;
    }

    if (self) {
      QMetaObject::invokeMethod(self, [self, requestId, filePath]() {
        if (self)
          emit self->requestFinished(requestId, filePath);
      }, Qt::QueuedConnection);
    }
  });
}

void CaptureProvider::copyImageFile(const QString &requestId, const QString &sourcePath, const QString &filePath)
{
  QPointer<CaptureProvider> self(this);
  (void)QtConcurrent::run([self, requestId, sourcePath, filePath]() {
    QString directoryError;
    if (!ensureParentDirectory(filePath, &directoryError)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, directoryError]() {
          if (self)
            emit self->requestFailed(requestId, directoryError);
        }, Qt::QueuedConnection);
      }
      return;
    }

    QFile::remove(filePath);
    if (!QFile::copy(sourcePath, filePath)) {
      if (self) {
        QMetaObject::invokeMethod(self, [self, requestId, sourcePath, filePath]() {
          if (self)
            emit self->requestFailed(requestId, QStringLiteral("Failed to copy image from %1 to %2").arg(sourcePath, filePath));
        }, Qt::QueuedConnection);
      }
      return;
    }

    if (self) {
      QMetaObject::invokeMethod(self, [self, requestId, filePath]() {
        if (self)
          emit self->requestFinished(requestId, filePath);
      }, Qt::QueuedConnection);
    }
  });
}

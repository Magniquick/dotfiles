#include "QsGoBacklight.h"

#include <QDir>
#include <QFile>
#include <QTextStream>
#include <algorithm>

namespace {

auto readTrimmedFile(const QString& path) -> QString {
  QFile file(path);
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
    return {};
  }
  return QString::fromUtf8(file.readAll()).trimmed();
}

auto clampPercent(int percent) -> int {
  if (percent < 0) {
    return 0;
  }
  if (percent > 100) {
    return 100;
  }
  return percent;
}

} // namespace

QsGoBacklight::QsGoBacklight(QObject* parent) : QObject(parent) {}

QsGoBacklight::~QsGoBacklight() {
  clearWatcher();
}

auto QsGoBacklight::deviceDirectory() -> QString {
  QDir const dir(QStringLiteral("/sys/class/backlight"));
  const QFileInfoList entries = dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
  if (entries.isEmpty()) {
    return {};
  }
  return entries.first().absoluteFilePath();
}

auto QsGoBacklight::brightnessPath() -> QString {
  const QString dir = deviceDirectory();
  return dir.isEmpty() ? QString() : dir + QStringLiteral("/brightness");
}

void QsGoBacklight::applyState(int percent, const QString& device, const QString& error) {
  if (percent != m_brightnessPercent) {
    m_brightnessPercent = percent;
    emit brightnessPercentChanged();
  }

  if (device != m_device) {
    const bool wasAvailable = !m_device.isEmpty();
    m_device = device;
    emit deviceChanged();
    if (wasAvailable != !m_device.isEmpty()) {
      emit availableChanged();
    }
  }

  if (error != m_error) {
    m_error = error;
    emit errorChanged();
  }
}

auto QsGoBacklight::refresh() -> bool {
  const QString dir = deviceDirectory();
  if (dir.isEmpty()) {
    applyState(0, QString(), QStringLiteral("no backlight devices found"));
    return true;
  }

  bool ok = false;
  const int current = readTrimmedFile(dir + QStringLiteral("/brightness")).toInt(&ok);
  if (!ok) {
    applyState(0, QFileInfo(dir).fileName(), QStringLiteral("failed to read brightness"));
    return true;
  }

  const int max = readTrimmedFile(dir + QStringLiteral("/max_brightness")).toInt(&ok);
  if (!ok || max <= 0) {
    applyState(0, QFileInfo(dir).fileName(), QStringLiteral("failed to read max_brightness"));
    return true;
  }

  const int percent = qRound((static_cast<double>(current) / static_cast<double>(max)) * 100.0);
  applyState(percent, QFileInfo(dir).fileName(), QString());
  return true;
}

auto QsGoBacklight::setBrightness(int percent) -> bool {
  const QString dir = deviceDirectory();
  if (dir.isEmpty()) {
    applyState(0, QString(), QStringLiteral("no backlight devices found"));
    return true;
  }

  bool ok = false;
  const int max = readTrimmedFile(dir + QStringLiteral("/max_brightness")).toInt(&ok);
  if (!ok || max <= 0) {
    applyState(m_brightnessPercent, QFileInfo(dir).fileName(),
               QStringLiteral("failed to read max_brightness"));
    return true;
  }

  const int clamped = clampPercent(percent);
  int target = qRound((static_cast<double>(clamped) / 100.0) * static_cast<double>(max));
  if (target < 1 && clamped > 0) {
    target = 1;
  }
  target = std::min(target, max);

  QFile file(dir + QStringLiteral("/brightness"));
  if (!file.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
    applyState(m_brightnessPercent, QFileInfo(dir).fileName(), file.errorString());
    return true;
  }

  QTextStream stream(&file);
  stream << target;
  file.close();

  refresh();
  return true;
}

void QsGoBacklight::start() {
  startMonitor();
}

void QsGoBacklight::ensureWatcher() {
  if (m_watcher == nullptr) {
    m_watcher = new QFileSystemWatcher(this);
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, [this](const QString&) -> void {
      refresh();
      if (m_watcher) {
        const QString path = brightnessPath();
        if (!path.isEmpty() && !m_watcher->files().contains(path)) {
          m_watcher->addPath(path);
        }
      }
    });
  }

  const QString path = brightnessPath();
  if (!path.isEmpty() && !m_watcher->files().contains(path)) {
    m_watcher->addPath(path);
  }
}

void QsGoBacklight::clearWatcher() {
  if (m_watcher == nullptr) {
    return;
  }
  m_watcher->deleteLater();
  m_watcher = nullptr;
}

void QsGoBacklight::startMonitor() {
  ensureWatcher();
  refresh();
}

void QsGoBacklight::stopMonitor() {
  clearWatcher();
}

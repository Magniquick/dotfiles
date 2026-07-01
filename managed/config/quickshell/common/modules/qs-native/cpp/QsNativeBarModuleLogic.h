#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

class QsNativeBarModuleLogic : public QObject {
  Q_OBJECT

public:
  explicit QsNativeBarModuleLogic(QObject* parent = nullptr) : QObject(parent) {}

  Q_INVOKABLE [[nodiscard]] auto bluetoothDevices(const QVariantList& devices) const
      -> QVariantList;
  Q_INVOKABLE [[nodiscard]] auto parseLibrepodsTooltip(const QString& text) const -> QVariantMap;
  Q_INVOKABLE [[nodiscard]] auto activeMprisPlayerIndex(const QVariantList& players) const -> int;
  Q_INVOKABLE [[nodiscard]] auto spotifyTrackRef(const QVariantMap& player) const -> QString;
  Q_INVOKABLE [[nodiscard]] auto lyricsLookupKey(const QString& track, const QString& artist,
                                                 const QString& album,
                                                 const QString& lengthMicros) const -> QString;
  Q_INVOKABLE [[nodiscard]] auto isNoLyricsError(const QString& errorText) const -> bool;
  Q_INVOKABLE [[nodiscard]] auto lyricsSourceInfo(const QString& source) const -> QVariantMap;
  Q_INVOKABLE [[nodiscard]] auto parseSystemdIdleInhibitors(const QString& output) const
      -> QVariantList;
  Q_INVOKABLE [[nodiscard]] auto parsePortalSessionCount(const QString& output) const -> int;
};

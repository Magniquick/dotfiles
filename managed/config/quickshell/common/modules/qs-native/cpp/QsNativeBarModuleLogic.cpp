#include "QsNativeBarModuleLogic.h"
#include "qsnative_api.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

namespace {

auto callJson(char* raw) -> QJsonDocument {
  if (raw == nullptr) {
    return {};
  }
  const QByteArray json(raw);
  QsNative_Free(raw);
  return QJsonDocument::fromJson(json);
}

auto objectFromJson(char* raw) -> QVariantMap {
  const QJsonDocument doc = callJson(raw);
  return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

auto listFromJson(char* raw) -> QVariantList {
  const QJsonDocument doc = callJson(raw);
  return doc.isArray() ? doc.array().toVariantList() : QVariantList{};
}

} // namespace

auto QsNativeBarModuleLogic::bluetoothDevices(const QVariantList& devices) const -> QVariantList {
  const QByteArray json = QJsonDocument::fromVariant(devices).toJson(QJsonDocument::Compact);
  return listFromJson(QsNative_BarModuleLogic_BluetoothDevices(json.constData()));
}

auto QsNativeBarModuleLogic::parseLibrepodsTooltip(const QString& text) const -> QVariantMap {
  return objectFromJson(QsNative_BarModuleLogic_ParseLibrepodsTooltip(text.toUtf8().constData()));
}

auto QsNativeBarModuleLogic::activeMprisPlayerIndex(const QVariantList& players) const -> int {
  const QByteArray json = QJsonDocument::fromVariant(players).toJson(QJsonDocument::Compact);
  const QVariantMap result =
      objectFromJson(QsNative_BarModuleLogic_ActiveMprisPlayer(json.constData()));
  return result.value(QStringLiteral("index"), -1).toInt();
}

auto QsNativeBarModuleLogic::spotifyTrackRef(const QVariantMap& player) const -> QString {
  const QByteArray json = QJsonDocument::fromVariant(player).toJson(QJsonDocument::Compact);
  const QVariantMap result =
      objectFromJson(QsNative_BarModuleLogic_SpotifyTrackRef(json.constData()));
  return result.value(QStringLiteral("ref")).toString();
}

auto QsNativeBarModuleLogic::lyricsLookupKey(const QString& track, const QString& artist,
                                             const QString& album,
                                             const QString& lengthMicros) const -> QString {
  const QVariantMap result = objectFromJson(QsNative_BarModuleLogic_LyricsLookupKey(
      track.toUtf8().constData(), artist.toUtf8().constData(), album.toUtf8().constData(),
      lengthMicros.toUtf8().constData()));
  return result.value(QStringLiteral("key")).toString();
}

auto QsNativeBarModuleLogic::isNoLyricsError(const QString& errorText) const -> bool {
  const QVariantMap result =
      objectFromJson(QsNative_BarModuleLogic_IsNoLyricsError(errorText.toUtf8().constData()));
  return result.value(QStringLiteral("value")).toBool();
}

auto QsNativeBarModuleLogic::lyricsSourceInfo(const QString& source) const -> QVariantMap {
  return objectFromJson(QsNative_BarModuleLogic_LyricsSourceInfo(source.toUtf8().constData()));
}

auto QsNativeBarModuleLogic::parseSystemdIdleInhibitors(const QString& output) const
    -> QVariantList {
  return listFromJson(
      QsNative_BarModuleLogic_ParseSystemdIdleInhibitors(output.toUtf8().constData()));
}

auto QsNativeBarModuleLogic::parsePortalSessionCount(const QString& output) const -> int {
  const QVariantMap result =
      objectFromJson(QsNative_BarModuleLogic_ParsePortalSessionCount(output.toUtf8().constData()));
  return result.value(QStringLiteral("count"), 0).toInt();
}

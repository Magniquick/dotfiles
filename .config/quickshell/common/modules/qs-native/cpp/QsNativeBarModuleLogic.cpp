#include "QsNativeBarModuleLogic.h"
#include "QsNativeGlue.h"
#include "qsnative_api.h"

#include <QByteArray>

namespace {
auto cborBytes(const QByteArray& cbor) -> const uint8_t* {
  return reinterpret_cast<const uint8_t*>(cbor.constData());
}
} // namespace

auto QsNativeBarModuleLogic::bluetoothDevices(const QVariantList& devices) const -> QVariantList {
  const QByteArray cbor = qsn::toCbor(devices);
  return qsn::takeCborList(
      QsNative_BarModuleLogic_BluetoothDevices(cborBytes(cbor), static_cast<size_t>(cbor.size())));
}

auto QsNativeBarModuleLogic::parseLibrepodsTooltip(const QString& text) const -> QVariantMap {
  return qsn::takeCborObject(
      QsNative_BarModuleLogic_ParseLibrepodsTooltip(text.toUtf8().constData()));
}

auto QsNativeBarModuleLogic::activeMprisPlayerIndex(const QVariantList& players) const -> int {
  const QByteArray cbor = qsn::toCbor(players);
  return qsn::takeCbor(QsNative_BarModuleLogic_ActiveMprisPlayer(cborBytes(cbor),
                                                                  static_cast<size_t>(cbor.size())))
      .toInt();
}

auto QsNativeBarModuleLogic::spotifyTrackRef(const QVariantMap& player) const -> QString {
  const QByteArray cbor = qsn::toCbor(player);
  return qsn::takeCbor(QsNative_BarModuleLogic_SpotifyTrackRef(cborBytes(cbor),
                                                                static_cast<size_t>(cbor.size())))
      .toString();
}

auto QsNativeBarModuleLogic::lyricsLookupKey(const QString& track, const QString& artist,
                                             const QString& album,
                                             const QString& lengthMicros) const -> QString {
  return qsn::takeCbor(QsNative_BarModuleLogic_LyricsLookupKey(
                           track.toUtf8().constData(), artist.toUtf8().constData(),
                           album.toUtf8().constData(), lengthMicros.toUtf8().constData()))
      .toString();
}

auto QsNativeBarModuleLogic::isNoLyricsError(const QString& errorText) const -> bool {
  return qsn::takeCbor(QsNative_BarModuleLogic_IsNoLyricsError(errorText.toUtf8().constData()))
      .toBool();
}

auto QsNativeBarModuleLogic::lyricsSourceInfo(const QString& source) const -> QVariantMap {
  return qsn::takeCborObject(QsNative_BarModuleLogic_LyricsSourceInfo(source.toUtf8().constData()));
}

auto QsNativeBarModuleLogic::parseSystemdIdleInhibitors(const QString& output) const
    -> QVariantList {
  return qsn::takeCborList(
      QsNative_BarModuleLogic_ParseSystemdIdleInhibitors(output.toUtf8().constData()));
}

auto QsNativeBarModuleLogic::parsePortalSessionCount(const QString& output) const -> int {
  return qsn::takeCbor(QsNative_BarModuleLogic_ParsePortalSessionCount(output.toUtf8().constData()))
      .toInt();
}

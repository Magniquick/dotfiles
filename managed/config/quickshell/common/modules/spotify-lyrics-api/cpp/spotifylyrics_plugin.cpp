#include <QtQml/qqmlextensionplugin.h>
#include <QtQml/qqml.h>

#include "SpotifyLyricsClient.h"

class spotifylyrics_plugin : public QQmlExtensionPlugin
{
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char *uri) override
  {
    // uri is expected to be "spotifylyrics" from qmldir.
    qmlRegisterType<SpotifyLyricsClient>(uri, 1, 0, "SpotifyLyricsClient");
  }
};

#include "spotifylyrics_plugin.moc"


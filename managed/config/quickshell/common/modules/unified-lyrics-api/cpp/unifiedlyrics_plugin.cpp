#include <QtQml/qqmlextensionplugin.h>
#include <QtQml/qqml.h>

#include "UnifiedLyricsClient.h"

class unifiedlyrics_plugin : public QQmlExtensionPlugin
{
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char *uri) override
  {
    qmlRegisterType<UnifiedLyricsClient>(uri, 1, 0, "UnifiedLyricsClient");
  }
};

#include "unifiedlyrics_plugin.moc"

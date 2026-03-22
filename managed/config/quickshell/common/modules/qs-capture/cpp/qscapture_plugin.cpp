#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "CaptureProvider.h"

class qscapture_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char *uri) override
  {
    qmlRegisterType<CaptureProvider>(uri, 1, 0, "CaptureProvider");
  }
};

#include "qscapture_plugin.moc"

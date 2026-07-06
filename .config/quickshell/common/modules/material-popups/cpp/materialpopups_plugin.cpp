#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "QsNativeMaterialPopup.h"

class materialpopups_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override {
    qmlRegisterType<QsNativeMaterialPopup>(uri, 1, 0, "MaterialPopupBackend");
  }
};

#include "materialpopups_plugin.moc"

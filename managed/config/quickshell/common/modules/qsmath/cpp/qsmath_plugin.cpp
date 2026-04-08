#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "MathRenderer.h"

class qsmath_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override {
    qmlRegisterType<MathRenderer>(uri, 1, 0, "MathRenderer");
  }
};

#include "qsmath_plugin.moc"

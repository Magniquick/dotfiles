#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "MathRenderer.h"
#include <qsmath_stream/src/markdown_stream.cxxqt.h>

class qsmath_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override {
    qmlRegisterType<MathRenderer>(uri, 1, 0, "MathRenderer");
    qmlRegisterType<MarkdownStreamModel>(uri, 1, 0, "MarkdownStreamModel");
  }
};

#include "qsmath_plugin.moc"

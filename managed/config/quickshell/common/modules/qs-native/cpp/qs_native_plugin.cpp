#include <QtQml/qqmlextensionplugin.h>

void qml_register_types_qs_native();

class qs_native_plugin : public QQmlExtensionPlugin
{
    Q_OBJECT
    Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
    void registerTypes(const char *uri) override
    {
        Q_UNUSED(uri);
    }
};

#include "qs_native_plugin.moc"

#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "QsNativeAiSession.h"
#include "QsNativeBarModuleLogic.h"

#include <qsnative_rust/src/backlight.cxxqt.h>
#include <qsnative_rust/src/bluetooth.cxxqt.h>
#include <qsnative_rust/src/config_resolver.cxxqt.h>
#include <qsnative_rust/src/ical.cxxqt.h>
#include <qsnative_rust/src/idle.cxxqt.h>
#include <qsnative_rust/src/net_stats.cxxqt.h>
#include <qsnative_rust/src/pacman.cxxqt.h>
#include <qsnative_rust/src/privacy.cxxqt.h>
#include <qsnative_rust/src/sys_info.cxxqt.h>
#include <qsnative_rust/src/systemd_failed.cxxqt.h>
#include <qsnative_rust/src/todoist.cxxqt.h>

class qsnative_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override {
    // uri is expected to be "qsnative" from qmldir.
    qmlRegisterType<SysInfoProvider>(uri, 1, 0, "SysInfoProvider");
    qmlRegisterType<BacklightProvider>(uri, 1, 0, "BacklightProvider");
    qmlRegisterType<BluetoothDiagnosticsProvider>(uri, 1, 0, "BluetoothDiagnosticsProvider");
    qmlRegisterType<ConfigResolver>(uri, 1, 0, "ConfigResolver");
    qmlRegisterType<QsNativeAiSession>(uri, 1, 0, "AiChatSession");
    qmlRegisterType<QsNativeBarModuleLogic>(uri, 1, 0, "BarModuleLogic");
    qmlRegisterType<PacmanUpdatesProvider>(uri, 1, 0, "PacmanUpdatesProvider");
    qmlRegisterType<PrivacyProvider>(uri, 1, 0, "PrivacyProvider");
    qmlRegisterType<IcalCache>(uri, 1, 0, "IcalCache");
    qmlRegisterType<IdleProvider>(uri, 1, 0, "IdleProvider");
    qmlRegisterType<TodoistClient>(uri, 1, 0, "TodoistClient");
    qmlRegisterType<SystemdFailedProvider>(uri, 1, 0, "SystemdFailedProvider");
    qmlRegisterType<NetStatsProvider>(uri, 1, 0, "NetStatsProvider");
  }
};

#include "qsnative_plugin.moc"

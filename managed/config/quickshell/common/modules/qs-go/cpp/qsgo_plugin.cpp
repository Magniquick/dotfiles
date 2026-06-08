#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "QsGoAiSession.h"
#include "QsGoBacklight.h"
#include "QsGoConfigResolver.h"
#include "QsGoIcal.h"
#include "QsGoNetStats.h"
#include "QsGoPacman.h"
#include "QsGoSysInfo.h"
#include "QsGoSystemdFailed.h"
#include "QsGoTodoist.h"

class qsgo_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override {
    // uri is expected to be "qsgo" from qmldir.
    qmlRegisterType<QsGoSysInfo>(uri, 1, 0, "SysInfoProvider");
    qmlRegisterType<QsGoBacklight>(uri, 1, 0, "BacklightProvider");
    qmlRegisterType<QsGoConfigResolver>(uri, 1, 0, "ConfigResolver");
    qmlRegisterType<QsGoAiSession>(uri, 1, 0, "AiChatSession");
    qmlRegisterType<QsGoPacman>(uri, 1, 0, "PacmanUpdatesProvider");
    qmlRegisterType<QsGoIcal>(uri, 1, 0, "IcalCache");
    qmlRegisterType<QsGoTodoist>(uri, 1, 0, "TodoistClient");
    qmlRegisterType<QsGoSystemdFailed>(uri, 1, 0, "SystemdFailedProvider");
    qmlRegisterType<QsGoNetStats>(uri, 1, 0, "NetStatsProvider");
  }
};

#include "qsgo_plugin.moc"

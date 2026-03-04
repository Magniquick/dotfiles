#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "QsGoAiModels.h"
#include "QsGoAiSession.h"
#include "QsGoBacklight.h"
#include "QsGoIcal.h"
#include "QsGoPacman.h"
#include "QsGoSysInfo.h"
#include "QsGoTodoist.h"

class qsgo_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override
  {
    // uri is expected to be "qsgo" from qmldir.
    qmlRegisterType<QsGoSysInfo>   (uri, 1, 0, "SysInfoProvider");
    qmlRegisterType<QsGoBacklight> (uri, 1, 0, "BacklightProvider");
    qmlRegisterType<QsGoAiSession> (uri, 1, 0, "AiChatSession");
    qmlRegisterType<QsGoAiModels>  (uri, 1, 0, "AiModelCatalog");
    qmlRegisterType<QsGoPacman>    (uri, 1, 0, "PacmanUpdatesProvider");
    qmlRegisterType<QsGoIcal>      (uri, 1, 0, "IcalCache");
    qmlRegisterType<QsGoTodoist>   (uri, 1, 0, "TodoistClient");
  }
};

#include "qsgo_plugin.moc"

#include <QtQml/qqml.h>
#include <QtQml/qqmlextensionplugin.h>

#include "qsnative_api.h"

#include "QsNativeAiSession.h"
#include "QsNativeBacklight.h"
#include "QsNativeBarModuleLogic.h"
#include "QsNativeBluetooth.h"
#include "QsNativeConfigResolver.h"
#include "QsNativeIcal.h"
#include "QsNativeIdle.h"
#include "QsNativeKeyboardLock.h"
#include "QsNativeNetStats.h"
#include "QsNativePacman.h"
#include "QsNativePrivacy.h"
#include "QsNativeSysInfo.h"
#include "QsNativeSystemdFailedProvider.h"
#include "QsNativeTodoist.h"

class qsnative_plugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID "org.qt-project.Qt.QQmlEngineExtensionInterface")

public:
  void registerTypes(const char* uri) override {
    // uri is expected to be "qsnative" from qmldir.
    // Install the fatal-abort panic hook once, up front (previously coupled to
    // IcalCache::initialize under cxx-qt).
    QsNative_InstallPanicHook();

    qmlRegisterType<QsNativeSysInfo>(uri, 1, 0, "SysInfoProvider");
    qmlRegisterType<QsNativeBacklight>(uri, 1, 0, "BacklightProvider");
    qmlRegisterType<QsNativeBluetooth>(uri, 1, 0, "BluetoothDiagnosticsProvider");
    qmlRegisterType<QsNativeConfigResolver>(uri, 1, 0, "ConfigResolver");
    qmlRegisterType<QsNativeAiSession>(uri, 1, 0, "AiChatSession");
    qmlRegisterType<QsNativeBarModuleLogic>(uri, 1, 0, "BarModuleLogic");
    qmlRegisterType<QsNativePacman>(uri, 1, 0, "PacmanUpdatesProvider");
    qmlRegisterType<QsNativePrivacy>(uri, 1, 0, "PrivacyProvider");
    qmlRegisterType<QsNativeIcal>(uri, 1, 0, "IcalCache");
    qmlRegisterType<QsNativeIdle>(uri, 1, 0, "IdleProvider");
    qmlRegisterType<QsNativeKeyboardLock>(uri, 1, 0, "KeyboardLockProvider");
    qmlRegisterType<QsNativeTodoist>(uri, 1, 0, "TodoistClient");
    qmlRegisterType<QsNativeSystemdFailedProvider>(uri, 1, 0, "SystemdFailedProvider");
    qmlRegisterType<QsNativeNetStats>(uri, 1, 0, "NetStatsProvider");
  }
};

#include "qsnative_plugin.moc"

cmake_minimum_required(VERSION 3.24)
project(qsnative LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/QuickshellCompilerOptions.cmake")

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml)

if(EXISTS "/usr/lib/qt6/bin/qmlplugindump")
    set(QMLPLUGINDUMP_EXECUTABLE "/usr/lib/qt6/bin/qmlplugindump")
else()
    find_program(QMLPLUGINDUMP_EXECUTABLE qmlplugindump REQUIRED)
endif()

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/qsnative")
set(QSNATIVE_SECRETS_BIN "${CMAKE_CURRENT_BINARY_DIR}/qs-secrets")
set(QSNATIVE_GOOGLE_AUTH_BIN "${CMAKE_CURRENT_BINARY_DIR}/qs-google-auth")

add_custom_command(
    OUTPUT "${QSNATIVE_SECRETS_BIN}" "${QSNATIVE_GOOGLE_AUTH_BIN}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${QS_CARGO_RELEASE_DIR}/qs-secrets"
        "${QSNATIVE_SECRETS_BIN}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${QS_CARGO_RELEASE_DIR}/qs-google-auth"
        "${QSNATIVE_GOOGLE_AUTH_BIN}"
    DEPENDS qs_rust_workspace_build
)
add_custom_target(qsnative_helper_bins ALL DEPENDS "${QSNATIVE_SECRETS_BIN}" "${QSNATIVE_GOOGLE_AUTH_BIN}")

add_library(qsnative_plugin SHARED
    cpp/qsnative_plugin.cpp
    cpp/QsNativeAiSession.cpp
    cpp/QsNativeBarModuleLogic.cpp
    cpp/QsNativeSysInfo.cpp
    cpp/QsNativeBacklight.cpp
    cpp/QsNativeBluetooth.cpp
    cpp/QsNativeConfigResolver.cpp
    cpp/QsNativeIcal.cpp
    cpp/QsNativeIdle.cpp
    cpp/QsNativeKeyboardLock.cpp
    cpp/QsNativeNetStats.cpp
    cpp/QsNativePacman.cpp
    cpp/QsNativePrivacy.cpp
    cpp/QsNativeSystemdFailedProvider.cpp
    cpp/QsNativeTodoist.cpp
)

set_target_properties(qsnative_plugin
    PROPERTIES
    OUTPUT_NAME "qsnative"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

# cpp/ holds both the hand-written QObject headers and the cbindgen-generated
# qsnative_api.h (emitted by the Rust build.rs during qs_rust_workspace_build).
target_include_directories(qsnative_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
)

target_compile_options(qsnative_plugin PRIVATE
    $<$<COMPILE_LANGUAGE:CXX>:$<$<CONFIG:Release>:-O3>>
    $<$<COMPILE_LANGUAGE:CXX>:$<$<CONFIG:RelWithDebInfo>:-O3>>
)
qs_apply_common_compile_options(qsnative_plugin)

add_dependencies(qsnative_plugin qsnative_helper_bins)

target_link_libraries(qsnative_plugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
)
qs_link_rust_static(qsnative_plugin qsnative_rust)
# rusqlite is unbundled (system sqlite): the Rust staticlib references sqlite3_*
# but cargo's `-lsqlite3` link directive doesn't flow through a .a, so link it here.
target_link_libraries(qsnative_plugin PRIVATE sqlite3)

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/types.qmltypes"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${QML_MODULE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/qsnative/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DQMLPLUGINDUMP_EXECUTABLE="${QMLPLUGINDUMP_EXECUTABLE}"
        -DMODULE_URI=qsnative
        -DMODULE_VERSION=1.0
        -DIMPORT_ROOT="${CMAKE_CURRENT_BINARY_DIR}/qml"
        -DOUTPUT_QMLTYPES="${QML_MODULE_DIR}/types.qmltypes"
        -DQML_IMPORT_PATH_VALUE="/usr/lib/qt6/qml:${CMAKE_CURRENT_BINARY_DIR}/qml"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/generate_qmltypes_with_qmlplugindump.cmake"
    DEPENDS qsnative_plugin "${CMAKE_CURRENT_LIST_DIR}/qml/qsnative/qmldir"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Generating qsnative qmltypes"
)
add_custom_target(qsnative_qmltypes ALL DEPENDS "${QML_MODULE_DIR}/types.qmltypes")

# Copy qmldir into the build output so `QML_IMPORT_PATH=.../build/qml` works,
# and advertise the generated qmltypes metadata there.
add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DINPUT_QMLDIR="${CMAKE_CURRENT_LIST_DIR}/qml/qsnative/qmldir"
        -DOUTPUT_QMLDIR="${QML_MODULE_DIR}/qmldir"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/write_qmldir_with_typeinfo.cmake"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/qsnative/qmldir" "${QML_MODULE_DIR}/types.qmltypes"
)
add_custom_target(qsnative_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")
add_dependencies(qsnative_qmldir qsnative_plugin)

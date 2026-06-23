cmake_minimum_required(VERSION 3.24)
project(unifiedlyrics LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/QuickshellCompilerOptions.cmake")

find_package(Qt6 REQUIRED COMPONENTS Core Qml)
if(EXISTS "/usr/lib/qt6/bin/qmlplugindump")
    set(QMLPLUGINDUMP_EXECUTABLE "/usr/lib/qt6/bin/qmlplugindump")
else()
    find_program(QMLPLUGINDUMP_EXECUTABLE qmlplugindump REQUIRED)
endif()

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/unifiedlyrics")

set(UNIFIEDLYRICS_RUST_CRATE unifiedlyrics_rust)
set(UNIFIEDLYRICS_RUST_DIR "${CMAKE_CURRENT_LIST_DIR}/unifiedlyrics-rust")

if(NOT EXISTS "${UNIFIEDLYRICS_RUST_DIR}/Cargo.toml")
    message(FATAL_ERROR
        "unifiedlyrics Rust backend missing: expected ${UNIFIEDLYRICS_RUST_DIR}/Cargo.toml"
    )
endif()

set(UNIFIEDLYRICS_CXXQT_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated-cxxqt/include")
add_custom_command(
    OUTPUT "${UNIFIEDLYRICS_CXXQT_INCLUDE_DIR}/unifiedlyrics_rust/src/lib.cxxqt.h"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${UNIFIEDLYRICS_CXXQT_INCLUDE_DIR}/unifiedlyrics_rust/src"
    COMMAND /bin/sh -c
        "cp -R ${QS_CXXQT_CRATES_DIR}/unifiedlyrics_rust/include/. '${UNIFIEDLYRICS_CXXQT_INCLUDE_DIR}/'"
    DEPENDS qs_rust_workspace_build
    VERBATIM
)
add_custom_target(unifiedlyrics_rust_headers
    DEPENDS "${UNIFIEDLYRICS_CXXQT_INCLUDE_DIR}/unifiedlyrics_rust/src/lib.cxxqt.h"
)

add_library(unifiedlyrics_plugin SHARED
    cpp/unifiedlyrics_plugin.cpp
)

set_target_properties(unifiedlyrics_plugin
    PROPERTIES
    OUTPUT_NAME "unifiedlyrics"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(unifiedlyrics_plugin PRIVATE
    "${UNIFIEDLYRICS_CXXQT_INCLUDE_DIR}"
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
)

qs_apply_common_compile_options(unifiedlyrics_plugin)

target_link_libraries(unifiedlyrics_plugin PRIVATE
    Qt6::Core
    Qt6::Qml
)
qs_link_rust_static(unifiedlyrics_plugin ${UNIFIEDLYRICS_RUST_CRATE})
add_dependencies(unifiedlyrics_plugin unifiedlyrics_rust_headers)

set_target_properties(unifiedlyrics_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/types.qmltypes"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${QML_MODULE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/unifiedlyrics/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DQMLPLUGINDUMP_EXECUTABLE="${QMLPLUGINDUMP_EXECUTABLE}"
        -DMODULE_URI=unifiedlyrics
        -DMODULE_VERSION=1.0
        -DIMPORT_ROOT="${CMAKE_CURRENT_BINARY_DIR}/qml"
        -DOUTPUT_QMLTYPES="${QML_MODULE_DIR}/types.qmltypes"
        -DQML_IMPORT_PATH_VALUE="/usr/lib/qt6/qml:${CMAKE_CURRENT_BINARY_DIR}/qml"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/generate_qmltypes_with_qmlplugindump.cmake"
    DEPENDS unifiedlyrics_plugin "${CMAKE_CURRENT_LIST_DIR}/qml/unifiedlyrics/qmldir"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Generating unifiedlyrics qmltypes"
)
add_custom_target(unifiedlyrics_qmltypes ALL DEPENDS "${QML_MODULE_DIR}/types.qmltypes")

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DINPUT_QMLDIR="${CMAKE_CURRENT_LIST_DIR}/qml/unifiedlyrics/qmldir"
        -DOUTPUT_QMLDIR="${QML_MODULE_DIR}/qmldir"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/write_qmldir_with_typeinfo.cmake"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/unifiedlyrics/qmldir" "${QML_MODULE_DIR}/types.qmltypes"
)
add_custom_target(unifiedlyrics_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")
add_dependencies(unifiedlyrics_qmldir unifiedlyrics_plugin)

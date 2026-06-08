cmake_minimum_required(VERSION 3.24)
project(materialpopups LANGUAGES CXX)

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

include(FetchContent)
FetchContent_Declare(
    CxxQt
    GIT_REPOSITORY https://github.com/kdab/cxx-qt-cmake.git
    GIT_TAG main
)
FetchContent_MakeAvailable(CxxQt)

cxx_qt_import_crate(
    MANIFEST_PATH "${CMAKE_CURRENT_LIST_DIR}/material-popups-backend/Cargo.toml"
    CRATES material_popups_backend
    QT_MODULES Qt6::Core Qt6::Qml
)

get_target_property(MATERIAL_POPUPS_LINK_LIBRARIES material_popups_backend INTERFACE_LINK_LIBRARIES)
if(MATERIAL_POPUPS_LINK_LIBRARIES)
    list(FILTER MATERIAL_POPUPS_LINK_LIBRARIES EXCLUDE REGEX "material_popups_backend_initializers")
    list(FILTER MATERIAL_POPUPS_LINK_LIBRARIES EXCLUDE REGEX "TARGET_OBJECTS:material_popups_backend_initializers")
    set_target_properties(material_popups_backend PROPERTIES
        INTERFACE_LINK_LIBRARIES "${MATERIAL_POPUPS_LINK_LIBRARIES}"
    )
endif()

set(MATERIAL_POPUPS_CXXQT_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated-cxxqt/include")
add_custom_command(
    OUTPUT "${MATERIAL_POPUPS_CXXQT_INCLUDE_DIR}/material_popups_backend/src/backend.cxxqt.h"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${MATERIAL_POPUPS_CXXQT_INCLUDE_DIR}/material_popups_backend/src"
    COMMAND /bin/sh -c
        "cp -R ${CMAKE_CURRENT_BINARY_DIR}/cxxqt/crates/material_popups_backend/include/. '${MATERIAL_POPUPS_CXXQT_INCLUDE_DIR}/'"
    DEPENDS material_popups_backend
    VERBATIM
)
add_custom_target(material_popups_backend_headers
    DEPENDS "${MATERIAL_POPUPS_CXXQT_INCLUDE_DIR}/material_popups_backend/src/backend.cxxqt.h"
)

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/materialpopups")

add_library(materialpopups_plugin SHARED
    cpp/materialpopups_plugin.cpp
)

set_target_properties(materialpopups_plugin
    PROPERTIES
    OUTPUT_NAME "materialpopups"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(materialpopups_plugin PRIVATE
    "${MATERIAL_POPUPS_CXXQT_INCLUDE_DIR}"
)

qs_apply_common_compile_options(materialpopups_plugin)

target_link_libraries(materialpopups_plugin PRIVATE
    material_popups_backend
    Qt6::Core
    Qt6::Qml
)
add_dependencies(materialpopups_plugin material_popups_backend_headers)

set_target_properties(materialpopups_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/types.qmltypes"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${QML_MODULE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/materialpopups/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DQMLPLUGINDUMP_EXECUTABLE="${QMLPLUGINDUMP_EXECUTABLE}"
        -DMODULE_URI=materialpopups
        -DMODULE_VERSION=1.0
        -DIMPORT_ROOT="${CMAKE_CURRENT_BINARY_DIR}/qml"
        -DOUTPUT_QMLTYPES="${QML_MODULE_DIR}/types.qmltypes"
        -DQML_IMPORT_PATH_VALUE="/usr/lib/qt6/qml:${CMAKE_CURRENT_BINARY_DIR}/qml"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/generate_qmltypes_with_qmlplugindump.cmake"
    DEPENDS materialpopups_plugin "${CMAKE_CURRENT_LIST_DIR}/qml/materialpopups/qmldir"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Generating materialpopups qmltypes"
)
add_custom_target(materialpopups_qmltypes ALL DEPENDS "${QML_MODULE_DIR}/types.qmltypes")

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DINPUT_QMLDIR="${CMAKE_CURRENT_LIST_DIR}/qml/materialpopups/qmldir"
        -DOUTPUT_QMLDIR="${QML_MODULE_DIR}/qmldir"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/write_qmldir_with_typeinfo.cmake"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/materialpopups/qmldir" "${QML_MODULE_DIR}/types.qmltypes"
)
add_custom_target(materialpopups_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")
add_dependencies(materialpopups_qmldir materialpopups_plugin)

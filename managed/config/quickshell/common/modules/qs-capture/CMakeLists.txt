cmake_minimum_required(VERSION 3.21)
project(qscapture LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Concurrent)
if(EXISTS "/usr/lib/qt6/bin/qmlplugindump")
    set(QMLPLUGINDUMP_EXECUTABLE "/usr/lib/qt6/bin/qmlplugindump")
else()
    find_program(QMLPLUGINDUMP_EXECUTABLE qmlplugindump REQUIRED)
endif()
find_package(PkgConfig REQUIRED)
pkg_check_modules(PIXMAN REQUIRED pixman-1)
pkg_check_modules(PNG REQUIRED libpng)
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols)
pkg_get_variable(WAYLAND_PROTOCOLS_PKGDATADIR wayland-protocols pkgdatadir)

find_program(WAYLAND_SCANNER_EXECUTABLE wayland-scanner REQUIRED)

set(PROTOCOL_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/protocol")
file(MAKE_DIRECTORY "${PROTOCOL_BUILD_DIR}")

set(PROTOCOL_XMLS
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/staging/ext-foreign-toplevel-list/ext-foreign-toplevel-list-v1.xml"
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/staging/ext-image-capture-source/ext-image-capture-source-v1.xml"
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/staging/ext-image-copy-capture/ext-image-copy-capture-v1.xml"
    "${WAYLAND_PROTOCOLS_PKGDATADIR}/unstable/xdg-output/xdg-output-unstable-v1.xml"
    "${CMAKE_CURRENT_LIST_DIR}/protocol/wlr-screencopy-unstable-v1.xml"
)

set(PROTOCOL_SRCS)
foreach(XML_PATH IN LISTS PROTOCOL_XMLS)
    get_filename_component(XML_NAME "${XML_PATH}" NAME_WE)
    set(PROTOCOL_HEADER "${PROTOCOL_BUILD_DIR}/${XML_NAME}-protocol.h")
    set(PROTOCOL_SOURCE "${PROTOCOL_BUILD_DIR}/${XML_NAME}-protocol.c")

    add_custom_command(
        OUTPUT "${PROTOCOL_HEADER}"
        COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" client-header "${XML_PATH}" "${PROTOCOL_HEADER}"
        DEPENDS "${XML_PATH}"
        COMMENT "Generating ${XML_NAME} client header"
    )
    add_custom_command(
        OUTPUT "${PROTOCOL_SOURCE}"
        COMMAND "${WAYLAND_SCANNER_EXECUTABLE}" private-code "${XML_PATH}" "${PROTOCOL_SOURCE}"
        DEPENDS "${XML_PATH}"
        COMMENT "Generating ${XML_NAME} protocol code"
    )

    list(APPEND PROTOCOL_SRCS "${PROTOCOL_HEADER}" "${PROTOCOL_SOURCE}")
endforeach()

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/qscapture")

add_library(qscapture_plugin SHARED
    cpp/CaptureProvider.cpp
    cpp/qscapture_plugin.cpp
    vendor/grim/src/buffer.c
    vendor/grim/src/box.c
    vendor/grim/src/output-layout.c
    vendor/grim/src/render.c
    vendor/grim/src/write_png.c
    vendor/grim/src/capture_core.c
    ${PROTOCOL_SRCS}
)

set_target_properties(qscapture_plugin
    PROPERTIES
    OUTPUT_NAME "qscapture"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(qscapture_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
    "${CMAKE_CURRENT_LIST_DIR}/vendor/grim/include"
    "${PROTOCOL_BUILD_DIR}"
    ${PIXMAN_INCLUDE_DIRS}
    ${PNG_INCLUDE_DIRS}
    ${WAYLAND_CLIENT_INCLUDE_DIRS}
)

target_compile_definitions(qscapture_plugin PRIVATE
    _GNU_SOURCE
    _POSIX_C_SOURCE=200809L
    GRIM_LITTLE_ENDIAN=1
)

if(QS_NATIVE_CPU)
    target_compile_options(qscapture_plugin PRIVATE -march=native -mtune=native)
endif()

target_link_libraries(qscapture_plugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Concurrent
    ${PIXMAN_LIBRARIES}
    ${PNG_LIBRARIES}
    ${WAYLAND_CLIENT_LIBRARIES}
    m
    rt
)

set_target_properties(qscapture_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/types.qmltypes"
    COMMAND "${CMAKE_COMMAND}"
        -DQMLPLUGINDUMP_EXECUTABLE="${QMLPLUGINDUMP_EXECUTABLE}"
        -DMODULE_URI=qscapture
        -DMODULE_VERSION=1.0
        -DIMPORT_ROOT="${CMAKE_CURRENT_BINARY_DIR}/qml"
        -DOUTPUT_QMLTYPES="${QML_MODULE_DIR}/types.qmltypes"
        -DQML_IMPORT_PATH_VALUE="/usr/lib/qt6/qml:${CMAKE_CURRENT_BINARY_DIR}/qml"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/generate_qmltypes_with_qmlplugindump.cmake"
    DEPENDS qscapture_plugin "${CMAKE_CURRENT_LIST_DIR}/qml/qscapture/qmldir"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Generating qscapture qmltypes"
)
add_custom_target(qscapture_qmltypes ALL DEPENDS "${QML_MODULE_DIR}/types.qmltypes")

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}"
        -DINPUT_QMLDIR="${CMAKE_CURRENT_LIST_DIR}/qml/qscapture/qmldir"
        -DOUTPUT_QMLDIR="${QML_MODULE_DIR}/qmldir"
        -P "${CMAKE_CURRENT_LIST_DIR}/../cmake/write_qmldir_with_typeinfo.cmake"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/qscapture/qmldir" qscapture_qmltypes
)
add_custom_target(qscapture_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")

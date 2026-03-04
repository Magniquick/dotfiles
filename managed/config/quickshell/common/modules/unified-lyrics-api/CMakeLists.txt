cmake_minimum_required(VERSION 3.21)
project(unifiedlyrics LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Concurrent)
find_program(GO_EXECUTABLE go REQUIRED)

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/unifiedlyrics")
set(UNIFIED_LYRICS_GO_LIB "${QML_MODULE_DIR}/libunifiedlyrics_go.so")

add_custom_command(
    OUTPUT "${UNIFIED_LYRICS_GO_LIB}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${QML_MODULE_DIR}"
    COMMAND "${GO_EXECUTABLE}" build -buildmode=c-shared -o "${UNIFIED_LYRICS_GO_LIB}" ./capi
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Building unified-lyrics Go shared library"
)
add_custom_target(unifiedlyrics_go_lib DEPENDS "${UNIFIED_LYRICS_GO_LIB}")

add_library(unifiedlyrics_plugin SHARED
    cpp/unifiedlyrics_plugin.cpp
    cpp/UnifiedLyricsClient.cpp
)

set_target_properties(unifiedlyrics_plugin
    PROPERTIES
    OUTPUT_NAME "unifiedlyrics"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(unifiedlyrics_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
)

add_dependencies(unifiedlyrics_plugin unifiedlyrics_go_lib)

target_link_libraries(unifiedlyrics_plugin PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Concurrent
    "${UNIFIED_LYRICS_GO_LIB}"
)

set_target_properties(unifiedlyrics_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/unifiedlyrics/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/unifiedlyrics/qmldir"
)
add_custom_target(unifiedlyrics_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")
add_dependencies(unifiedlyrics_qmldir unifiedlyrics_plugin)

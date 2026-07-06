cmake_minimum_required(VERSION 3.24)
project(qsmath LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)
include("${CMAKE_CURRENT_LIST_DIR}/../cmake/QuickshellCompilerOptions.cmake")

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Concurrent)

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/qsmath")
set(QSMATH_RENDERER "${CMAKE_CURRENT_BINARY_DIR}/qsmath-render-svg")

add_custom_command(
    OUTPUT "${QSMATH_RENDERER}"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${QS_CARGO_RELEASE_DIR}/qsmath-render-svg"
        "${QSMATH_RENDERER}"
    DEPENDS qs_rust_workspace_build
)
add_custom_target(qsmath_renderer ALL DEPENDS "${QSMATH_RENDERER}")

add_library(qsmath_plugin SHARED
    cpp/MathRenderer.cpp
    cpp/qsmath_plugin.cpp
    cpp/QsNativeMarkdownStream.cpp
)

set_target_properties(qsmath_plugin
    PROPERTIES
    OUTPUT_NAME "qsmath"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(qsmath_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
)

target_compile_definitions(qsmath_plugin PRIVATE
    QSMATH_RENDERER_PATH="${QSMATH_RENDERER}"
)

qs_apply_common_compile_options(qsmath_plugin)

target_link_libraries(qsmath_plugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Concurrent
)
qs_link_rust_static(qsmath_plugin qsmath_stream)
add_dependencies(qsmath_plugin qsmath_renderer)

set_target_properties(qsmath_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/qsmath/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/qsmath/qmldir" qsmath_plugin
)
add_custom_target(qsmath_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")

include(CTest)
if(BUILD_TESTING)
    find_package(Qt6 REQUIRED COMPONENTS Test)

    add_executable(qsmath_render_smoke
        tests/render_smoke.cpp
        cpp/MathRenderer.cpp
    )
    target_include_directories(qsmath_render_smoke PRIVATE
        "${CMAKE_CURRENT_LIST_DIR}/cpp"
    )
    target_link_libraries(qsmath_render_smoke PRIVATE
        Qt6::Core
        Qt6::Gui
        Qt6::Concurrent
        Qt6::Test
    )
    qs_link_rust_static(qsmath_render_smoke qsmath_stream)
    target_compile_definitions(qsmath_render_smoke PRIVATE
        QSMATH_RENDERER_PATH="${QSMATH_RENDERER}"
    )
    qs_apply_common_compile_options(qsmath_render_smoke)
    add_dependencies(qsmath_render_smoke qsmath_renderer)
    add_test(NAME qsmath_render_smoke COMMAND qsmath_render_smoke)
endif()

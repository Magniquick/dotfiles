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
find_program(CARGO_EXECUTABLE cargo REQUIRED)

include(FetchContent)
FetchContent_Declare(
    CxxQt
    GIT_REPOSITORY https://github.com/kdab/cxx-qt-cmake.git
    GIT_TAG main
)
FetchContent_MakeAvailable(CxxQt)

cxx_qt_import_crate(
    MANIFEST_PATH "${CMAKE_CURRENT_LIST_DIR}/ratex-helper/Cargo.toml"
    CRATES qsmath_stream
    QT_MODULES Qt6::Core Qt6::Gui Qt6::Qml
)

# qsmath registers Rust-backed types from the existing QML plugin below. The
# crate is not a standalone CXX-Qt QML module, so cxx-qt-cmake's static-module
# initializer object is intentionally absent.
get_target_property(QSMATH_STREAM_LINK_LIBRARIES qsmath_stream INTERFACE_LINK_LIBRARIES)
if(QSMATH_STREAM_LINK_LIBRARIES)
    list(FILTER QSMATH_STREAM_LINK_LIBRARIES EXCLUDE REGEX "qsmath_stream_initializers")
    list(FILTER QSMATH_STREAM_LINK_LIBRARIES EXCLUDE REGEX "TARGET_OBJECTS:qsmath_stream_initializers")
    set_target_properties(qsmath_stream PROPERTIES
        INTERFACE_LINK_LIBRARIES "${QSMATH_STREAM_LINK_LIBRARIES}"
    )
endif()

set(QSMATH_CXXQT_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated-cxxqt/include")
add_custom_command(
    OUTPUT "${QSMATH_CXXQT_INCLUDE_DIR}/qsmath_stream/src/markdown_stream.cxxqt.h"
    COMMAND "${CMAKE_COMMAND}" -E make_directory
        "${QSMATH_CXXQT_INCLUDE_DIR}/qsmath_stream/src"
    COMMAND /bin/sh -c
        "cp -R ${CMAKE_CURRENT_BINARY_DIR}/cargo/build/${Rust_CARGO_TARGET_CACHED}/release/build/qsmath_stream-*/out/cxxqtbuild/include/. '${QSMATH_CXXQT_INCLUDE_DIR}/'"
    DEPENDS qsmath_stream
    VERBATIM
)
add_custom_target(qsmath_stream_headers
    DEPENDS "${QSMATH_CXXQT_INCLUDE_DIR}/qsmath_stream/src/markdown_stream.cxxqt.h"
)

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/qsmath")
set(QSMATH_RENDERER "${CMAKE_CURRENT_BINARY_DIR}/qsmath-render-svg")

add_custom_command(
    OUTPUT "${QSMATH_RENDERER}"
    COMMAND "${CARGO_EXECUTABLE}" build
        --manifest-path "${CMAKE_CURRENT_LIST_DIR}/ratex-helper/Cargo.toml"
        --target-dir "${CMAKE_CURRENT_BINARY_DIR}/cargo"
        --release
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_BINARY_DIR}/cargo/release/qsmath-render-svg"
        "${QSMATH_RENDERER}"
    DEPENDS
        "${CMAKE_CURRENT_LIST_DIR}/ratex-helper/Cargo.toml"
        "${CMAKE_CURRENT_LIST_DIR}/ratex-helper/src/main.rs"
)
add_custom_target(qsmath_renderer ALL DEPENDS "${QSMATH_RENDERER}")

add_library(qsmath_plugin SHARED
    cpp/MathRenderer.cpp
    cpp/qsmath_plugin.cpp
)

set_target_properties(qsmath_plugin
    PROPERTIES
    OUTPUT_NAME "qsmath"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(qsmath_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
    "${QSMATH_CXXQT_INCLUDE_DIR}"
)

target_compile_definitions(qsmath_plugin PRIVATE
    QSMATH_RENDERER_PATH="${QSMATH_RENDERER}"
)

qs_apply_common_compile_options(qsmath_plugin)

target_link_libraries(qsmath_plugin PRIVATE
    qsmath_stream
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Concurrent
)
add_dependencies(qsmath_plugin qsmath_renderer)
add_dependencies(qsmath_plugin qsmath_stream_headers)

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
        "${QSMATH_CXXQT_INCLUDE_DIR}"
    )
    target_link_libraries(qsmath_render_smoke PRIVATE
        qsmath_stream
        Qt6::Core
        Qt6::Gui
        Qt6::Concurrent
        Qt6::Test
    )
    target_compile_definitions(qsmath_render_smoke PRIVATE
        QSMATH_RENDERER_PATH="${QSMATH_RENDERER}"
    )
    qs_apply_common_compile_options(qsmath_render_smoke)
    add_dependencies(qsmath_render_smoke qsmath_renderer)
    add_dependencies(qsmath_render_smoke qsmath_stream_headers)
    add_test(NAME qsmath_render_smoke COMMAND qsmath_render_smoke)
endif()

cmake_minimum_required(VERSION 3.21)
project(qsmath LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Concurrent)
find_package(PkgConfig REQUIRED)
pkg_check_modules(CLATEXMATH REQUIRED clatexmath)
pkg_check_modules(CAIROMM REQUIRED cairomm-1.0)

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/qsmath")

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
    ${CLATEXMATH_INCLUDE_DIRS}
    ${CAIROMM_INCLUDE_DIRS}
)

target_compile_definitions(qsmath_plugin PRIVATE
    BUILD_GTK
)

if(QS_NATIVE_CPU)
    target_compile_options(qsmath_plugin PRIVATE -march=native -mtune=native)
endif()

target_compile_options(qsmath_plugin PRIVATE
    ${CLATEXMATH_CFLAGS_OTHER}
    ${CAIROMM_CFLAGS_OTHER}
)

target_link_directories(qsmath_plugin PRIVATE
    ${CLATEXMATH_LIBRARY_DIRS}
    ${CAIROMM_LIBRARY_DIRS}
)

target_link_libraries(qsmath_plugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Concurrent
    ${CLATEXMATH_LIBRARIES}
    ${CAIROMM_LIBRARIES}
)

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

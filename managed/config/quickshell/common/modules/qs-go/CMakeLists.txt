cmake_minimum_required(VERSION 3.21)
project(qsgo LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml)

# Build the Go shared library once and keep it next to the QML module output.
find_program(GO_EXECUTABLE go REQUIRED)
set(QSGO_GO_BUILD_FLAGS "-trimpath" "-ldflags=-s -w")
set(QSGO_CGO_CFLAGS "-O3")
set(QSGO_CGO_CXXFLAGS "-O3")
if(QS_NATIVE_CPU)
    list(APPEND QSGO_CGO_CFLAGS "-march=native" "-mtune=native")
    list(APPEND QSGO_CGO_CXXFLAGS "-march=native" "-mtune=native")
endif()
string(JOIN " " QSGO_CGO_CFLAGS_STR ${QSGO_CGO_CFLAGS})
string(JOIN " " QSGO_CGO_CXXFLAGS_STR ${QSGO_CGO_CXXFLAGS})

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/qsgo")
set(QSGO_GO_LIB "${QML_MODULE_DIR}/libqsgo_go.so")

file(GLOB_RECURSE QSGO_GO_SOURCES
    "${CMAKE_CURRENT_LIST_DIR}/capi/*.go"
    "${CMAKE_CURRENT_LIST_DIR}/internal/*.go"
)

add_custom_command(
    OUTPUT "${QSGO_GO_LIB}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${QML_MODULE_DIR}"
    COMMAND "${CMAKE_COMMAND}" -E env
        "CGO_CFLAGS=${QSGO_CGO_CFLAGS_STR}"
        "CGO_CXXFLAGS=${QSGO_CGO_CXXFLAGS_STR}"
        "${GO_EXECUTABLE}" build -buildmode=c-shared ${QSGO_GO_BUILD_FLAGS} -o "${QSGO_GO_LIB}" ./capi
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    DEPENDS ${QSGO_GO_SOURCES}
    COMMENT "Building qs-go Go shared library"
)
add_custom_target(qsgo_go_lib DEPENDS "${QSGO_GO_LIB}")

add_library(qsgo_plugin SHARED
    cpp/qsgo_plugin.cpp
    cpp/QsGoSysInfo.cpp
    cpp/QsGoBacklight.cpp
    cpp/QsGoAiSession.cpp
    cpp/QsGoAiModels.cpp
    cpp/QsGoPacman.cpp
    cpp/QsGoIcal.cpp
    cpp/QsGoTodoist.cpp
)

set_target_properties(qsgo_plugin
    PROPERTIES
    OUTPUT_NAME "qsgo"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(qsgo_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
)

if(QS_NATIVE_CPU)
    target_compile_options(qsgo_plugin PRIVATE -march=native -mtune=native)
endif()

add_dependencies(qsgo_plugin qsgo_go_lib)

target_link_libraries(qsgo_plugin PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    "${QSGO_GO_LIB}"
)

set_target_properties(qsgo_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

# Copy qmldir into the build output so `QML_IMPORT_PATH=.../build/qml` works.
add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/qsgo/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/qsgo/qmldir"
)
add_custom_target(qsgo_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")
add_dependencies(qsgo_qmldir qsgo_plugin)

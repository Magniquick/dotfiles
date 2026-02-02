cmake_minimum_required(VERSION 3.21)
project(qs_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml)

include(FetchContent)
FetchContent_Declare(
    Corrosion
    GIT_REPOSITORY https://github.com/corrosion-rs/corrosion.git
    GIT_TAG v0.4.5
)
FetchContent_MakeAvailable(Corrosion)

find_package(CxxQt QUIET)
if(NOT CxxQt_FOUND)
    FetchContent_Declare(
        CxxQt
        GIT_REPOSITORY https://github.com/kdab/cxx-qt-cmake.git
        GIT_TAG main
    )
    FetchContent_MakeAvailable(CxxQt)
endif()

cxx_qt_import_crate(
    MANIFEST_PATH ${CMAKE_CURRENT_LIST_DIR}/Cargo.toml
    CRATES qs_native
    QT_MODULES Qt::Core Qt::Gui Qt::Qml
)

add_library(qs_native_rust_shared SHARED IMPORTED)
set_target_properties(qs_native_rust_shared
    PROPERTIES
    IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/libqs_native_rust.so"
)
add_dependencies(qs_native_rust_shared cargo-build_qs_native_rust)

set(GENERATED_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(GENERATED_CXXQT_ARCHIVE "${GENERATED_DIR}/libqs_native-cxxqt-generated.a")
set(GENERATED_HEADERS_DIR "${GENERATED_DIR}/include")
set(GENERATED_HEADERS_STAMP "${GENERATED_DIR}/headers.stamp")

add_custom_command(
    OUTPUT "${GENERATED_CXXQT_ARCHIVE}"
    COMMAND ${CMAKE_COMMAND}
        -DCARGO_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/cargo/build
        -DOUTPUT_ARCHIVE=${GENERATED_CXXQT_ARCHIVE}
        -P ${CMAKE_CURRENT_LIST_DIR}/cmake_copy_cxxqt_archive.cmake
    DEPENDS cargo-build_qs_native_rust
)
add_custom_target(qs_native_cxxqt_archive DEPENDS "${GENERATED_CXXQT_ARCHIVE}")

add_custom_command(
    OUTPUT "${GENERATED_HEADERS_STAMP}"
    COMMAND ${CMAKE_COMMAND}
        -DCARGO_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/cargo/build
        -DOUTPUT_DIR=${GENERATED_HEADERS_DIR}
        -DSTAMP_FILE=${GENERATED_HEADERS_STAMP}
        -P ${CMAKE_CURRENT_LIST_DIR}/cmake_copy_cxxqt_headers.cmake
    DEPENDS cargo-build_qs_native_rust
)

add_custom_target(qs_native_headers DEPENDS "${GENERATED_HEADERS_STAMP}")

add_library(qs_native_plugin SHARED cpp/qs_native_plugin.cpp)
set_target_properties(qs_native_plugin
    PROPERTIES
    OUTPUT_NAME "qsnative"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/qml/qsnative"
)
target_include_directories(qs_native_plugin PRIVATE
    "${GENERATED_HEADERS_DIR}/qs_native/src"
    "${GENERATED_HEADERS_DIR}"
)
add_dependencies(qs_native_plugin qs_native_headers qs_native_cxxqt_archive)
target_link_libraries(qs_native_plugin PRIVATE
    "${GENERATED_CXXQT_ARCHIVE}"
    qs_native_rust_shared
    Qt6::Qml
    Qt6::Core
    Qt6::Gui
)

add_custom_target(qs_native_qml_module_sync ALL
    COMMAND ${CMAKE_COMMAND}
        -DCARGO_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/cargo/build
        -DCXXQT_QML_DIR=${CMAKE_CURRENT_BINARY_DIR}/cxxqt/qml_modules/qsnative
        -DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/qml
        -P ${CMAKE_CURRENT_LIST_DIR}/cmake_copy_qml_module.cmake
    DEPENDS qs_native_plugin
)

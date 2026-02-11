cmake_minimum_required(VERSION 3.21)
project(qs_native LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml)

find_program(CARGO_EXECUTABLE cargo REQUIRED)
find_program(RUSTC_EXECUTABLE rustc REQUIRED)
find_program(QMAKE_EXECUTABLE NAMES qmake6 qmake REQUIRED)

execute_process(
    COMMAND "${RUSTC_EXECUTABLE}" -vV
    OUTPUT_VARIABLE RUSTC_VERSION_INFO
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
string(REGEX MATCH "host: ([^\n\r]+)" _RUSTC_HOST_MATCH "${RUSTC_VERSION_INFO}")
set(RUST_HOST_TRIPLE "${CMAKE_MATCH_1}")
if(NOT RUST_HOST_TRIPLE)
    message(FATAL_ERROR "Failed to detect rustc host target triple")
endif()

set(CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargo/build")
set(RUST_SHARED_LIB "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_SHARED_LIBRARY_PREFIX}qs_native_rust${CMAKE_SHARED_LIBRARY_SUFFIX}")

set(CARGO_PROFILE_FLAG "")
set(CARGO_PROFILE_DIR "debug")
if(CMAKE_BUILD_TYPE STREQUAL "Release" OR CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo" OR CMAKE_BUILD_TYPE STREQUAL "MinSizeRel")
    set(CARGO_PROFILE_FLAG "--release")
    set(CARGO_PROFILE_DIR "release")
endif()

set(RUST_SHARED_LIB_SRC "${CARGO_TARGET_DIR}/${CARGO_PROFILE_DIR}/${CMAKE_SHARED_LIBRARY_PREFIX}qs_native_rust${CMAKE_SHARED_LIBRARY_SUFFIX}")

add_custom_target(_cargo-build_qs_native_rust
    COMMAND ${CMAKE_COMMAND} -E env
        "CXX_QT_EXPORT_DIR=${CMAKE_CURRENT_BINARY_DIR}/cxxqt/"
        "CXX_QT_EXPORT_CRATE_qs_native_rust=1"
        "CXX_QT_QT_MODULES=Qt::Core,Qt::Gui,Qt::Qml"
        "QMAKE=${QMAKE_EXECUTABLE}"
        "CXX_${RUST_HOST_TRIPLE}=${CMAKE_CXX_COMPILER}"
        "CARGO_BUILD_RUSTC=${RUSTC_EXECUTABLE}"
        "${CARGO_EXECUTABLE}" rustc
            --lib
            --package qs_native
            --manifest-path "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml"
            ${CARGO_PROFILE_FLAG}
            --target-dir "${CARGO_TARGET_DIR}"
            --
            -Cdefault-linker-libraries=yes
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${RUST_SHARED_LIB_SRC}" "${RUST_SHARED_LIB}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    USES_TERMINAL
)

add_custom_target(cargo-build_qs_native_rust)
add_dependencies(cargo-build_qs_native_rust _cargo-build_qs_native_rust)

add_custom_target(cargo-clean_qs_native_rust
    COMMAND ${CMAKE_COMMAND} -E env
        "${CARGO_EXECUTABLE}" clean
            --manifest-path "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml"
            --target-dir "${CARGO_TARGET_DIR}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    USES_TERMINAL
)

if(NOT TARGET cargo-clean)
    add_custom_target(cargo-clean)
endif()
add_dependencies(cargo-clean cargo-clean_qs_native_rust)

add_library(qs_native_rust_shared SHARED IMPORTED)
set_target_properties(qs_native_rust_shared
    PROPERTIES
    IMPORTED_LOCATION "${RUST_SHARED_LIB}"
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
        -DCARGO_PROFILE_DIR=${CARGO_PROFILE_DIR}
        -DOUTPUT_ARCHIVE=${GENERATED_CXXQT_ARCHIVE}
        -P ${CMAKE_CURRENT_LIST_DIR}/cmake_copy_cxxqt_archive.cmake
    DEPENDS cargo-build_qs_native_rust
)
add_custom_target(qs_native_cxxqt_archive DEPENDS "${GENERATED_CXXQT_ARCHIVE}")

add_custom_command(
    OUTPUT "${GENERATED_HEADERS_STAMP}"
    COMMAND ${CMAKE_COMMAND}
        -DCARGO_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}/cargo/build
        -DCARGO_PROFILE_DIR=${CARGO_PROFILE_DIR}
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
        -DCARGO_PROFILE_DIR=${CARGO_PROFILE_DIR}
        -DCXXQT_QML_DIR=${CMAKE_CURRENT_BINARY_DIR}/cxxqt/qml_modules/qsnative
        -DOUTPUT_DIR=${CMAKE_CURRENT_BINARY_DIR}/qml
        -P ${CMAKE_CURRENT_LIST_DIR}/cmake_copy_qml_module.cmake
    DEPENDS qs_native_plugin
)

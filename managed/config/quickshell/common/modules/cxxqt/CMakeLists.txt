cmake_minimum_required(VERSION 3.24)
project(qs_cxxqt_modules LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml DBus Concurrent)
find_program(CARGO_EXECUTABLE cargo REQUIRED)
find_program(CLANGXX_EXECUTABLE clang++)

include(FetchContent)
FetchContent_Declare(
    CxxQt
    GIT_REPOSITORY https://github.com/kdab/cxx-qt-cmake.git
    GIT_TAG main
)
FetchContent_MakeAvailable(CxxQt)

set(QS_RUST_TARGET "x86_64-unknown-linux-gnu")
message(STATUS "Rust Target: ${QS_RUST_TARGET}")
string(REPLACE "-" "_" QS_RUST_TARGET_ENV "${QS_RUST_TARGET}")

get_target_property(QMAKE_EXECUTABLE Qt6::qmake IMPORTED_LOCATION)
set(QS_CXXQT_EXPORT_DIR "${CMAKE_CURRENT_BINARY_DIR}/cxxqt")
set(QS_CXXQT_CRATES_DIR "${QS_CXXQT_EXPORT_DIR}/crates")
set(QS_CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargo/build")
set(QS_CARGO_RELEASE_DIR "${QS_CARGO_TARGET_DIR}/${QS_RUST_TARGET}/release")
set(QS_RUST_NATIVE_LIBS gcc_s util rt pthread m dl c)
set(QS_RUST_CXX_COMPILER "${CMAKE_CXX_COMPILER}")
if(CLANGXX_EXECUTABLE)
    set(QS_RUST_CXX_COMPILER "${CLANGXX_EXECUTABLE}")
endif()
set(QS_RUST_CXXFLAGS "-O3 -march=native -mtune=native")
message(STATUS "Rust CXX compiler: ${QS_RUST_CXX_COMPILER}")

add_custom_target(qs_rust_workspace_build ALL
    COMMAND "${CMAKE_COMMAND}" -E env
        "CXX_QT_EXPORT_DIR=${QS_CXXQT_EXPORT_DIR}/"
        "CXX_QT_EXPORT_CRATE_qsnative_rust=1"
        "CXX_QT_EXPORT_CRATE_material_popups_backend=1"
        "CXX_QT_EXPORT_CRATE_qsmath_stream=1"
        "CXX_QT_EXPORT_CRATE_unifiedlyrics_rust=1"
        "CXX_QT_QT_MODULES=Qt6::Core,Qt6::Gui,Qt6::Qml,Qt6::DBus"
        "QMAKE=${QMAKE_EXECUTABLE}"
        "CXX_${QS_RUST_TARGET_ENV}=${QS_RUST_CXX_COMPILER}"
        "CXXFLAGS_${QS_RUST_TARGET_ENV}=${QS_RUST_CXXFLAGS}"
        "AR_${QS_RUST_TARGET_ENV}=${CMAKE_AR}"
        "CORROSION_BUILD_DIR=${CMAKE_CURRENT_BINARY_DIR}"
        "${CARGO_EXECUTABLE}" build
            --manifest-path "${CMAKE_CURRENT_LIST_DIR}/../Cargo.toml"
            --workspace
            --target-dir "${QS_CARGO_TARGET_DIR}"
            --release
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}/.."
    USES_TERMINAL
    BYPRODUCTS
        "${QS_CARGO_RELEASE_DIR}/libqsnative_rust.a"
        "${QS_CARGO_RELEASE_DIR}/libmaterial_popups_backend.a"
        "${QS_CARGO_RELEASE_DIR}/libqsmath_stream.a"
        "${QS_CARGO_RELEASE_DIR}/libunifiedlyrics_rust.a"
        "${QS_CARGO_RELEASE_DIR}/qs-secrets"
        "${QS_CARGO_RELEASE_DIR}/qs-google-auth"
        "${QS_CARGO_RELEASE_DIR}/qsmath-render-svg"
        "${QS_CXXQT_CRATES_DIR}/qsnative_rust/initializers.o"
        "${QS_CXXQT_CRATES_DIR}/material_popups_backend/initializers.o"
        "${QS_CXXQT_CRATES_DIR}/qsmath_stream/initializers.o"
        "${QS_CXXQT_CRATES_DIR}/unifiedlyrics_rust/initializers.o"
)

function(qs_link_rust_static target crate)
    add_dependencies(${target} qs_rust_workspace_build)
    target_link_libraries(${target} PRIVATE
        "${QS_CXXQT_CRATES_DIR}/${crate}/initializers.o"
        "${QS_CARGO_RELEASE_DIR}/lib${crate}.a"
        ${QS_RUST_NATIVE_LIBS}
    )
endfunction()

function(qs_link_plain_rust_static target crate)
    add_dependencies(${target} qs_rust_workspace_build)
    target_link_libraries(${target} PRIVATE
        "${QS_CARGO_RELEASE_DIR}/lib${crate}.a"
        ${QS_RUST_NATIVE_LIBS}
    )
endfunction()

add_subdirectory("../qs-native" "qs-native")
add_subdirectory("../material-popups" "material-popups")
add_subdirectory("../qsmath" "qsmath")
add_subdirectory("../unified-lyrics-api" "unified-lyrics-api")

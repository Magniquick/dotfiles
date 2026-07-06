cmake_minimum_required(VERSION 3.24)
project(qs_rust_modules LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml DBus Concurrent)
find_program(CARGO_EXECUTABLE cargo REQUIRED)

set(QS_RUST_TARGET "x86_64-unknown-linux-gnu")
message(STATUS "Rust Target: ${QS_RUST_TARGET}")

set(QS_CARGO_TARGET_DIR "${CMAKE_CURRENT_BINARY_DIR}/cargo/build")
set(QS_CARGO_RELEASE_DIR "${QS_CARGO_TARGET_DIR}/${QS_RUST_TARGET}/release")
set(QS_RUST_NATIVE_LIBS gcc_s util rt pthread m dl c)

# Single cargo build of the whole Rust workspace. Each crate's build.rs runs
# cbindgen to emit its C ABI header (../cpp/<crate>_api.h) as a side effect, so
# any target that depends on this one sees a fresh header before it compiles.
add_custom_target(qs_rust_workspace_build ALL
    COMMAND "${CARGO_EXECUTABLE}" build
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
)

# Link a Rust staticlib into a target. No initializers.o: QML types are now
# registered by hand-written C++ QObjects in each plugin's registerTypes.
function(qs_link_rust_static target crate)
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

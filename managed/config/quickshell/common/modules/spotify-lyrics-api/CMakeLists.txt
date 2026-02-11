cmake_minimum_required(VERSION 3.21)
project(spotifylyrics LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Qml Concurrent)

# Build the Go shared library once and keep it next to the QML module output.
find_program(GO_EXECUTABLE go REQUIRED)

set(QML_MODULE_DIR "${CMAKE_CURRENT_BINARY_DIR}/qml/spotifylyrics")
set(SPOTIFY_LYRICS_GO_LIB "${QML_MODULE_DIR}/libspotifylyrics_go.so")

add_custom_command(
    OUTPUT "${SPOTIFY_LYRICS_GO_LIB}"
    COMMAND "${CMAKE_COMMAND}" -E make_directory "${QML_MODULE_DIR}"
    COMMAND "${GO_EXECUTABLE}" build -buildmode=c-shared -o "${SPOTIFY_LYRICS_GO_LIB}" ./capi
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    COMMENT "Building spotify-lyrics Go shared library"
)
add_custom_target(spotifylyrics_go_lib DEPENDS "${SPOTIFY_LYRICS_GO_LIB}")

add_library(spotifylyrics_plugin SHARED
    cpp/spotifylyrics_plugin.cpp
    cpp/SpotifyLyricsClient.cpp
)

set_target_properties(spotifylyrics_plugin
    PROPERTIES
    OUTPUT_NAME "spotifylyrics"
    LIBRARY_OUTPUT_DIRECTORY "${QML_MODULE_DIR}"
)

target_include_directories(spotifylyrics_plugin PRIVATE
    "${CMAKE_CURRENT_LIST_DIR}/cpp"
)

add_dependencies(spotifylyrics_plugin spotifylyrics_go_lib)

target_link_libraries(spotifylyrics_plugin PRIVATE
    Qt6::Core
    Qt6::Qml
    Qt6::Concurrent
    "${SPOTIFY_LYRICS_GO_LIB}"
)

set_target_properties(spotifylyrics_plugin PROPERTIES
    BUILD_RPATH "$ORIGIN"
    INSTALL_RPATH "$ORIGIN"
)

# Copy qmldir into the build output so `QML_IMPORT_PATH=.../build/qml` works.
add_custom_command(
    OUTPUT "${QML_MODULE_DIR}/qmldir"
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${CMAKE_CURRENT_LIST_DIR}/qml/spotifylyrics/qmldir"
        "${QML_MODULE_DIR}/qmldir"
    DEPENDS "${CMAKE_CURRENT_LIST_DIR}/qml/spotifylyrics/qmldir"
)
add_custom_target(spotifylyrics_qmldir ALL DEPENDS "${QML_MODULE_DIR}/qmldir")
add_dependencies(spotifylyrics_qmldir spotifylyrics_plugin)

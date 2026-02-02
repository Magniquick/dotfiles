if(NOT DEFINED CARGO_BUILD_DIR)
  message(FATAL_ERROR "CARGO_BUILD_DIR not set")
endif()
if(NOT DEFINED OUTPUT_ARCHIVE)
  message(FATAL_ERROR "OUTPUT_ARCHIVE not set")
endif()

file(GLOB archive_candidates
  "${CARGO_BUILD_DIR}/*/debug/build/qs_native-*/out/libqs_native-cxxqt-generated.a")

list(LENGTH archive_candidates archive_count)
if(archive_count EQUAL 0)
  message(FATAL_ERROR "No libqs_native-cxxqt-generated.a found under ${CARGO_BUILD_DIR}")
endif()

list(GET archive_candidates 0 archive_src)
get_filename_component(output_dir "${OUTPUT_ARCHIVE}" DIRECTORY)
file(MAKE_DIRECTORY "${output_dir}")
file(COPY "${archive_src}" DESTINATION "${output_dir}")

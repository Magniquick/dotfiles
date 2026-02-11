if(NOT DEFINED CARGO_BUILD_DIR)
  message(FATAL_ERROR "CARGO_BUILD_DIR not set")
endif()
if(NOT DEFINED OUTPUT_DIR)
  message(FATAL_ERROR "OUTPUT_DIR not set")
endif()
if(NOT DEFINED STAMP_FILE)
  message(FATAL_ERROR "STAMP_FILE not set")
endif()
if(NOT DEFINED CARGO_PROFILE_DIR)
  set(CARGO_PROFILE_DIR "debug")
endif()

file(GLOB header_dir_candidates
  "${CARGO_BUILD_DIR}/${CARGO_PROFILE_DIR}/build/qs_native-*/out/cxxqtbuild/include/qs_native"
  "${CARGO_BUILD_DIR}/*/${CARGO_PROFILE_DIR}/build/qs_native-*/out/cxxqtbuild/include/qs_native")
file(GLOB cxx_qt_lib_candidates
  "${CARGO_BUILD_DIR}/${CARGO_PROFILE_DIR}/build/cxx-qt-lib-*/out/cxxqtbuild/include"
  "${CARGO_BUILD_DIR}/*/${CARGO_PROFILE_DIR}/build/cxx-qt-lib-*/out/cxxqtbuild/include")
file(GLOB cxx_qt_candidates
  "${CARGO_BUILD_DIR}/${CARGO_PROFILE_DIR}/build/cxx-qt-*/out/include"
  "${CARGO_BUILD_DIR}/*/${CARGO_PROFILE_DIR}/build/cxx-qt-*/out/include")

list(LENGTH header_dir_candidates header_dir_count)
if(header_dir_count EQUAL 0)
  message(FATAL_ERROR "No cxxqt header dir found under ${CARGO_BUILD_DIR}")
endif()
list(LENGTH cxx_qt_lib_candidates cxx_qt_lib_count)
if(cxx_qt_lib_count EQUAL 0)
  message(FATAL_ERROR "No cxx-qt-lib header dir found under ${CARGO_BUILD_DIR}")
endif()
list(LENGTH cxx_qt_candidates cxx_qt_count)
if(cxx_qt_count EQUAL 0)
  message(FATAL_ERROR "No cxx-qt header dir found under ${CARGO_BUILD_DIR}")
endif()

list(GET header_dir_candidates 0 header_src_dir)
list(GET cxx_qt_lib_candidates 0 cxx_qt_lib_dir)
list(GET cxx_qt_candidates 0 cxx_qt_dir)
file(MAKE_DIRECTORY "${OUTPUT_DIR}")
file(COPY "${header_src_dir}/" DESTINATION "${OUTPUT_DIR}/qs_native")
file(COPY "${cxx_qt_lib_dir}/" DESTINATION "${OUTPUT_DIR}")
file(COPY "${cxx_qt_dir}/" DESTINATION "${OUTPUT_DIR}")

file(WRITE "${STAMP_FILE}" "ok")

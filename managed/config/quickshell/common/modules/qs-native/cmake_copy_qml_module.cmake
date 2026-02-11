if(NOT DEFINED OUTPUT_DIR)
  message(FATAL_ERROR "OUTPUT_DIR not set")
endif()
if(NOT DEFINED CARGO_PROFILE_DIR)
  set(CARGO_PROFILE_DIR "debug")
endif()

if(DEFINED CXXQT_QML_DIR AND EXISTS "${CXXQT_QML_DIR}")
  set(qml_src_dir "${CXXQT_QML_DIR}")
else()
  if(NOT DEFINED CARGO_BUILD_DIR)
    message(FATAL_ERROR "CARGO_BUILD_DIR not set")
  endif()

  file(GLOB qml_dir_candidates
    "${CARGO_BUILD_DIR}/${CARGO_PROFILE_DIR}/build/qs_native-*/out/qt-build-utils/qml_modules/qsnative"
    "${CARGO_BUILD_DIR}/*/${CARGO_PROFILE_DIR}/build/qs_native-*/out/qt-build-utils/qml_modules/qsnative")

  list(LENGTH qml_dir_candidates qml_dir_count)
  if(qml_dir_count EQUAL 0)
    message(FATAL_ERROR "No qml module export dir found under ${CARGO_BUILD_DIR}")
  endif()

  list(GET qml_dir_candidates 0 qml_src_dir)
endif()
file(MAKE_DIRECTORY "${OUTPUT_DIR}/qsnative")

foreach(fname qmldir plugin.qmltypes)
  if(EXISTS "${qml_src_dir}/${fname}")
    file(COPY "${qml_src_dir}/${fname}" DESTINATION "${OUTPUT_DIR}/qsnative")
  else()
    message(FATAL_ERROR "Missing ${fname} in ${qml_src_dir}")
  endif()
endforeach()

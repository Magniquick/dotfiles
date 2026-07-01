if(NOT DEFINED INPUT_QMLDIR OR NOT DEFINED OUTPUT_QMLDIR)
  message(FATAL_ERROR "INPUT_QMLDIR and OUTPUT_QMLDIR must be set")
endif()

file(READ "${INPUT_QMLDIR}" qmldir_content)
string(REGEX REPLACE "\n+$" "" qmldir_content "${qmldir_content}")
file(WRITE "${OUTPUT_QMLDIR}" "${qmldir_content}\ntypeinfo types.qmltypes\n")

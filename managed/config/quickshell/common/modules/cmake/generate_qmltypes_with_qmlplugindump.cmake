if(NOT DEFINED QMLPLUGINDUMP_EXECUTABLE)
  message(FATAL_ERROR "QMLPLUGINDUMP_EXECUTABLE must be set")
endif()

if(NOT DEFINED MODULE_URI OR NOT DEFINED MODULE_VERSION OR NOT DEFINED IMPORT_ROOT OR NOT DEFINED OUTPUT_QMLTYPES)
  message(FATAL_ERROR "MODULE_URI, MODULE_VERSION, IMPORT_ROOT, and OUTPUT_QMLTYPES must be set")
endif()

if(DEFINED QML_IMPORT_PATH_VALUE)
  set(_env_args "QML_IMPORT_PATH=${QML_IMPORT_PATH_VALUE}")
else()
  set(_env_args)
endif()

execute_process(
  COMMAND "${CMAKE_COMMAND}" -E env ${_env_args} "${QMLPLUGINDUMP_EXECUTABLE}" -noinstantiate "${MODULE_URI}" "${MODULE_VERSION}" "${IMPORT_ROOT}"
  RESULT_VARIABLE qmlplugindump_result
  OUTPUT_VARIABLE qmlplugindump_stdout
  ERROR_VARIABLE qmlplugindump_stderr
)

if(NOT qmlplugindump_result EQUAL 0)
  message(FATAL_ERROR "qmlplugindump failed for ${MODULE_URI}: ${qmlplugindump_stderr}${qmlplugindump_stdout}")
endif()

string(FIND "${qmlplugindump_stdout}" "import QtQuick.tooling" qmltypes_start)
if(qmltypes_start EQUAL -1)
  message(FATAL_ERROR "qmlplugindump output for ${MODULE_URI} did not contain qmltypes data:\n${qmlplugindump_stdout}")
endif()

string(SUBSTRING "${qmlplugindump_stdout}" ${qmltypes_start} -1 qmltypes_content)
string(REPLACE "        exportMetaObjectRevisions: [0]" "" qmltypes_content "${qmltypes_content}")
string(REPLACE "        exportMetaObjectRevisions: [0]\r" "" qmltypes_content "${qmltypes_content}")
string(REPLACE "prototype: \"QAbstractListModel\"" "prototype: \"QObject\"" qmltypes_content "${qmltypes_content}")
file(WRITE "${OUTPUT_QMLTYPES}" "${qmltypes_content}")

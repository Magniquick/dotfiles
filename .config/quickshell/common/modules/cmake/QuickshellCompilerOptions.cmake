include_guard(GLOBAL)

option(QS_NATIVE_CPU "Enable native CPU optimizations" ON)
option(QS_STRICT_WARNINGS "Enable strict compiler warnings" ON)
option(QS_WARNINGS_AS_ERRORS "Treat compiler warnings as errors" OFF)

function(qs_apply_common_compile_options target)
  if(NOT TARGET "${target}")
    message(FATAL_ERROR "Unknown target: ${target}")
  endif()

  if(QS_STRICT_WARNINGS)
    if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
      target_compile_options("${target}" PRIVATE
        $<$<COMPILE_LANGUAGE:CXX>:-Wall>
        $<$<COMPILE_LANGUAGE:CXX>:-Wextra>
        $<$<COMPILE_LANGUAGE:CXX>:-Wpedantic>
        $<$<COMPILE_LANGUAGE:CXX>:-Wcast-align>
        $<$<COMPILE_LANGUAGE:CXX>:-Wconversion>
        $<$<COMPILE_LANGUAGE:CXX>:-Wdouble-promotion>
        $<$<COMPILE_LANGUAGE:CXX>:-Wformat=2>
        $<$<COMPILE_LANGUAGE:CXX>:-Wimplicit-fallthrough>
        $<$<COMPILE_LANGUAGE:CXX>:-Wnon-virtual-dtor>
        $<$<COMPILE_LANGUAGE:CXX>:-Wnull-dereference>
        $<$<COMPILE_LANGUAGE:CXX>:-Wold-style-cast>
        $<$<COMPILE_LANGUAGE:CXX>:-Woverloaded-virtual>
        $<$<COMPILE_LANGUAGE:CXX>:-Wshadow>
        $<$<COMPILE_LANGUAGE:CXX>:-Wsign-conversion>
        $<$<COMPILE_LANGUAGE:CXX>:-Wundef>
      )
    endif()

    if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
      target_compile_options("${target}" PRIVATE
        $<$<COMPILE_LANGUAGE:C>:-Wall>
        $<$<COMPILE_LANGUAGE:C>:-Wextra>
        $<$<COMPILE_LANGUAGE:C>:-Wpedantic>
        $<$<COMPILE_LANGUAGE:C>:-Wformat=2>
        $<$<COMPILE_LANGUAGE:C>:-Wimplicit-fallthrough>
        $<$<COMPILE_LANGUAGE:C>:-Wnull-dereference>
        $<$<COMPILE_LANGUAGE:C>:-Wundef>
      )
    endif()

    if(QS_WARNINGS_AS_ERRORS AND CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
      target_compile_options("${target}" PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-Werror>)
    endif()
    if(QS_WARNINGS_AS_ERRORS AND CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
      target_compile_options("${target}" PRIVATE $<$<COMPILE_LANGUAGE:C>:-Werror>)
    endif()
  endif()

  if(QS_NATIVE_CPU AND CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options("${target}" PRIVATE
      $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>>>:-march=native>
      $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>>>:-mtune=native>
    )
  endif()

  if(QS_NATIVE_CPU AND CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options("${target}" PRIVATE
      $<$<AND:$<COMPILE_LANGUAGE:C>,$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>>>:-march=native>
      $<$<AND:$<COMPILE_LANGUAGE:C>,$<OR:$<CONFIG:Release>,$<CONFIG:RelWithDebInfo>>>:-mtune=native>
    )
  endif()
endfunction()

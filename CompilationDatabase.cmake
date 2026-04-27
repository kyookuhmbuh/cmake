
include_guard(GLOBAL)

#[[
  Enables generation of `compile_commands.json`, which contains the exact
  compiler invocations for all translation units in a machine-readable format.

  When using the Ninja Multi-Config generator, CMake emits compilation commands
  for all configurations for each source file (e.g. Debug, Release,
  RelWithDebInfo, MinSizeRel).

  Observations from clangd logs show that clangd always selects commands
  corresponding to the Debug configuration, likely because it is the first
  configuration encountered in the file.
#]]
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

#[[
  Creates a symbolic link to the generated `compile_commands.json` file.

  By default, clangd searches for `compile_commands.json` in the parent
  directories of the source file (and also in subdirectories named `build/`),
  so placing a link in the source root improves discoverability.
#]]
option(
  CMAKE_CREATE_COMPILE_COMMANDS_LINK
  "Create a symlink to compile_commands.json in the source root"
  ${CMAKE_EXPORT_COMPILE_COMMANDS}
)

function(_compdb_create_symlink)
  get_filename_component(_expected_binary_dir "${CMAKE_SOURCE_DIR}/build" ABSOLUTE)
  get_filename_component(_actual_binary_dir "${CMAKE_BINARY_DIR}" ABSOLUTE)

  if(_actual_binary_dir STREQUAL _expected_binary_dir)
    message(STATUS "compile_commands.json exists in canonical build directory")
    return()
  endif()

  set(_origin "${CMAKE_BINARY_DIR}/compile_commands.json")
  set(_link   "${CMAKE_SOURCE_DIR}/compile_commands.json")

  # Do not overwrite a real file
  if(EXISTS "${_link}" AND NOT IS_SYMLINK "${_link}")
    message(WARNING
      "compile_commands.json exists in source tree and is not a symlink; "
      "skipping link creation")
    return()
  endif()

  file(
    CREATE_LINK "${_origin}" "${_link}"
    SYMBOLIC
    RESULT _result
  )

  if(_result EQUAL 0)
    message(STATUS
      "compile_commands.json -> ${_origin}")
  else()
    message(WARNING
      "Failed to create compile_commands.json symlink (code: ${_result})")
  endif()
endfunction()

if(CMAKE_CREATE_COMPILE_COMMANDS_LINK)
  _compdb_create_symlink()
endif()

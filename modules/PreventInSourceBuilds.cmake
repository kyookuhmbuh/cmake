#[[
Prevent in-source CMake builds.

This module provides a function that aborts configuration when the
binary directory is the same as the source directory. In-source builds
pollute the source tree with generated files and are strongly
discouraged.

Usage:
  include(PreventInsourceBuilds)
  prevent_insource_builds()

Both CMAKE_SOURCE_DIR and CMAKE_BINARY_DIR are available before the
project() command, so the check may be placed at the very top of the
root CMakeLists.txt.

Note:
  This check only catches exact in-source builds
  (CMAKE_BINARY_DIR == CMAKE_SOURCE_DIR). It does not prevent builds
  in subdirectories of the source tree.
]]

#[[
Abort configuration if the build directory is the source directory.
]]
function(prevent_insource_builds)
  if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
    message(
      FATAL_ERROR
        "In-source builds are not supported.\n"
        "Please use a dedicated build directory instead:\n"
        "  mkdir build && cd build\n"
        "  cmake ..\n\n"
        "If you previously ran CMake in the source tree, remove the "
        "generated files first:\n"
        "  rm -rf CMakeCache.txt CMakeFiles/ cmake_install.cmake\n"
    )
  endif()
endfunction()

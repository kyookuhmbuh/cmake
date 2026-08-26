
#[[
LLVM source-based code coverage support.

This module provides functions for instrumenting executable targets,
registering test executables, and generating HTML coverage reports
using llvm-profdata and llvm-cov.

Coverage instrumentation is applied to the executable targets that
run the code under test. This also covers header-only libraries, whose
code is compiled into the consuming test executable.

Example:

  include(LLVMCoverage)

  enable_llvm_coverage()

  # Instrument library targets if their compiled code is part of the
  # coverage data and they are linked into the test executables.
  add_llvm_coverage(stnet_core)
  add_llvm_coverage(stnet_io)

  add_subdirectory(tests)

  # Register test executables for a coverage report.
  #
  # The first registered test executable is used as the primary
  # llvm-cov input. Additional executables are passed as -object
  # arguments.
  add_llvm_coverage_test(coverage bitfield_test)
  add_llvm_coverage_test(coverage crc16_test)

  add_llvm_coverage_report(coverage
    EXCLUDE_DIRS
      "${CMAKE_CURRENT_SOURCE_DIR}/extern"
      "${CMAKE_CURRENT_SOURCE_DIR}/tests"
  )

The resulting coverage target can be built with:

  cmake --build <build-dir> --target coverage

The HTML report is generated under:

  <build-dir>/coverage/html

The coverage workflow consists of:
- compiling and linking instrumented executables;
- running the test suite with LLVM_PROFILE_FILE configured;
- merging generated .profraw files with llvm-profdata;
- generating the HTML report with llvm-cov.

LLVM coverage requires the Clang compiler and the llvm-profdata and
llvm-cov executables.
]]

# Cache current list dir
set(LLVM_COVERAGE_MODULE_DIR
  "${CMAKE_CURRENT_LIST_DIR}"
)

#[[
Enable LLVM source-based code coverage support.

This macro initializes the LLVM coverage infrastructure when Clang,
llvm-profdata, and llvm-cov are available.

The initialized infrastructure provides:
- an interface library with LLVM coverage compilation flags;
- an interface library with LLVM coverage linking flags;
- the LLVM_COVERAGE_SUPPORTED variable indicating whether coverage
  support is available.

Coverage instrumentation is applied to executable targets rather than
library targets. This is important for header-only code, since such code
is compiled and instrumented as part of the consuming test executable.

The macro is safe to call multiple times. Initialization is performed
only once.
]]
macro (enable_llvm_coverage)
  if(LLVM_COVERAGE_INTERFACE_INITIALIZED)
    return()
  endif()

  set(LLVM_COVERAGE_SUPPORTED OFF)

  if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    message(WARNING
      "LLVM coverage requires Clang, "
      "but compiler is ${CMAKE_CXX_COMPILER_ID}"
    )
    return()
  endif()

  find_program(LLVM_PROFDATA_EXECUTABLE NAMES llvm-profdata)
  if(NOT LLVM_PROFDATA_EXECUTABLE)
    message(WARNING
      "LLVM coverage is enabled, but llvm-profdata was not found"
    )
  endif()

  find_program(LLVM_COV_EXECUTABLE NAMES llvm-cov)
  if(NOT LLVM_COV_EXECUTABLE)
    message(WARNING
      "LLVM coverage is enabled, but llvm-cov was not found"
    )
  endif()

  if(NOT LLVM_PROFDATA_EXECUTABLE OR NOT LLVM_COV_EXECUTABLE)
    return()
  endif()

  set(LLVM_COVERAGE_SUPPORTED ON)

  # Compiler instrumentation required for LLVM source-based coverage.
  add_library(llvm_coverage_compile_flags INTERFACE)
  target_compile_options(llvm_coverage_compile_flags
    INTERFACE
      -fprofile-instr-generate
      -fcoverage-mapping
  )

  # Linker instrumentation required to emit LLVM profiling runtime support.
  add_library(llvm_coverage_link_flags INTERFACE)
  target_link_options(llvm_coverage_link_flags
    INTERFACE
      -fprofile-instr-generate
  )

  set(LLVM_COVERAGE_INTERFACE_INITIALIZED ON)

  message(STATUS
    "LLVM coverage interface initialized"
  )
endmacro()

#[[
Instrument a target for LLVM source-based code coverage.

The target receives both the compile-time coverage mapping options and
the link-time profile generation option.

This function is normally applied to executable targets that execute
the code under test. In particular, this is required for header-only
libraries: their code is instantiated and compiled into the consuming
test executable, so instrumenting the library target itself is
insufficient.

The function does nothing when LLVM coverage support is unavailable.

@param target_name Name of the target to instrument.
]]
function(add_llvm_coverage target_name)
  if(NOT LLVM_COVERAGE_SUPPORTED)
    return()
  endif()

  target_link_libraries(${target_name} PRIVATE llvm_coverage_compile_flags)
  target_link_libraries(${target_name} PRIVATE llvm_coverage_link_flags)

  message(STATUS
    "LLVM coverage instrumentation added to target '${target_name}'"
  )
endfunction()

#[[
Register a test executable as an LLVM coverage test.

The test target is added to a named coverage test group and is
instrumented with LLVM coverage support.

A coverage group is later consumed by add_llvm_coverage_report().
The first registered test executable is used as the primary executable
passed to llvm-cov; all subsequent executables are passed as additional
coverage objects.

The target must exist when this function is called.

@param list_name Name of the coverage test group.
@param target_name Name of the test executable target.
]]
function(add_llvm_coverage_test list_name target_name)
  if(NOT LLVM_COVERAGE_SUPPORTED)
    return()
  endif()

  if(NOT TARGET ${target_name})
    message(FATAL_ERROR
      "LLVM coverage target '${target_name}' does not exist"
    )
  endif()

  set(list_variable "LLVM_COVERAGE_TESTS__${list_name}")

  set(targets "${${list_variable}}")
  list(APPEND targets "${target_name}")

  set(${list_variable}
    "${targets}"
    CACHE INTERNAL
    "LLVM coverage targets for '${list_name}'"
  )

  add_llvm_coverage(${target_name})
  message(STATUS
    "LLVM coverage target '${target_name}' registered in '${list_name}'"
  )
endfunction()

#[[
Create a custom target that runs tests and generates an LLVM coverage
report.

The custom target performs the following steps:
1. Removes the previous coverage output.
2. Creates the directory for raw LLVM profile data.
3. Runs the CTest test suite with LLVM_PROFILE_FILE configured.
4. Merges the generated .profraw files into a .profdata file.
5. Runs llvm-cov to generate an HTML coverage report.

All test executables registered with add_llvm_coverage_test() for the
specified group are passed to llvm-cov. The first registered executable
is used as the primary coverage binary, while the remaining executables
are supplied as additional coverage objects.

Directories listed in EXCLUDE_DIRS are excluded from the generated
coverage report using llvm-cov's -ignore-filename-regex option.

Coverage instrumentation is expected to be present in the test
executables. This is particularly important for header-only libraries,
whose code is compiled into those executables.

@param list_name Name of the coverage test group.
@param EXCLUDE_DIRS Absolute or relative source directories to exclude
                    from the coverage report.
]]
function(add_llvm_coverage_report list_name)
  if(NOT LLVM_COVERAGE_SUPPORTED)
    return()
  endif()

  set(options)
  set(one_value_args)
  set(multi_value_args EXCLUDE_DIRS)

  cmake_parse_arguments(
    PARSE_ARGV 1
    ARG
    "${options}"
    "${one_value_args}"
    "${multi_value_args}"
  )

  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "Unknown arguments for add_llvm_coverage_report(): "
      "${ARG_UNPARSED_ARGUMENTS}"
    )
  endif()

  set(list_variable "LLVM_COVERAGE_TESTS__${list_name}")

  if(NOT DEFINED ${list_variable} OR NOT ${list_variable})
    message(WARNING
      "No LLVM coverage targets registered for '${list_name}'"
    )
    return()
  endif()

  set(coverage_tests "${${list_variable}}")

  set(COVERAGE_DIR
    "${CMAKE_BINARY_DIR}/coverage"
  )

  set(PROFILE_DIR
    "${COVERAGE_DIR}/profraw"
  )

  set(PROFDATA_FILE
    "${COVERAGE_DIR}/coverage.profdata"
  )

  list(GET coverage_tests 0 coverage_main_target)
  list(REMOVE_AT coverage_tests 0)

  set(COVERAGE_OBJECTS)

  foreach(target IN LISTS coverage_tests)
    list(APPEND COVERAGE_OBJECTS
      -object "$<TARGET_FILE:${target}>"
    )
  endforeach()

  # Build llvm-cov filename exclusion regex.
  set(COVERAGE_IGNORE_FILENAME_REGEX)

  foreach(directory IN LISTS ARG_EXCLUDE_DIRS)
    get_filename_component(directory "${directory}" ABSOLUTE)

    string(REGEX REPLACE
      "([][.^$()+*?|\\\\])"
      "\\\\\\1"
      directory_regex
      "${directory}"
    )

    if(COVERAGE_IGNORE_FILENAME_REGEX)
      string(APPEND
        COVERAGE_IGNORE_FILENAME_REGEX
        "|"
      )
    endif()

    string(APPEND
      COVERAGE_IGNORE_FILENAME_REGEX
      "${directory_regex}/.*"
    )
  endforeach()

  set(COVERAGE_IGNORE_ARGS)

  if(COVERAGE_IGNORE_FILENAME_REGEX)
    list(APPEND COVERAGE_IGNORE_ARGS
      "-ignore-filename-regex=${COVERAGE_IGNORE_FILENAME_REGEX}"
    )
  endif()

  set(LLVM_COVERAGE_PROFILE_DIR
    "${PROFILE_DIR}"
  )

  set(LLVM_COVERAGE_PROFDATA_FILE
    "${PROFDATA_FILE}"
  )

  set(LLVM_COVERAGE_MERGE_SCRIPT
    "${CMAKE_CURRENT_BINARY_DIR}/LLVMCoverageMerge.cmake"
  )

  configure_file(
    "${LLVM_COVERAGE_MODULE_DIR}/LLVMCoverageMerge.cmake.in"
    "${LLVM_COVERAGE_MERGE_SCRIPT}"
    @ONLY
  )

  add_custom_target(${list_name}
    COMMAND
      ${CMAKE_COMMAND} -E rm -rf
      "${COVERAGE_DIR}"

    COMMAND
      ${CMAKE_COMMAND} -E make_directory
      "${PROFILE_DIR}"

    COMMAND
      ${CMAKE_COMMAND} -E env
      "LLVM_PROFILE_FILE=${PROFILE_DIR}/%p-%m.profraw"
      ${CMAKE_CTEST_COMMAND}
      --output-on-failure

    COMMAND
      ${CMAKE_COMMAND} -E echo
      "Running llvm-profdata merge..."

    COMMAND
      ${CMAKE_COMMAND}
      -P "${LLVM_COVERAGE_MERGE_SCRIPT}"

    COMMAND
      ${CMAKE_COMMAND} -E echo
      "Running llvm-cov..."

    COMMAND
      ${CMAKE_COMMAND} -E env
      DEBUGINFOD_URLS=
      ${LLVM_COV_EXECUTABLE}
      show
      $<TARGET_FILE:${coverage_main_target}>
      ${COVERAGE_OBJECTS}
      -instr-profile=${PROFDATA_FILE}
      -format=html
      -output-dir=${COVERAGE_DIR}/html
      ${COVERAGE_IGNORE_ARGS}

    DEPENDS
      ${${list_variable}}

    WORKING_DIRECTORY
      "${CMAKE_BINARY_DIR}"

    USES_TERMINAL
    VERBATIM
  )

  message(STATUS
    "LLVM coverage report '${list_name}' initialized for targets: "
    "${${list_variable}}"
  )
endfunction()

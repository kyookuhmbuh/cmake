
#[[
Code coverage support for CMake projects.

This module provides functions for enabling code coverage, instrumenting
targets, registering test executables, and generating HTML coverage
reports.

The following coverage modes are supported:

  LLVM
    Uses llvm-profdata and llvm-cov with Clang.

  GNU
    Uses gcov/gcovr with GCC. Clang can also be used in GNU coverage
    mode through llvm-cov gcov.

Coverage instrumentation is applied to the executable targets that run
the code under test. This is especially important for header-only
libraries, whose code is compiled into the consuming test executable.

Example:

  include(CodeCoverage)

  enable_code_coverage()

  add_subdirectory(tests)

  # Register test executables for a coverage report.
  append_code_coverage_target(coverage bitfield_test)
  append_code_coverage_target(coverage crc16_test)
  append_code_coverage_target(coverage frame_checksum_test)

  add_code_coverage_report(coverage
    EXCLUDE_DIRS
      "${CMAKE_CURRENT_SOURCE_DIR}/extern"
      "${CMAKE_CURRENT_SOURCE_DIR}/tests"
  )

The coverage mode can be selected explicitly:

  enable_code_coverage(MODE LLVM)
  enable_code_coverage(MODE GNU)

If no mode is specified, LLVM is selected for Clang and GNU is selected
for GCC.

The resulting coverage target can be built with:

  cmake --build <build-dir> --target coverage

The HTML report is generated under:

  <build-dir>/html

The coverage workflow depends on the selected mode. LLVM coverage runs
the test suite with LLVM profile instrumentation, merges the generated
profile data with llvm-profdata, and generates the report with llvm-cov.

GNU coverage runs the test suite with gcov instrumentation and generates
the report with gcovr.

Coverage support requires the tools corresponding to the selected mode:
llvm-profdata and llvm-cov for LLVM mode, and gcov and gcovr for GNU mode.
]]

# Directory containing this coverage module.
set(_CODE_COVERAGE_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}")

# Prevent repeated coverage initialization.
set(_CODE_COVERAGE_INITIALIZED
  OFF
  CACHE INTERNAL "Code coverage state."
  FORCE
)

# Valid target usage requirement scopes.
set(_CODE_COVERAGE_SCOPES
  PRIVATE
  PUBLIC
  INTERFACE
)

# Supported coverage modes.
set(_CODE_COVERAGE_SUPPORTED_MODES
  LLVM
  GNU
)

# Paths to coverage tools.
find_program(CODE_COVERAGE_LLVM_PROFDATA_PATH NAMES llvm-profdata)
find_program(CODE_COVERAGE_LLVM_COV_PATH NAMES llvm-cov)
find_program(CODE_COVERAGE_GNU_GCOV_PATH NAMES gcov)
find_program(CODE_COVERAGE_GNU_GCOVR_PATH NAMES gcovr)

# Selected coverage mode.
set(CODE_COVERAGE_MODE
    GNU
    CACHE INTERNAL "Code coverage mode."
    FORCE
)

# Indicates whether coverage support is available.
set(CODE_COVERAGE_SUPPORTED
    OFF
    CACHE INTERNAL "Indicating whether coverage support is available."
    FORCE
)

#[[
Enable code coverage support.

The coverage mode can be selected with the optional MODE argument:

  enable_code_coverage(MODE LLVM)
  enable_code_coverage(MODE GNU)

If MODE is omitted, the mode is selected automatically based on the
C++ compiler: LLVM for Clang and GNU for GCC.

LLVM mode requires llvm-profdata and llvm-cov.
GNU mode requires gcov and gcovr.

The function sets CODE_COVERAGE_MODE to the selected coverage mode and
CODE_COVERAGE_SUPPORTED to ON when all required tools are available.

The function is safe to call multiple times. Initialization is performed
only once.

@param MODE
  Optional coverage mode. Supported values are LLVM and GNU.
]]
function (enable_code_coverage)
  if(_CODE_COVERAGE_INITIALIZED)
    return()
  endif()

  set(options)
  set(one_value_args MODE)
  set(multi_value_args)

  cmake_parse_arguments(
    PARSE_ARGV 0
    ARG
    "${options}"
    "${one_value_args}"
    "${multi_value_args}"
  )

  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "Unknown arguments for enable_code_coverage(): "
      "${ARG_UNPARSED_ARGUMENTS}"
    )
  endif()

  if(ARG_MODE)
    if(NOT ARG_MODE IN_LIST _CODE_COVERAGE_SUPPORTED_MODES)
      message(FATAL_ERROR
        "Invalid code coverage mode ${ARG_MODE}, "
        "supported modes: ${_CODE_COVERAGE_SUPPORTED_MODES}"
      )
      return()
    endif()

    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU" AND ARG_MODE STREQUAL "LLVM")
      message(FATAL_ERROR
        "Invalid code coverage mode ${ARG_MODE} for GCC"
      )
      return()
    endif()

    set(CODE_COVERAGE_MODE
      "${ARG_MODE}"
      CACHE INTERNAL "Code coverage mode."
      FORCE
    )
  else()
    if(CMAKE_CXX_COMPILER_ID MATCHES "(Apple)?[Cc]lang")
      set(CODE_COVERAGE_MODE
        LLVM
        CACHE INTERNAL "Code coverage mode."
        FORCE
      )
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
      set(CODE_COVERAGE_MODE
        GNU
        CACHE INTERNAL "Code coverage mode."
        FORCE
      )
    endif()
  endif()

  if(NOT CODE_COVERAGE_MODE IN_LIST _CODE_COVERAGE_SUPPORTED_MODES)
    message(WARNING "Code coverage requires Clang or GCC")
    return()
  endif()

  if(CODE_COVERAGE_MODE STREQUAL "LLVM")
    if(NOT CODE_COVERAGE_LLVM_PROFDATA_PATH)
      message(WARNING
        "LLVM code coverage is enabled, but llvm-profdata was not found"
      )
    endif()

    if(NOT CODE_COVERAGE_LLVM_COV_PATH)
      message(WARNING
        "LLVM code coverage is enabled, but llvm-cov was not found"
      )
    endif()

    if(NOT CODE_COVERAGE_LLVM_PROFDATA_PATH OR
      NOT CODE_COVERAGE_LLVM_COV_PATH
    )
      return()
    endif()
  elseif(CODE_COVERAGE_MODE STREQUAL "GNU")
    if(NOT CODE_COVERAGE_GNU_GCOV_PATH)
      message(WARNING
        "GNU code coverage is enabled, but gcov was not found"
      )
    endif()

    if(NOT CODE_COVERAGE_GNU_GCOVR_PATH)
      message(WARNING
        "GNU code coverage is enabled, but gcovr was not found"
      )
    endif()

    if(CMAKE_CXX_COMPILER_ID MATCHES "(Apple)?[Cc]lang")
      if(NOT CODE_COVERAGE_LLVM_COV_PATH)
        message(WARNING
          "GNU code coverage for Clang is enabled, but llvm-cov was not found"
        )
      endif()
    endif()

    if(NOT CODE_COVERAGE_GNU_GCOV_PATH OR
      NOT CODE_COVERAGE_GNU_GCOVR_PATH
    )
      return()
    endif()
  endif()

  set(CODE_COVERAGE_SUPPORTED
    ON
    CACHE INTERNAL "Indicating whether coverage support is available."
    FORCE
  )
  set(_CODE_COVERAGE_INITIALIZED
    ON
    CACHE INTERNAL "Code coverage state."
    FORCE
  )

  message(STATUS "Code coverage enabled (${CODE_COVERAGE_MODE} mode)")
endfunction()

#[[
Add code coverage compile options to a target.

The options depend on the selected coverage mode.

In LLVM mode, the target is compiled with LLVM source-based coverage
instrumentation using -fprofile-instr-generate and -fcoverage-mapping.

In GNU mode, the target is compiled with GCC/gcov coverage
instrumentation using --coverage.

@param target_name
  Name of the target to which the options are added.

@param scope
  Target usage requirement: PRIVATE, PUBLIC, or INTERFACE.
]]
function(code_coverage_compile_options target_name scope)
  if(NOT scope IN_LIST _CODE_COVERAGE_SCOPES)
    message(FATAL_ERROR
      "Invalid coverage compile options scope '${scope}'. "
      "Expected PRIVATE, PUBLIC, or INTERFACE."
    )
  endif()

  if (CODE_COVERAGE_MODE STREQUAL "LLVM")
    target_compile_options(${target_name}
      ${scope}
        -fprofile-instr-generate
        -fcoverage-mapping
    )
  elseif(CODE_COVERAGE_MODE STREQUAL "GNU")
    target_compile_options(${target_name}
      ${scope}
        --coverage
    )

    include(CheckCXXCompilerFlag)
    check_cxx_compiler_flag(-fprofile-abs-path HAVE_fprofile_abs_path)
    if(HAVE_fprofile_abs_path)
      target_compile_options(${target_name}
        ${scope}
          -fprofile-abs-path
      )
    endif()
  endif()
endfunction()

#[[
Add code coverage link options to a target.

The options depend on the selected coverage mode.

In LLVM mode, the target is linked with the LLVM profiling runtime.

In GNU mode, GCC targets are linked with libgcov, while Clang targets
use the --coverage linker option.

@param target_name
  Name of the target to which the options are added.

@param scope
  Target usage requirement: PRIVATE, PUBLIC, or INTERFACE.
]]
function(code_coverage_link_options target_name scope)
  if(NOT scope IN_LIST _CODE_COVERAGE_SCOPES)
    message(FATAL_ERROR
      "Invalid coverage link options scope '${scope}'. "
      "Expected PRIVATE, PUBLIC, or INTERFACE."
    )
  endif()

  if (CODE_COVERAGE_MODE STREQUAL "LLVM")
    target_link_options(${target_name}
      ${scope}
        -fprofile-instr-generate
        -fcoverage-mapping
    )
  elseif(CODE_COVERAGE_MODE STREQUAL "GNU")
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU")
      target_link_libraries(${target_name} ${scope} gcov)
    elseif(CMAKE_CXX_COMPILER_ID MATCHES "(Apple)?[Cc]lang")
      target_link_options(${target_name} ${scope} --coverage)
    endif()
  endif()
endfunction()

#[[
Register a target for a code coverage report.

The target is added to a named coverage target group and instrumented
with the compile and link options required by the selected coverage
mode.

For test executables, this enables coverage instrumentation for the
code executed by the tests. This is particularly important for
header-only libraries, whose code is compiled into the consuming test
executable.

A coverage group is later consumed by add_code_coverage_report().

The target must exist when this function is called.

@param list_name
  Name of the coverage target group.

@param target_name
  Name of the target to register.
]]
function(append_code_coverage_target list_name target_name)
  if(NOT CODE_COVERAGE_SUPPORTED)
    return()
  endif()

  if(NOT TARGET ${target_name})
    message(FATAL_ERROR
      "Code coverage target '${target_name}' does not exist"
    )
  endif()

  set(list_variable "_CODE_COVERAGE_TARGETS__${list_name}")

  set(targets "${${list_variable}}")
  list(APPEND targets "${target_name}")

  set(${list_variable}
    "${targets}"
    CACHE INTERNAL
    "Code coverage targets for '${list_name}'"
  )

  code_coverage_compile_options(${target_name} PRIVATE)
  code_coverage_link_options(${target_name} PRIVATE)
  message(STATUS
    "Code coverage target '${target_name}' registered in '${list_name}' "
    "(${CODE_COVERAGE_MODE} mode)"
  )
endfunction()

#[[
Create a custom target that runs tests and generates an HTML coverage
report.

The report format and collection tools depend on the selected coverage
mode.

In LLVM mode, the custom target:
1. Removes previous coverage data.
2. Runs the CTest test suite with LLVM profile generation enabled.
3. Merges the generated .profraw files with llvm-profdata.
4. Generates an HTML report with llvm-cov.

In GNU mode, the custom target:
1. Removes the previous HTML report.
2. Runs the CTest test suite with gcov instrumentation enabled.
3. Generates an HTML report with gcovr.

All targets registered with append_code_coverage_target() for the
specified group participate in the coverage report.

In LLVM mode, the first registered target is used as the primary
llvm-cov input and the remaining targets are supplied as additional
coverage objects.

Directories and files listed in EXCLUDE_DIRS and EXCLUDE_FILES are
excluded from the generated coverage report.

Coverage instrumentation is applied to the executable targets that run
the code under test. This is particularly important for header-only
libraries, whose code is compiled into those executables.

@param list_name
  Name of the coverage target group.

@param ALL
  Indicate that this target should be added to the default build target
  so that it will be run every time.

@param TARGET_NAME
  Optional name of custom target to build a report.

@param OUTPUT_DIR
  Optional directory where the generated HTML report is placed.
  Defaults to the current binary directory.

@param EXCLUDE_DIRS
  Optional list of directories to exclude from the coverage report.

@param EXCLUDE_FILES
  Optional list of files to exclude from the coverage report.
]]
function(add_code_coverage_report list_name)
  if(NOT CODE_COVERAGE_SUPPORTED)
    return()
  endif()

  set(options ALL)
  set(one_value_args TARGET_NAME OUTPUT_DIR)
  set(multi_value_args EXCLUDE_DIRS EXCLUDE_FILES)

  cmake_parse_arguments(
    PARSE_ARGV 1
    ARG
    "${options}"
    "${one_value_args}"
    "${multi_value_args}"
  )

  if(ARG_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "Unknown arguments for add_code_coverage_report(): "
      "${ARG_UNPARSED_ARGUMENTS}"
    )
  endif()

  set(list_variable "_CODE_COVERAGE_TARGETS__${list_name}")

  if(NOT DEFINED ${list_variable} OR NOT ${list_variable})
    message(WARNING
      "No coverage targets registered for '${list_name}'"
    )
    return()
  endif()

  set(coverage_tests "${${list_variable}}")

  set(COVERAGE_INTERMEDIATE_DIR "${CMAKE_CURRENT_BINARY_DIR}/coverage")
  set(COVERAGE_OUTPUT_DIR "${CMAKE_CURRENT_BINARY_DIR}")
  if(ARG_OUTPUT_DIR)
    set(COVERAGE_OUTPUT_DIR "${ARG_OUTPUT_DIR}")
  endif()
  set(COVERAGE_OUTPUT_HTML_DIR "${COVERAGE_OUTPUT_DIR}/html")
  set(COVERAGE_OUTPUT_TXT_DIR "${COVERAGE_OUTPUT_DIR}/txt")

  set(_report_commands)

  if(CODE_COVERAGE_MODE STREQUAL "LLVM")
    set(PROFILE_DIR   "${COVERAGE_INTERMEDIATE_DIR}/profraw")
    set(PROFDATA_FILE "${COVERAGE_INTERMEDIATE_DIR}/coverage.profdata")

    list(GET coverage_tests 0 coverage_main_target)
    set(coverage_extra_tests "${coverage_tests}")
    list(REMOVE_AT coverage_extra_tests 0)

    set(COVERAGE_OBJECTS)
    foreach(target IN LISTS coverage_extra_tests)
      list(APPEND COVERAGE_OBJECTS -object "$<TARGET_FILE:${target}>")
    endforeach()

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
        string(APPEND COVERAGE_IGNORE_FILENAME_REGEX "|")
      endif()
      string(APPEND COVERAGE_IGNORE_FILENAME_REGEX "${directory_regex}/.*")
    endforeach()
    foreach(file_path IN LISTS ARG_EXCLUDE_FILES)
      get_filename_component(file_path "${file_path}" ABSOLUTE)
      string(REGEX REPLACE
        "([][.^$()+*?|\\\\])"
        "\\\\\\1"
        file_regex
        "${file_path}"
      )
      if(COVERAGE_IGNORE_FILENAME_REGEX)
        string(APPEND COVERAGE_IGNORE_FILENAME_REGEX "|")
      endif()
      string(APPEND COVERAGE_IGNORE_FILENAME_REGEX "${file_regex}")
    endforeach()

    set(COVERAGE_IGNORE_ARGS)
    if(COVERAGE_IGNORE_FILENAME_REGEX)
      list(APPEND COVERAGE_IGNORE_ARGS
        "-ignore-filename-regex=${COVERAGE_IGNORE_FILENAME_REGEX}"
      )
    endif()

    set(LLVM_COVERAGE_PROFILE_DIR  "${PROFILE_DIR}")
    set(LLVM_COVERAGE_PROFDATA_FILE "${PROFDATA_FILE}")
    set(LLVM_COVERAGE_MERGE_SCRIPT
      "${CMAKE_CURRENT_BINARY_DIR}/CodeCoverageMergeForLLVM.cmake"
    )

    configure_file(
      "${_CODE_COVERAGE_MODULE_DIR}/CodeCoverageMergeForLLVM.cmake.in"
      "${LLVM_COVERAGE_MERGE_SCRIPT}"
      @ONLY
    )

    list(APPEND _report_commands
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${COVERAGE_INTERMEDIATE_DIR}"
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${COVERAGE_OUTPUT_HTML_DIR}"
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${COVERAGE_OUTPUT_TXT_DIR}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${COVERAGE_INTERMEDIATE_DIR}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${COVERAGE_OUTPUT_HTML_DIR}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${COVERAGE_OUTPUT_TXT_DIR}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${PROFILE_DIR}"

      COMMAND ${CMAKE_COMMAND} -E env
        "LLVM_PROFILE_FILE=${PROFILE_DIR}/%p-%m.profraw"
        ${CMAKE_CTEST_COMMAND} --output-on-failure

      COMMAND ${CMAKE_COMMAND} -E echo "Running llvm-profdata merge..."

      COMMAND ${CMAKE_COMMAND}
        -P "${LLVM_COVERAGE_MERGE_SCRIPT}"

      COMMAND ${CMAKE_COMMAND} -E echo "Running llvm-cov..."

      COMMAND ${CMAKE_COMMAND} -E env DEBUGINFOD_URLS=
        ${CODE_COVERAGE_LLVM_COV_PATH}
        show
        $<TARGET_FILE:${coverage_main_target}>
        ${COVERAGE_OBJECTS}
        -instr-profile=${PROFDATA_FILE}
        -format=html
        -output-dir=${COVERAGE_OUTPUT_HTML_DIR}
        ${COVERAGE_IGNORE_ARGS}

      COMMAND ${CMAKE_COMMAND} -E echo
        "LLVM code coverage report has been created in"
        "'${COVERAGE_OUTPUT_HTML_DIR}/index.html'"
    )

  elseif(CODE_COVERAGE_MODE STREQUAL "GNU")
    set(GCOVR_EXCLUDE_ARGS)
    foreach(directory IN LISTS ARG_EXCLUDE_DIRS)
      get_filename_component(directory "${directory}" ABSOLUTE)
      list(APPEND GCOVR_EXCLUDE_ARGS --exclude "${directory}")
    endforeach()
    foreach(file_path IN LISTS ARG_EXCLUDE_FILES)
      get_filename_component(file_path "${file_path}" ABSOLUTE)
      list(APPEND GCOVR_EXCLUDE_ARGS --exclude "${file_path}")
    endforeach()

    if(CMAKE_CXX_COMPILER_ID MATCHES "(Apple)?[Cc]lang")
      set(GCOVR_GCOV_EXECUTABLE "${CODE_COVERAGE_LLVM_COV_PATH} gcov")
    else()
      set(GCOVR_GCOV_EXECUTABLE "${CODE_COVERAGE_GNU_GCOV_PATH}")
    endif()

    list(APPEND _report_commands
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${COVERAGE_OUTPUT_HTML_DIR}"
      COMMAND ${CMAKE_COMMAND} -E rm -rf "${COVERAGE_OUTPUT_TXT_DIR}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${COVERAGE_OUTPUT_HTML_DIR}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${COVERAGE_OUTPUT_TXT_DIR}"

      COMMAND ${CMAKE_CTEST_COMMAND} --output-on-failure

      COMMAND ${CMAKE_COMMAND} -E echo "Running gcovr..."

      COMMAND ${CODE_COVERAGE_GNU_GCOVR_PATH}
        --root "${CMAKE_CURRENT_SOURCE_DIR}"
        --gcov-executable "${GCOVR_GCOV_EXECUTABLE}"
        --txt "${COVERAGE_OUTPUT_TXT_DIR}/index.txt"
        --html "${COVERAGE_OUTPUT_HTML_DIR}/index.html"
        --html-details
        --html-details-syntax-highlighting
        --html-theme github.green
        --html-title "'${PROJECT_NAME}' code coverage report"
        --html-self-contained
        --print-summary
        ${GCOVR_EXCLUDE_ARGS}

      COMMAND ${CMAKE_COMMAND} -E echo
        "GNU code coverage report has been created in"
        "'${COVERAGE_OUTPUT_HTML_DIR}/index.html'"
    )
  endif()

  set(_custom_target_name "${list_name}")
  if(ARG_TARGET_NAME)
    set(_custom_target_name "${ARG_TARGET_NAME}")
  endif()

  set(_all_flag)
  if(ARG_ALL)
    set(_all_flag ALL)
  endif()

  add_custom_target(${_custom_target_name}
    ${_all_flag}
    ${_report_commands}
    COMMENT "Executing code coverage reports building."
    DEPENDS ${${list_variable}}
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    USES_TERMINAL
    VERBATIM
  )

  message(STATUS
    "Code coverage report '${_custom_target_name}' initialized for targets: "
    "${${list_variable}} (${CODE_COVERAGE_MODE} mode)"
  )
endfunction()

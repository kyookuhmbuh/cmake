
include_guard(GLOBAL)

# Parses a semantic version string into components
#
# Notes:
#   Accepts optional v/V prefix
#
# Arguments:
#   <input>         - input version string
#   [MAJOR <var>]   - major version number
#   [MINOR <var>]   - minor version number
#   [PATCH <var>]   - patch number
#   [PRERE <var>]   - pre-release string (without '-')
#   [BUILD <var>]   - build metadata string (without '+')
#   [RELEASE <var>] - normalized release string (major.minor.patch)
#   [FULL <var>]    - full normalized version string
function(project_version_parse input)
  cmake_parse_arguments(PARSE_ARGV 1 project_version_parse
    ""
    "MAJOR;MINOR;PATCH;PRERE;BUILD;RELEASE;FULL"
    ""
  )

  if(project_version_parse_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "Unknown arguments for `project_version_parse`:  "
      "${project_version_parse_UNPARSED_ARGUMENTS}"
    )
  endif()

  # Validate a pre-release string according to SemVer 2.0.0 rules
  function(_semver_validate_prerelease output input)
    if(NOT input)
      set(${output} TRUE PARENT_SCOPE)
      return()
    endif()

    set(semver_numeric_id "0|[1-9][0-9]*")
    set(semver_prere_alnum_id "[0-9]*[A-Za-z-][0-9A-Za-z-]*")
    set(semver_prere_id_part "(${semver_numeric_id}|${semver_prere_alnum_id})")
    set(semver_prere "(${semver_prere_id_part}(\\.${semver_prere_id_part})*)")

    string(REGEX MATCH "^(${semver_prere})$" ok "${input}")
    if(NOT ok)
      set(${output} FALSE PARENT_SCOPE)
      return()
    endif()

    set(${output} TRUE PARENT_SCOPE)
  endfunction()

  # Validate a build metadata string according to SemVer 2.0.0 rules
  function(_semver_validate_buildmetainfo output input)
    if(NOT input)
      set(${output} TRUE PARENT_SCOPE)
      return()
    endif()

    set(semver_build_alnum_id "[0-9A-Za-z-]+")
    set(semver_build "(${semver_build_alnum_id}(\\.${semver_build_alnum_id})*)")

    string(REGEX MATCH "^(${semver_build})$" ok "${input}")
    if(NOT ok)
      set(${output} FALSE PARENT_SCOPE)
      return()
    endif()

    set(${output} TRUE PARENT_SCOPE)
  endfunction()

  # Core regex: major.minor.patch with optional v/V prefix
  set(num "0|[1-9][0-9]*")
  set(core_regex "^[vV]?(${num})\\.(${num})\\.(${num})(.*)$")
  string(REGEX MATCH ${core_regex} matched "${input}")

  set(is_valid "TRUE")

  if(NOT matched)
    set(is_valid "FALSE")
    message(FATAL_ERROR "Invalid format: '${input}'")
  else()
    set(major "${CMAKE_MATCH_1}")
    set(minor "${CMAKE_MATCH_2}")
    set(patch "${CMAKE_MATCH_3}")
    set(rest  "${CMAKE_MATCH_4}")
    set(prere "")
    set(build "")

    # Parse optional pre-release and build metadata from the rest
    if(rest STREQUAL "")
      # nothing to parse
    elseif(rest MATCHES "^-([^+]+)$")
      set(prere "${CMAKE_MATCH_1}")
    elseif(rest MATCHES "^-([^+]+)(\\+.+)$")
      set(prere "${CMAKE_MATCH_1}")
      string(SUBSTRING "${CMAKE_MATCH_2}" 1 -1 build)
    elseif(rest MATCHES "^(\\+.+)$")
      string(SUBSTRING "${CMAKE_MATCH_1}" 1 -1 build)
    else()
      set(is_valid FALSE)
      message(FATAL_ERROR "Invalid format: '${input}'")
    endif()

    if(prere AND is_valid)
      _semver_validate_prerelease(is_valid "${prere}")
      if(NOT is_valid)
        message(FATAL_ERROR "Invalid pre-release part: ${prere}")
      endif()
    endif()

    if(build AND is_valid)
      _semver_validate_buildmetainfo(is_valid "${build}")
      if(NOT is_valid)
        message(FATAL_ERROR "Invalid build-metadata part: ${build}")
      endif()
    endif()
  endif()

  if(is_valid)
    set(release "${major}.${minor}.${patch}")
    set(full "${release}")
    if(prere)
      string(APPEND full "-${prere}")
    endif()
    if(build)
      string(APPEND full "+${build}")
    endif()
  endif()

  # Helper macro to propagate only requested variables
  macro(_propagate_if arg_name local_var)
    if(DEFINED project_version_parse_${arg_name})
      set(${project_version_parse_${arg_name}} "${${local_var}}")
      list(APPEND PROPAGATE_VARS ${project_version_parse_${arg_name}})
    endif()
  endmacro()

  _propagate_if(MAJOR major)
  _propagate_if(MINOR minor)
  _propagate_if(PATCH patch)
  _propagate_if(PRERE prere)
  _propagate_if(BUILD build)
  _propagate_if(RELEASE release)
  _propagate_if(FULL full)

  return(PROPAGATE ${PROPAGATE_VARS})
endfunction()

# Set version-related variables for the current project.
#
# Arguments:
#   <filepath> - the path to the file containing the project version
function (project_version_from_file filepath)
  file(READ "${filepath}" project_version)
  string(STRIP "${project_version}" project_version)

  project_version_parse(${project_version}
    MAJOR PROJECT_VERSION_MAJOR
    MINOR PROJECT_VERSION_MINOR
    PATCH PROJECT_VERSION_PATCH
    RELEASE PROJECT_VERSION
  )

  return(PROPAGATE
    PROJECT_VERSION_MAJOR
    PROJECT_VERSION_MINOR
    PROJECT_VERSION_PATCH
    PROJECT_VERSION
  )
endfunction()

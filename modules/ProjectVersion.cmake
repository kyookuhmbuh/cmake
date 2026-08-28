
# Parses a project version string into components
#
# Notes:
#   Accepts optional v/V prefix
#
# Arguments:
#   <input>                   - input version string
#   [SEMVER_MAJOR <var>]      - major semantic version component
#   [SEMVER_MINOR <var>]      - minor semantic version component
#   [SEMVER_PATCH <var>]      - patch semantic version component
#   [SEMVER_PRERELEASE <var>] - pre-release semantic version component
#                               (without '-')
#   [SEMVER_METADATA <var>]   - build metadata semantic version component
#                               (without '+')
#   [SEMVER_CORE <var>]       - normalized core semantic version
#                               (major.minor.patch)
#   [SEMVER_FULL <var>]       - normalized full semantic version
#   [REVISION_PREFIX <var>]   - prefix (everything before the last '/')
#   [REVISION_FULL <var>]     - full version string with prefix
#   [REVISION_SLUG <var>]     - in lowercase, shortened to 63 bytes, and with
#                               everything except 0-9 and a-z replaced with -.
#                               No leading / trailing -. Use in URLs, host names
#                               and domain names.
function(parse_project_version input)
  set(parse_project_version_output_args
    SEMVER_MAJOR
    SEMVER_MINOR
    SEMVER_PATCH
    SEMVER_PRERELEASE
    SEMVER_METADATA
    SEMVER_CORE
    SEMVER_FULL
    REVISION_PREFIX
    REVISION_FULL
    REVISION_SLUG
  )
  cmake_parse_arguments(PARSE_ARGV 1 parse_project_version
    ""
    ""
    "${parse_project_version_output_args}"
  )

  if(parse_project_version_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR
      "Unknown arguments for `parse_project_version`:  "
      "${parse_project_version_UNPARSED_ARGUMENTS}"
    )
  endif()

  # Validate a pre-release string according to SemVer 2.0.0 rules
  function(_semver_validate_prerelease output input)
    if(NOT input)
      set(${output} TRUE PARENT_SCOPE)
      return()
    endif()

    set(regex_semver_numeric_id "0|[1-9][0-9]*")
    set(regex_semver_prere_alnum_id "[0-9]*[A-Za-z-][0-9A-Za-z-]*")
    set(regex_semver_prere_id_part
      "(${regex_semver_numeric_id}|${regex_semver_prere_alnum_id})"
    )
    set(regex_semver_prere
      "(${regex_semver_prere_id_part}(\\.${regex_semver_prere_id_part})*)"
    )

    string(REGEX MATCH "^(${regex_semver_prere})$" ok "${input}")
    if(NOT ok)
      set(${output} FALSE PARENT_SCOPE)
      return()
    endif()

    set(${output} TRUE PARENT_SCOPE)
  endfunction()

  # Validate a build metadata string according to SemVer 2.0.0 rules
  function(_semver_validate_buildmetadata output input)
    if(NOT input)
      set(${output} TRUE PARENT_SCOPE)
      return()
    endif()

    set(regex_semver_build_alnum_id "[0-9A-Za-z-]+")
    set(regex_semver_build
      "(${regex_semver_build_alnum_id}(\\.${regex_semver_build_alnum_id})*)"
    )

    string(REGEX MATCH "^(${regex_semver_build})$" ok "${input}")
    if(NOT ok)
      set(${output} FALSE PARENT_SCOPE)
      return()
    endif()

    set(${output} TRUE PARENT_SCOPE)
  endfunction()

  string(STRIP "${input}" input)
  set(REVISION_PREFIX "")
  set(rest "${input}")

  # Prefix part
  if(input MATCHES "^(.*)/(.*)$")
    set(REVISION_PREFIX "${CMAKE_MATCH_1}")
    set(rest "${CMAKE_MATCH_2}")
  endif()

  # Core regex: major.minor.patch with optional v/V prefix
  set(regex_num "0|[1-9][0-9]*")
  set(regex_core_version
    "^[vV]?(${regex_num})\\.(${regex_num})\\.(${regex_num})(.*)$"
  )
  string(REGEX MATCH ${regex_core_version} matched "${rest}")

  set(is_valid "TRUE")

  if(NOT matched)
    set(is_valid "FALSE")
    message(FATAL_ERROR "Invalid format: '${rest}' in '${input}'")
  else()
    set(SEMVER_MAJOR "${CMAKE_MATCH_1}")
    set(SEMVER_MINOR "${CMAKE_MATCH_2}")
    set(SEMVER_PATCH "${CMAKE_MATCH_3}")
    set(rest "${CMAKE_MATCH_4}")
    set(SEMVER_PRERELEASE "")
    set(SEMVER_METADATA "")

    # Parse optional pre-release and build metadata from the rest
    if(rest STREQUAL "")
      # nothing to parse
    elseif(rest MATCHES "^-([^+]+)$")
      set(SEMVER_PRERELEASE "${CMAKE_MATCH_1}")
    elseif(rest MATCHES "^-([^+]+)(\\+.+)$")
      set(SEMVER_PRERELEASE "${CMAKE_MATCH_1}")
      string(SUBSTRING "${CMAKE_MATCH_2}" 1 -1 SEMVER_METADATA)
    elseif(rest MATCHES "^(\\+.+)$")
      string(SUBSTRING "${CMAKE_MATCH_1}" 1 -1 SEMVER_METADATA)
    else()
      set(is_valid FALSE)
      message(FATAL_ERROR "Invalid format: '${rest}' in '${input}'")
    endif()

    if(SEMVER_PRERELEASE AND is_valid)
      _semver_validate_prerelease(is_valid "${SEMVER_PRERELEASE}")
      if(NOT is_valid)
        message(FATAL_ERROR
          "Invalid pre-release part: ${SEMVER_PRERELEASE}"
        )
      endif()
    endif()

    if(SEMVER_METADATA AND is_valid)
      _semver_validate_buildmetadata(is_valid "${SEMVER_METADATA}")
      if(NOT is_valid)
        message(FATAL_ERROR
          "Invalid build-metadata part: ${SEMVER_METADATA}"
        )
      endif()
    endif()
  endif()

  # Build semver core and full
  if(is_valid)
    set(SEMVER_CORE
      "${SEMVER_MAJOR}.${SEMVER_MINOR}.${SEMVER_PATCH}"
    )
    set(SEMVER_FULL "${SEMVER_CORE}")
    if(SEMVER_PRERELEASE)
      string(APPEND SEMVER_FULL "-${SEMVER_PRERELEASE}")
    endif()
    if(SEMVER_METADATA)
      string(APPEND SEMVER_FULL "+${SEMVER_METADATA}")
    endif()
  endif()

  # Build version with prefix
  if(REVISION_PREFIX)
    string(JOIN / REVISION_FULL "${REVISION_PREFIX}" "v${SEMVER_FULL}")
  else()
    set(REVISION_FULL "v${SEMVER_FULL}")
  endif()

  # Build slug for version
  if(REVISION_PREFIX)
    # lowercase
    string(TOLOWER "${REVISION_PREFIX}" REVISION_SLUG)
    # everything except [a-z0-9] -> '-'
    string(REGEX REPLACE "[^a-z0-9]+" "-" REVISION_SLUG "${REVISION_SLUG}")
    # remove leading/trailing '-'
    string(REGEX REPLACE "^-+|-+$" "" REVISION_SLUG "${REVISION_SLUG}")
    # limit to 63 characters
    string(SUBSTRING "${REVISION_SLUG}" 0 63 REVISION_SLUG)
    # substring may end with '-'
    string(REGEX REPLACE "-+$" "" REVISION_SLUG "${REVISION_SLUG}")
    # join with semver
    string(JOIN - REVISION_SLUG "${REVISION_SLUG}" "${SEMVER_FULL}")
  else()
    set(REVISION_SLUG "${SEMVER_FULL}")
  endif()

  # Propagate only requested variables
  foreach(output_arg ${parse_project_version_output_args})
    foreach(external_var ${parse_project_version_${output_arg}})
      set(${external_var} "${${output_arg}}")
      list(APPEND PROPAGATE_VARS ${external_var})
    endforeach()
  endforeach()
  return(PROPAGATE ${PROPAGATE_VARS})
endfunction()

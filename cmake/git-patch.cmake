# Applies a patch to the git checkout in the working directory, for
# FetchContent's PATCH_COMMAND. Succeeds if the patch applies or is applied
# already; fails otherwise.
#
#   cmake -Dpatch_file=<file> [-Dpatch_hash=<hash>] -P git-patch.cmake
#
# patch_hash is unused here. It's part of the command line so FetchContent sees
# a new command, and patches again, when the patch changes.

# git apply in a subfolder of another repository silently skips every file
# outside it. The working directory must be a checkout of its own, or no
# repository at all (dependencies whose history was pruned).
execute_process(
    COMMAND git rev-parse --show-toplevel
    OUTPUT_VARIABLE toplevel
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE rev_parse_result
    ERROR_QUIET
)
if(rev_parse_result EQUAL 0)
    file(REAL_PATH "${toplevel}" toplevel)
    file(REAL_PATH "${CMAKE_CURRENT_SOURCE_DIR}" here)
    if(NOT toplevel STREQUAL here)
        message(FATAL_ERROR "${here} is inside ${toplevel}, not a checkout of its own; can't apply ${patch_file}")
    endif()
endif()

execute_process(
    COMMAND git apply --check ${patch_file}
    RESULT_VARIABLE applies
    ERROR_QUIET
)
if(applies EQUAL 0)
    execute_process(COMMAND git apply ${patch_file} RESULT_VARIABLE result)
    if(NOT result EQUAL 0)
        message(FATAL_ERROR "Couldn't apply ${patch_file}")
    endif()
    message(STATUS "Applied ${patch_file}")
    return()
endif()

execute_process(
    COMMAND git apply --reverse --check ${patch_file}
    RESULT_VARIABLE applied
    ERROR_QUIET
)
if(applied EQUAL 0)
    message(STATUS "Already applied: ${patch_file}")
    return()
endif()

# An older version of the patch is probably in the way. The checkout belongs to
# FetchContent, so start it over.
message(STATUS "Resetting the sources to apply ${patch_file}")
execute_process(COMMAND git reset --hard --quiet)
execute_process(COMMAND git apply ${patch_file} RESULT_VARIABLE result)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Couldn't apply ${patch_file}")
endif()

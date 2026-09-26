# Stands in for leetal/ios-cmake's toolchain.
#
# libultraship includes leetal/ios-cmake's toolchain *after* project() when
# CMAKE_SYSTEM_NAME is iOS. That toolchain only supports the Xcode generator in
# its default "OS64COMBINED" mode. scripts/build-engine.sh uses CMake's native
# iOS support (CMAKE_SYSTEM_NAME=iOS + CMAKE_OSX_SYSROOT) with Ninja instead, so
# it points FETCHCONTENT_SOURCE_DIR_IOSTOOLCHAIN here: the include then defines
# only the one helper below.

# libultraship calls this helper from the real toolchain. Keep the same
# signature and just record the Xcode attribute, which Ninja ignores.
function(set_xcode_property TARGET XCODE_PROPERTY XCODE_VALUE XCODE_RELVERSION)
    set_property(TARGET ${TARGET} PROPERTY XCODE_ATTRIBUTE_${XCODE_PROPERTY} ${XCODE_VALUE})
endfunction()

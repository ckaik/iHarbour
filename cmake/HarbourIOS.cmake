# iHarbour's CMake support for building a libultraship game as an iOS framework.
#
# A game's CMakeLists.txt includes this file (through the patch in patches/<game>/)
# when HARBOUR_ROOT is set, before it adds libultraship. scripts/build-engine.sh
# sets these cache variables:
#
#   HARBOUR_ROOT            this repository
#   HARBOUR_GAME            the game's id, which names its folder in ports/ (soh, 2ship, ...)
#   HARBOUR_FRAMEWORK_NAME  the framework's name (ShipOfHarkinian, ...)
#
# The file does three things:
#
# 1. Enables Objective-C(++), which SDL and the engine glue need.
# 2. Fetches and builds the libraries desktop builds take from the system
#    (brew, apt, vcpkg): SDL2 (with iHarbour's UIScene patch), SDL2_net, Ogg,
#    Vorbis, Opus and opusfile. Declared before libultraship's own
#    FetchContent_Declare calls, these win.
# 3. Defines harbour_add_game_framework(), which turns the game's shared library
#    target into the framework the launcher app loads.

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "HarbourIOS.cmake is for iOS builds (CMAKE_SYSTEM_NAME=iOS)")
endif()
if(NOT HARBOUR_GAME OR NOT HARBOUR_FRAMEWORK_NAME)
    message(FATAL_ERROR "HARBOUR_GAME and HARBOUR_FRAMEWORK_NAME must be set; build with scripts/build-engine.sh")
endif()

enable_language(OBJC OBJCXX)

include(FetchContent)

set(HARBOUR_PATCH_DIR ${HARBOUR_ROOT}/patches)
set(HARBOUR_GIT_PATCH ${HARBOUR_ROOT}/cmake/git-patch.cmake)

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(CMAKE_POLICY_DEFAULT_CMP0077 NEW)

#=================== SDL2 ===================
# The release libultraship pins for iOS, plus UIScene support: apps built against
# the iOS 27 SDK must use the scene life cycle, and SDL2 creates its UIWindow
# without a scene, which then never shows up. See patches/sdl2/.
set(SDL_TEST OFF CACHE BOOL "" FORCE)
set(HARBOUR_SDL2_PATCH ${HARBOUR_PATCH_DIR}/sdl2/sdl2-uikit-scene-support.patch)
# Editing the patch re-runs CMake, and its hash in the patch command makes
# FetchContent see a changed command and patch the sources again.
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${HARBOUR_SDL2_PATCH})
file(MD5 ${HARBOUR_SDL2_PATCH} HARBOUR_SDL2_PATCH_HASH)
FetchContent_Declare(
    SDL2
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG release-2.32.10
    PATCH_COMMAND ${CMAKE_COMMAND} -Dpatch_file=${HARBOUR_SDL2_PATCH} -Dpatch_hash=${HARBOUR_SDL2_PATCH_HASH} -P ${HARBOUR_GIT_PATCH}
    OVERRIDE_FIND_PACKAGE
)
FetchContent_MakeAvailable(SDL2)

#=================== SDL2_net ===================
set(SDL2NET_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL2NET_SAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    SDL2_net
    GIT_REPOSITORY https://github.com/libsdl-org/SDL_net.git
    GIT_TAG release-2.2.0
    OVERRIDE_FIND_PACKAGE
)
FetchContent_MakeAvailable(SDL2_net)
# Games include <SDL2/SDL_net.h>, the layout a system install has.
file(COPY ${sdl2_net_SOURCE_DIR}/SDL_net.h DESTINATION ${CMAKE_BINARY_DIR}/harbour-include/SDL2)
target_include_directories(SDL2_net INTERFACE $<BUILD_INTERFACE:${CMAKE_BINARY_DIR}/harbour-include>)

#=================== Ogg / Vorbis ===================
set(INSTALL_DOCS OFF CACHE BOOL "" FORCE)
set(INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(INSTALL_CMAKE_PACKAGE_MODULE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    Ogg
    GIT_REPOSITORY https://github.com/xiph/ogg.git
    GIT_TAG v1.3.6
    OVERRIDE_FIND_PACKAGE
)
FetchContent_MakeAvailable(Ogg)

FetchContent_Declare(
    Vorbis
    GIT_REPOSITORY https://github.com/xiph/vorbis.git
    GIT_TAG v1.3.7
    OVERRIDE_FIND_PACKAGE
)
# vorbis 1.3.7 still declares cmake_minimum_required(2.8), which CMake 4 refuses.
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)
FetchContent_MakeAvailable(Vorbis)
unset(CMAKE_POLICY_VERSION_MINIMUM)
# Games that find_package(Vorbis) expect namespaced targets.
foreach(harbour_vorbis_lib vorbis vorbisenc vorbisfile)
    if(TARGET ${harbour_vorbis_lib} AND NOT TARGET Vorbis::${harbour_vorbis_lib})
        add_library(Vorbis::${harbour_vorbis_lib} ALIAS ${harbour_vorbis_lib})
    endif()
endforeach()

#=================== Opus / Opusfile ===================
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    Opus
    GIT_REPOSITORY https://github.com/xiph/opus.git
    GIT_TAG v1.5.2
    OVERRIDE_FIND_PACKAGE
)
FetchContent_MakeAvailable(Opus)

# The opusfile 0.12 release has no CMake build, and the games only need the
# decoder (no HTTP streaming), so build its four sources directly.
FetchContent_Declare(
    opusfile
    GIT_REPOSITORY https://github.com/xiph/opusfile.git
    GIT_TAG v0.12
)
FetchContent_MakeAvailable(opusfile)
if(NOT TARGET opusfile)
    add_library(opusfile STATIC
        ${opusfile_SOURCE_DIR}/src/info.c
        ${opusfile_SOURCE_DIR}/src/internal.c
        ${opusfile_SOURCE_DIR}/src/opusfile.c
        ${opusfile_SOURCE_DIR}/src/stream.c
    )
    target_include_directories(opusfile PUBLIC ${opusfile_SOURCE_DIR}/include)
    target_compile_definitions(opusfile PRIVATE OP_DISABLE_HTTP OP_HAVE_LRINTF)
    target_compile_options(opusfile PRIVATE -w)
    target_link_libraries(opusfile PUBLIC Ogg::ogg Opus::opus)
    add_library(OpusFile::opusfile ALIAS opusfile)
endif()

#=================== Game-specific additions ===================
# ports/<game>/port.cmake, if there is one, adds what only that game needs
# (another library, aliases for the names its find_package calls expect, ...).
if(EXISTS ${HARBOUR_ROOT}/ports/${HARBOUR_GAME}/port.cmake)
    include(${HARBOUR_ROOT}/ports/${HARBOUR_GAME}/port.cmake)
endif()

#=================== The framework ===================
# harbour_add_game_framework(<target>)
#
# Turns <target>, a SHARED library holding the whole game, into
# ${HARBOUR_FRAMEWORK_NAME}.framework: adds the engine glue (engine/) and the
# game's port glue (ports/${HARBOUR_GAME}/), links the iOS dependencies, and
# exports HarbourEngine_GetAPI and nothing else, so two games' frameworks in one
# process can't bind to each other's copies of libultraship, SDL, ImGui, ...
function(harbour_add_game_framework target)
    if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
        set(HARBOUR_IOS_PLATFORM "iPhoneSimulator")
    else()
        set(HARBOUR_IOS_PLATFORM "iPhoneOS")
    endif()
    # Read by engine/Info.plist.in.
    set(MACOSX_FRAMEWORK_NAME ${HARBOUR_FRAMEWORK_NAME} PARENT_SCOPE)
    set(HARBOUR_IOS_PLATFORM ${HARBOUR_IOS_PLATFORM} PARENT_SCOPE)

    file(GLOB harbour_engine_sources CONFIGURE_DEPENDS
        ${HARBOUR_ROOT}/engine/*.h ${HARBOUR_ROOT}/engine/*.mm ${HARBOUR_ROOT}/engine/*.cpp)
    file(GLOB harbour_port_sources CONFIGURE_DEPENDS
        ${HARBOUR_ROOT}/ports/${HARBOUR_GAME}/*.h
        ${HARBOUR_ROOT}/ports/${HARBOUR_GAME}/*.c
        ${HARBOUR_ROOT}/ports/${HARBOUR_GAME}/*.cpp
        ${HARBOUR_ROOT}/ports/${HARBOUR_GAME}/*.mm)
    target_sources(${target} PRIVATE ${harbour_engine_sources} ${harbour_port_sources})
    set(harbour_objc_sources ${harbour_engine_sources} ${harbour_port_sources})
    list(FILTER harbour_objc_sources INCLUDE REGEX "\\.mm$")
    set_source_files_properties(${harbour_objc_sources} PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
    target_include_directories(${target} PRIVATE ${HARBOUR_ROOT}/engine ${HARBOUR_ROOT}/ports/${HARBOUR_GAME})
    # HARBOUR_IOS lets a game's patch tell iHarbour's build from a standalone iOS one.
    target_compile_definitions(${target} PRIVATE
        HARBOUR_IOS=1
        HARBOUR_GAME_ID="${HARBOUR_GAME}"
        HARBOUR_FRAMEWORK_NAME="${HARBOUR_FRAMEWORK_NAME}")

    target_link_libraries(${target} PRIVATE
        SDL2::SDL2-static
        SDL2_net::SDL2_net-static
        Ogg::ogg
        vorbis
        vorbisenc
        vorbisfile
        Opus::opus
        OpusFile::opusfile
        "-framework AVFoundation"
        "-framework Foundation"
        "-framework UIKit"
    )
    target_link_options(${target} PRIVATE
        "LINKER:-exported_symbol,_HarbourEngine_GetAPI"
        "LINKER:-dead_strip"
    )

    string(TOLOWER "${HARBOUR_GAME}" harbour_game_lower)
    set_target_properties(${target} PROPERTIES
        FRAMEWORK TRUE
        OUTPUT_NAME ${HARBOUR_FRAMEWORK_NAME}
        MACOSX_FRAMEWORK_IDENTIFIER "org.iharbour.engine.${harbour_game_lower}"
        MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${CMAKE_PROJECT_VERSION}"
        MACOSX_FRAMEWORK_BUNDLE_VERSION "${CMAKE_PROJECT_VERSION}"
        MACOSX_FRAMEWORK_INFO_PLIST "${HARBOUR_ROOT}/engine/Info.plist.in"
        INSTALL_NAME_DIR "@rpath"
        BUILD_WITH_INSTALL_RPATH TRUE
    )
endfunction()

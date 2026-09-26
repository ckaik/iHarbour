# What only 2 Ship 2 Harkinian needs on iOS. Included by cmake/HarbourIOS.cmake.

#=================== libpng ===================
# The game extracts the ROM with ZAPD, which it links as a library (ZAPDLib), and
# ZAPD finds libpng with find_package(PNG REQUIRED). iOS has no libpng, so build
# it here, against the SDK's zlib. (ZAPD reads PNGs when it packs the game's own
# textures into 2ship.o2r, which happens on the Mac.)
set(PNG_SHARED OFF CACHE BOOL "" FORCE)
set(PNG_STATIC ON CACHE BOOL "" FORCE)
set(PNG_FRAMEWORK OFF CACHE BOOL "" FORCE)
set(PNG_TESTS OFF CACHE BOOL "" FORCE)
set(PNG_TOOLS OFF CACHE BOOL "" FORCE)
set(PNG_HARDWARE_OPTIMIZATIONS OFF CACHE BOOL "" FORCE)
set(SKIP_INSTALL_ALL ON CACHE BOOL "" FORCE)
FetchContent_Declare(
    PNG
    GIT_REPOSITORY https://github.com/pnggroup/libpng.git
    GIT_TAG v1.6.47
    OVERRIDE_FIND_PACKAGE
)
FetchContent_MakeAvailable(PNG)
# find_package(PNG) now finds the (empty) config FetchContent writes, so provide
# what ZAPD's CMakeLists.txt uses from CMake's FindPNG.
if(NOT TARGET PNG::PNG)
    add_library(PNG::PNG ALIAS png_static)
endif()
# png_static carries its include directories (png.h, the generated pnglibconf.h).
set(PNG_PNG_INCLUDE_DIR ${png_SOURCE_DIR})

#=================== <opus/opus.h> ===================
# The game includes <opus/opus.h>, the layout a system install has; the Opus
# sources keep the headers in include/.
file(GLOB harbour_opus_headers ${opus_SOURCE_DIR}/include/*.h)
file(COPY ${harbour_opus_headers} DESTINATION ${CMAKE_BINARY_DIR}/harbour-include/opus)
target_include_directories(opus INTERFACE $<BUILD_INTERFACE:${CMAKE_BINARY_DIR}/harbour-include>)

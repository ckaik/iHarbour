# Starship's additions to cmake/HarbourIOS.cmake, which includes this file from
# the game's top-level CMakeLists.txt, before libultraship and Torch are added.

# The fmt that libultraship's spdlog (v1.14.1) bundles doesn't compile its
# consteval format-string checks with Xcode 27's clang ("call to consteval
# function 'fmt::basic_format_string<...>' is not a constant expression").
# Empty, FMT_CONSTEVAL falls back to fmt's constexpr checks, with the same
# runtime behavior. Set for the whole directory, so spdlog, libultraship, Torch
# and the game all see the same fmt; SDL and the codecs are added before this.
add_compile_definitions(FMT_CONSTEVAL=)

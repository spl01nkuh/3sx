# Native iOS build. Configure with tools/build-ios.sh on a Mac with Xcode.
if(CMAKE_VERSION VERSION_LESS 3.29)
    message(FATAL_ERROR "The iOS target requires CMake 3.29 or newer")
endif()
if(NOT CMAKE_OSX_DEPLOYMENT_TARGET)
    set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0" CACHE STRING "Minimum supported iOS version" FORCE)
elseif(CMAKE_OSX_DEPLOYMENT_TARGET VERSION_LESS 15.0)
    message(FATAL_ERROR "The iOS target requires a deployment target of iOS 15.0 or newer")
endif()

# Game data is optional and stays outside the source tree. Validate before
# downloading dependencies so an invalid input fails immediately.
set(THREESX_IOS_AFS_FILE "" CACHE FILEPATH "Optional local SF33RD.AFS to bundle in the iOS app")
set(IOS_BUNDLED_AFS "${CMAKE_CURRENT_BINARY_DIR}/ios-bundled-resources/SF33RD.AFS")
if(THREESX_IOS_AFS_FILE)
    get_filename_component(IOS_AFS_INPUT "${THREESX_IOS_AFS_FILE}" ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")
    if(NOT EXISTS "${IOS_AFS_INPUT}" OR IS_DIRECTORY "${IOS_AFS_INPUT}")
        message(FATAL_ERROR "THREESX_IOS_AFS_FILE must point to an existing SF33RD.AFS file")
    endif()
    file(SHA256 "${IOS_AFS_INPUT}" IOS_AFS_SHA256)
    if(NOT IOS_AFS_SHA256 STREQUAL "f9fa50f3a124ec9fa9465aa9c8546c2d867887eb39f711a070762a0324ba5604")
        message(FATAL_ERROR "THREESX_IOS_AFS_FILE does not match the supported PS2 SF33RD.AFS SHA-256")
    endif()
    configure_file("${IOS_AFS_INPUT}" "${IOS_BUNDLED_AFS}" COPYONLY)
else()
    file(REMOVE "${IOS_BUNDLED_AFS}")
endif()

enable_language(OBJC)
include(FetchContent)

if(THREESX_STATCHECK OR THREESX_ARCADE_ROM_TEXTURES)
    message(FATAL_ERROR "The initial iOS port supports offline play with PS2 AFS resources only")
endif()

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_OBJC_STANDARD 11)

set(THREESX_IOS_BUNDLE_IDENTIFIER "org.crowdedstreet.3sx" CACHE STRING "iOS application bundle identifier")
set(THREESX_IOS_DEVELOPMENT_TEAM "" CACHE STRING "Apple development team for device signing")
option(THREESX_IOS_SIGN "Enable automatic code signing for device builds" OFF)

# Build these for the selected SDK and architecture; desktop .a/.dylib files
# cannot be linked into an iOS app. FETCHCONTENT_SOURCE_DIR_* overrides allow
# local source checkouts for offline builds.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL_OPENGL OFF CACHE BOOL "" FORCE)
set(SDL_OPENGLES OFF CACHE BOOL "" FORCE)
set(SDL_VULKAN OFF CACHE BOOL "" FORCE)
set(SDL_METAL ON CACHE BOOL "" FORCE)
FetchContent_Declare(threesx_sdl
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG f87239e71e42da91ca317a12eefb82cfbf3393eb # release-3.4.12
)
FetchContent_MakeAvailable(threesx_sdl)

find_package(ZLIB REQUIRED)
set(MZ_COMPAT OFF CACHE BOOL "" FORCE)
set(MZ_ZLIB ON CACHE BOOL "" FORCE)
set(MZ_ZLIB_FLAVOR zlib CACHE STRING "" FORCE)
set(MZ_FETCH_LIBS OFF CACHE BOOL "" FORCE)
set(MZ_BZIP2 OFF CACHE BOOL "" FORCE)
set(MZ_LZMA OFF CACHE BOOL "" FORCE)
set(MZ_PPMD OFF CACHE BOOL "" FORCE)
set(MZ_ZSTD OFF CACHE BOOL "" FORCE)
set(MZ_LIBCOMP OFF CACHE BOOL "" FORCE)
set(MZ_PKCRYPT OFF CACHE BOOL "" FORCE)
set(MZ_WZAES OFF CACHE BOOL "" FORCE)
set(MZ_OPENSSL OFF CACHE BOOL "" FORCE)
set(MZ_LIBBSD OFF CACHE BOOL "" FORCE)
set(MZ_ICONV OFF CACHE BOOL "" FORCE)
set(MZ_DECOMPRESS_ONLY ON CACHE BOOL "" FORCE)
set(MZ_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(MZ_BUILD_UNIT_TESTS OFF CACHE BOOL "" FORCE)
FetchContent_Declare(threesx_minizip
    GIT_REPOSITORY https://github.com/zlib-ng/minizip-ng.git
    GIT_TAG cf4b58e17ebdcff8c6fbce1a9c3af5bf0485423c # 4.1.0
)
FetchContent_MakeAvailable(threesx_minizip)

# The game's installed-header spelling is minizip-ng/mz.h; a source build's
# headers live at its root. Preserve the spelling without modifying the library.
file(GLOB MINIZIP_HEADERS "${threesx_minizip_SOURCE_DIR}/*.h")
file(COPY ${MINIZIP_HEADERS} DESTINATION "${CMAKE_CURRENT_BINARY_DIR}/ios-includes/minizip-ng")

file(GLOB_RECURSE IOS_GAME_SRC CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/src/*.c")
list(FILTER IOS_GAME_SRC EXCLUDE REGEX "/platform/video/opengl/")
file(GLOB_RECURSE IOS_OBJC_SRC CONFIGURE_DEPENDS "${PROJECT_SOURCE_DIR}/src/*.m")
add_executable(3sx MACOSX_BUNDLE ${IOS_GAME_SRC} ${IOS_OBJC_SRC})
if(THREESX_IOS_AFS_FILE)
    set_source_files_properties("${IOS_BUNDLED_AFS}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/game-data")
    target_sources(3sx PRIVATE "${IOS_BUNDLED_AFS}")
else()
    # Xcode can retain copied resources when reusing a build directory. Remove
    # a previously bundled archive when the option has been cleared.
    add_custom_command(TARGET 3sx PRE_BUILD
        COMMAND "${CMAKE_COMMAND}" -E rm -f "$<TARGET_BUNDLE_DIR:3sx>/game-data/SF33RD.AFS"
        VERBATIM
    )
endif()
add_custom_command(TARGET 3sx PRE_BUILD
    COMMAND "${CMAKE_COMMAND}" -E rm -rf "$<TARGET_BUNDLE_DIR:3sx>/resources"
    VERBATIM
)
target_include_directories(3sx PRIVATE
    "${PROJECT_SOURCE_DIR}/src"
    "${PROJECT_SOURCE_DIR}/src/sdk"
    "${PROJECT_SOURCE_DIR}/src/imgui/imgui"
    "${PROJECT_SOURCE_DIR}/src/imgui/dcimgui"
    "${CMAKE_CURRENT_BINARY_DIR}/ios-includes"
)
target_compile_definitions(3sx PRIVATE
    CRS_PLATFORM_IOS=1
    THREESX_IOS=1
    CRS_APP_DRIVER_SDL=1
    CRS_VIDEO_DRIVER_SDL_GENERIC=1
    CRS_VIDEO_DRIVER_SDL_GPU=1
    CRS_INPUT_DRIVER_SDL=1
    SOUND_ENABLED=1
    CHECKSUM=1
    $<$<CONFIG:Debug>:DEBUG=1>
    $<$<NOT:$<CONFIG:Debug>>:RELEASE=1>
)
target_compile_options(3sx PRIVATE
    -Wall -Werror -fno-strict-aliasing
    -Wpointer-to-int-cast
    -Wno-deprecated-non-prototype
    -Wno-tautological-overlap-compare
    -Wno-unused-variable
    $<$<CONFIG:Debug>:-Wno-unused-function>
    $<$<CONFIG:Debug>:-Wno-unused-but-set-variable>
)
target_link_libraries(3sx PRIVATE
    SDL3::SDL3-static MINIZIP::minizip ZLIB::ZLIB
    "-framework UIKit" "-framework UniformTypeIdentifiers"
)
if(IOS_OBJC_SRC)
    set_source_files_properties(${IOS_OBJC_SRC} PROPERTIES COMPILE_OPTIONS "-fobjc-arc")
endif()

set_target_properties(3sx PROPERTIES
    OUTPUT_NAME "3SX"
    MACOSX_BUNDLE_BUNDLE_NAME "3SX"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${THREESX_IOS_BUNDLE_IDENTIFIER}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "0.3.0"
    MACOSX_BUNDLE_BUNDLE_VERSION "4"
    MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/cmake/iOS-Info.plist"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${THREESX_IOS_BUNDLE_IDENTIFIER}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
    XCODE_ATTRIBUTE_ENABLE_BITCODE NO
    # The shared game code uses PS2-width values. Keep Xcode aligned with the
    # project's desktop warning settings; -Wall and -Werror remain enabled.
    XCODE_ATTRIBUTE_GCC_WARN_64_TO_32_BIT_CONVERSION NO
    XCODE_ATTRIBUTE_SKIP_INSTALL NO
    XCODE_ATTRIBUTE_INSTALL_PATH "$(LOCAL_APPS_DIR)"
)
if(THREESX_IOS_SIGN)
    if(NOT THREESX_IOS_DEVELOPMENT_TEAM)
        message(FATAL_ERROR "Set THREESX_IOS_DEVELOPMENT_TEAM to enable device signing")
    endif()
    set_target_properties(3sx PROPERTIES
        XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${THREESX_IOS_DEVELOPMENT_TEAM}"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED YES
    )
else()
    set_target_properties(3sx PROPERTIES XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
endif()

# CMake strips the leading Resources component for the flat iOS bundle layout.
# SDL_GetBasePath() can then find assets and Metal source shaders in the app.
function(threesx_ios_resources source_dir destination)
    file(GLOB_RECURSE resource_files CONFIGURE_DEPENDS "${source_dir}/*")
    foreach(resource IN LISTS resource_files)
        file(RELATIVE_PATH relative "${source_dir}" "${resource}")
        get_filename_component(subdirectory "${relative}" DIRECTORY)
        set_source_files_properties("${resource}" PROPERTIES
            MACOSX_PACKAGE_LOCATION "Resources/${destination}/${subdirectory}"
        )
    endforeach()
    target_sources(3sx PRIVATE ${resource_files})
endfunction()
threesx_ios_resources("${PROJECT_SOURCE_DIR}/assets" "assets")
threesx_ios_resources("${PROJECT_SOURCE_DIR}/src/platform/video/sdl_gpu/shaders/compiled/msl" "shaders/sdlgpu/msl")

configure_file("${threesx_sdl_SOURCE_DIR}/LICENSE.txt" "ios-licenses/SDL.txt" COPYONLY)
configure_file("${threesx_minizip_SOURCE_DIR}/LICENSE" "ios-licenses/minizip-ng.txt" COPYONLY)
threesx_ios_resources("${CMAKE_CURRENT_BINARY_DIR}/ios-licenses" "licenses")
set(IOS_LICENSE_FILES "${PROJECT_SOURCE_DIR}/LICENSE" "${PROJECT_SOURCE_DIR}/THIRD_PARTY_NOTICES.txt"
    "${PROJECT_SOURCE_DIR}/third_party_sources/carlos-crt/COPYING.GPL3")
set_source_files_properties(${IOS_LICENSE_FILES} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/licenses")
target_sources(3sx PRIVATE ${IOS_LICENSE_FILES})
install(TARGETS 3sx BUNDLE DESTINATION .)

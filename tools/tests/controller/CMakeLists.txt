cmake_minimum_required(VERSION 3.24)
project(3sx_controller_test LANGUAGES C)
set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
get_filename_component(THREESX_ROOT "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)
set(SDL3_SOURCE_DIR "" CACHE PATH "Local checkout of the project's pinned SDL3")
if(NOT EXISTS "${SDL3_SOURCE_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "Set SDL3_SOURCE_DIR to an SDL3 source checkout")
endif()
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SDL_INSTALL OFF CACHE BOOL "" FORCE)
set(SDL_AUDIO OFF CACHE BOOL "" FORCE)
set(SDL_VIDEO OFF CACHE BOOL "" FORCE)
set(SDL_GPU OFF CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
set(SDL_HAPTIC OFF CACHE BOOL "" FORCE)
set(SDL_SENSOR OFF CACHE BOOL "" FORCE)
set(SDL_JOYSTICK ON CACHE BOOL "" FORCE)
set(SDL_VIRTUAL_JOYSTICK ON CACHE BOOL "" FORCE)
set(SDL_HIDAPI ON CACHE BOOL "" FORCE)
set(SDL_HIDAPI_JOYSTICK OFF CACHE BOOL "" FORCE)
set(SDL_UNIX_CONSOLE_BUILD ON CACHE BOOL "" FORCE)
add_subdirectory("${SDL3_SOURCE_DIR}" sdl EXCLUDE_FROM_ALL)
add_executable(test-ios-controller
    ../test-ios-controller.c
    "${THREESX_ROOT}/src/core/input.c"
    "${THREESX_ROOT}/src/platform/input/sdl/sdl_pad.c"
    "${THREESX_ROOT}/src/platform/input/ios/ios_touch_state.c"
    "${THREESX_ROOT}/src/platform/app/ios/ios_options.c"
    "${THREESX_ROOT}/src/port/config/keymap.c"
    "${THREESX_ROOT}/src/port/sdk/sdk_libpad2.c"
    "${THREESX_ROOT}/src/sf33rd/AcrSDK/common/mlPAD.c"
    "${THREESX_ROOT}/src/sf33rd/AcrSDK/ps2/flPADUSR.c"
    "${THREESX_ROOT}/src/sf33rd/AcrSDK/ps2/ps2PAD.c"
    "${THREESX_ROOT}/src/sf33rd/Source/Game/io/ioconv.c"
    "${THREESX_ROOT}/src/sf33rd/Source/Game/system/work_sys.c"
    "${THREESX_ROOT}/src/sf33rd/Source/Game/engine/workuser.c"
)
target_include_directories(test-ios-controller PRIVATE "${THREESX_ROOT}/src" "${THREESX_ROOT}/src/sdk")
target_compile_definitions(test-ios-controller PRIVATE CRS_PLATFORM_IOS=1 CRS_INPUT_DRIVER_SDL=1)
target_compile_options(test-ios-controller PRIVATE -UNDEBUG -ffunction-sections -fdata-sections)
if(APPLE)
    target_link_options(test-ios-controller PRIVATE -Wl,-dead_strip)
else()
    target_link_options(test-ios-controller PRIVATE -Wl,--gc-sections)
    target_link_libraries(test-ios-controller PRIVATE m)
endif()
target_link_libraries(test-ios-controller PRIVATE SDL3::SDL3-static)
enable_testing()
add_test(NAME ios-controller-game-directions COMMAND test-ios-controller)

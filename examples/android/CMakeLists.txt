cmake_minimum_required(VERSION 3.18.1)

project("zigtaptun_android")

# Configure Zig compiler
set(ZIG_COMPILER "zig" CACHE STRING "Path to Zig compiler")

# Determine target triple based on Android ABI
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(ZIG_TARGET "aarch64-linux-android")
elseif(ANDROID_ABI STREQUAL "armeabi-v7a")
    set(ZIG_TARGET "armv7a-linux-androideabi")
elseif(ANDROID_ABI STREQUAL "x86_64")
    set(ZIG_TARGET "x86_64-linux-android")
elseif(ANDROID_ABI STREQUAL "x86")
    set(ZIG_TARGET "i386-linux-android")
else()
    message(FATAL_ERROR "Unsupported Android ABI: ${ANDROID_ABI}")
endif()

# Set Zig build directory
set(ZIG_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/zig-build")
file(MAKE_DIRECTORY ${ZIG_BUILD_DIR})

# Build ZigTapTun library with Zig
set(ZIG_LIB_OUTPUT "${ZIG_BUILD_DIR}/libtaptun.a")
set(ZIG_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../../")

add_custom_command(
    OUTPUT ${ZIG_LIB_OUTPUT}
    COMMAND ${ZIG_COMPILER} build
        -Dtarget=${ZIG_TARGET}
        -Doptimize=ReleaseFast
        --prefix ${ZIG_BUILD_DIR}
        --prefix-lib-dir ${ZIG_BUILD_DIR}
    WORKING_DIRECTORY ${ZIG_SRC_DIR}
    COMMENT "Building ZigTapTun library for ${ANDROID_ABI}"
    VERBATIM
)

add_custom_target(zig_taptun_build ALL DEPENDS ${ZIG_LIB_OUTPUT})

# Create JNI wrapper library
add_library(taptun SHARED
    cpp/jni_wrapper.cpp
)

# Link against Zig library
target_link_libraries(taptun
    ${ZIG_LIB_OUTPUT}
    log
)

# Include directories
target_include_directories(taptun PRIVATE
    cpp
    ${ZIG_SRC_DIR}/src
)

# Ensure Zig library is built first
add_dependencies(taptun zig_taptun_build)

# Strip symbols in release builds
if(CMAKE_BUILD_TYPE STREQUAL "Release")
    add_custom_command(TARGET taptun POST_BUILD
        COMMAND ${CMAKE_STRIP} --strip-all $<TARGET_FILE:taptun>
    )
endif()

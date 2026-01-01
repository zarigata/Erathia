cmake_minimum_required(VERSION 3.20)
project(erathia_terrain_native)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Detect platform and architecture
if(CMAKE_SYSTEM_NAME STREQUAL "Windows")
    set(PLATFORM "windows")
    set(EXTENSION ".dll")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
    set(PLATFORM "linux")
    set(EXTENSION ".so")
elseif(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(PLATFORM "macos")
    set(EXTENSION ".dylib")
endif()

# Architecture detection for macOS
if(CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    if(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64;x86_64" OR CMAKE_OSX_ARCHITECTURES STREQUAL "x86_64;arm64")
        set(ARCH "universal")
    elseif(CMAKE_OSX_ARCHITECTURES STREQUAL "arm64" OR CMAKE_SYSTEM_PROCESSOR STREQUAL "arm64")
        set(ARCH "arm64")
    else()
        set(ARCH "x86_64")
    endif()
else()
    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(ARCH "x86_64")
    else()
        set(ARCH "x86_32")
    endif()
endif()

# Build type (debug/release)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Debug")
endif()

# godot-cpp library
add_subdirectory(godot-cpp)

# Source files
file(GLOB_RECURSE SOURCES src/*.cpp)

# Create shared library
add_library(${PROJECT_NAME} SHARED ${SOURCES})

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/../godot_voxel_cpp
)

# Define ZN_GODOT_EXTENSION for voxel_cpp
target_compile_definitions(${PROJECT_NAME} PRIVATE ZN_GODOT_EXTENSION)

# Link godot-cpp (godot_voxel_cpp headers are header-only for our usage)
target_link_libraries(${PROJECT_NAME} PRIVATE godot::cpp)

# Output naming convention using generator expressions for configuration-specific names
# Debug builds produce .editor. artifacts, Release builds produce .template_release. artifacts
set_target_properties(${PROJECT_NAME} PROPERTIES
    OUTPUT_NAME_DEBUG "liberathia_terrain.${PLATFORM}.editor.${ARCH}"
    OUTPUT_NAME_RELEASE "liberathia_terrain.${PLATFORM}.template_release.${ARCH}"
    PREFIX ""
    SUFFIX "${EXTENSION}"
)

# Output directory - directly to bin/ without Debug/Release subdirectories
set_target_properties(${PROJECT_NAME} PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY_DEBUG "${CMAKE_SOURCE_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_DEBUG "${CMAKE_SOURCE_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_SOURCE_DIR}/bin"
)

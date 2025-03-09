# =============================================================================
# Top-level CMake configuration for Watsonx Code Assistant
# =============================================================================

cmake_minimum_required(VERSION 3.14)

# Project definition
project(WatsonxCodeAssistant
        VERSION 1.0.0
        DESCRIPTION "IBM Watsonx Code Assistant - AI coding platform"
        HOMEPAGE_URL "https://github.com/IBM/watsonx-code-assistant-individual"
        LANGUAGES C CXX)

# Include custom modules
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/.cmake")

# Options
option(BUILD_TESTS "Build the test suite" ON)
option(CODE_COVERAGE "Enable code coverage" OFF)
option(BUILD_DOCS "Build documentation" OFF)
option(DEBUG "Enable debug mode" OFF)
option(USE_SYSTEM_DEPS "Use system dependencies instead of bundled ones" OFF)
option(ENABLE_SANITIZERS "Enable sanitizers in debug builds" OFF)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Set default build type if not specified
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Build type" FORCE)
endif()

# Configure compiler warnings
if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wextra -Wpedantic")
    if(DEBUG)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g3 -O0")
    endif()
elseif(MSVC)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /W4 /permissive-")
    if(DEBUG)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /Zi /Od")
    endif()
endif()

# Enable sanitizers in debug mode if requested
if(ENABLE_SANITIZERS AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address,undefined -fno-omit-frame-pointer")
    endif()
endif()

# Output directories
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# Find required packages
find_package(Python3 COMPONENTS Interpreter Development REQUIRED)
find_package(PythonLibs 3 REQUIRED)
find_package(Threads REQUIRED)

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${PYTHON_INCLUDE_DIRS}
)

# Subdirectories
add_subdirectory(src)

# Build tests if enabled
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
endif()

# Documentation
if(BUILD_DOCS)
    find_package(Doxygen)
    if(DOXYGEN_FOUND)
        add_subdirectory(docs)
    else()
        message(WARNING "Doxygen not found, documentation will not be built")
    endif()
endif()

# Configure package
include(InstallRequiredSystemLibraries)
set(CPACK_PACKAGE_NAME "${PROJECT_NAME}")
set(CPACK_PACKAGE_VENDOR "IBM")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "${PROJECT_DESCRIPTION}")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_VERSION_MAJOR "${PROJECT_VERSION_MAJOR}")
set(CPACK_PACKAGE_VERSION_MINOR "${PROJECT_VERSION_MINOR}")
set(CPACK_PACKAGE_VERSION_PATCH "${PROJECT_VERSION_PATCH}")
set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/LICENSE")
set(CPACK_RESOURCE_FILE_README "${CMAKE_CURRENT_SOURCE_DIR}/README.md")

# Package file format configuration
if(WIN32)
    set(CPACK_GENERATOR "NSIS;ZIP")
elseif(APPLE)
    set(CPACK_GENERATOR "DragNDrop;TGZ")
else()
    set(CPACK_GENERATOR "DEB;RPM;TGZ")
endif()

# Include CPack to enable packaging
include(CPack)

# Print configuration summary
message(STATUS "=====================================================")
message(STATUS "Project: ${PROJECT_NAME} ${PROJECT_VERSION}")
message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
message(STATUS "Tests: ${BUILD_TESTS}")
message(STATUS "Debug mode: ${DEBUG}")
message(STATUS "Code coverage: ${CODE_COVERAGE}")
message(STATUS "Documentation: ${BUILD_DOCS}")
message(STATUS "Sanitizers: ${ENABLE_SANITIZERS}")
message(STATUS "System dependencies: ${USE_SYSTEM_DEPS}")
message(STATUS "=====================================================")

# Export compile commands for linter tools
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

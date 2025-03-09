#!/bin/bash
# CMake Deployment Script for Watsonx Code Assistant
# Installs, configures and deploys CMake with Ninja for optimal build performance

set -eo pipefail

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
CMAKE_VERSION=${CMAKE_VERSION:-"3.28.1"}
NINJA_VERSION=${NINJA_VERSION:-"1.11.1"}
BUILD_DIR=${BUILD_DIR:-"build"}
CONFIG_DIR=${CONFIG_DIR:-".cmake"}
CMAKE_GENERATOR=${CMAKE_GENERATOR:-"Ninja"}
BUILD_TYPE=${BUILD_TYPE:-"Release"}
INSTALL_PREFIX=${INSTALL_PREFIX:-""}
NUM_JOBS=${NUM_JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}

# Print banner
echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${BLUE}${BOLD}     CMake + Ninja Deployment for Watsonx Code Assistant          ${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"

# Check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Check for required tools
    for cmd in curl wget tar make gcc g++; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${YELLOW}⚠️ Command not found: $cmd${NC}"
        else
            echo -e "${GREEN}✓ Found: $cmd${NC}"
        fi
    done
    
    # Check if CMake is already installed
    if command -v cmake &> /dev/null; then
        INSTALLED_CMAKE_VERSION=$(cmake --version | head -n1 | awk '{print $3}')
        echo -e "${GREEN}✓ CMake already installed: v${INSTALLED_CMAKE_VERSION}${NC}"
        
        # Check if version meets requirements
        if [ "$(printf '%s\n' "$CMAKE_VERSION" "$INSTALLED_CMAKE_VERSION" | sort -V | head -n1)" = "$CMAKE_VERSION" ]; then
            echo -e "${GREEN}✓ Installed CMake meets version requirements${NC}"
        else
            echo -e "${YELLOW}⚠️ Installed CMake version is older than required ($CMAKE_VERSION)${NC}"
            echo -e "${YELLOW}⚠️ Will install newer version${NC}"
            INSTALL_CMAKE=true
        fi
    else
        echo -e "${YELLOW}⚠️ CMake not found, will install${NC}"
        INSTALL_CMAKE=true
    fi
    
    # Check if Ninja is already installed
    if command -v ninja &> /dev/null; then
        INSTALLED_NINJA_VERSION=$(ninja --version 2>/dev/null)
        echo -e "${GREEN}✓ Ninja already installed: v${INSTALLED_NINJA_VERSION}${NC}"
        
        # Check if version meets requirements
        if [ "$(printf '%s\n' "$NINJA_VERSION" "$INSTALLED_NINJA_VERSION" | sort -V | head -n1)" = "$NINJA_VERSION" ]; then
            echo -e "${GREEN}✓ Installed Ninja meets version requirements${NC}"
        else
            echo -e "${YELLOW}⚠️ Installed Ninja version is older than required ($NINJA_VERSION)${NC}"
            echo -e "${YELLOW}⚠️ Will install newer version${NC}"
            INSTALL_NINJA=true
        fi
    else
        echo -e "${YELLOW}⚠️ Ninja not found, will install${NC}"
        INSTALL_NINJA=true
    fi
    
    echo -e "${GREEN}✓ Prerequisite check completed${NC}"
}

# Install CMake if needed
install_cmake() {
    if [[ "$INSTALL_CMAKE" != "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Installing CMake v${CMAKE_VERSION}...${NC}"
    
    # Create temp directory
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    # Determine OS and architecture
    case "$(uname -s)" in
        Linux*)
            OS="Linux"
            ARCH=$(uname -m)
            if [[ "$ARCH" == "x86_64" ]]; then
                CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
            elif [[ "$ARCH" == "aarch64" ]]; then
                CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-aarch64.tar.gz"
            else
                echo -e "${RED}❌ Unsupported architecture: $ARCH${NC}"
                exit 1
            fi
            ;;
        Darwin*)
            OS="macOS"
            ARCH=$(uname -m)
            if [[ "$ARCH" == "x86_64" ]]; then
                CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-macos-universal.tar.gz"
            elif [[ "$ARCH" == "arm64" ]]; then
                CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-macos-universal.tar.gz"
            else
                echo -e "${RED}❌ Unsupported architecture: $ARCH${NC}"
                exit 1
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows*)
            OS="Windows"
            ARCH=$(uname -m)
            if [[ "$ARCH" == "x86_64" ]]; then
                CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-windows-x86_64.zip"
            else
                echo -e "${RED}❌ Unsupported architecture: $ARCH${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "${RED}❌ Unsupported operating system: $(uname -s)${NC}"
            exit 1
            ;;
    esac
    
    # Download and extract CMake
    echo -e "${YELLOW}Downloading CMake from: $CMAKE_URL${NC}"
    if [[ "$OS" == "Windows" ]]; then
        curl -sSL "$CMAKE_URL" -o cmake.zip
        unzip cmake.zip
        CMAKE_DIR=$(find . -maxdepth 1 -type d -name "cmake*" | head -n1)
    else
        curl -sSL "$CMAKE_URL" -o cmake.tar.gz
        tar -xzf cmake.tar.gz
        CMAKE_DIR=$(find . -maxdepth 1 -type d -name "cmake*" | head -n1)
    fi
    
    # Install CMake to the system or user location
    if [[ $EUID -eq 0 ]]; then
        # Running as root, install system-wide
        echo -e "${YELLOW}Installing CMake system-wide...${NC}"
        cp -r "$CMAKE_DIR"/* /usr/local/
    else
        # Running as user, install to user location
        echo -e "${YELLOW}Installing CMake to user location...${NC}"
        mkdir -p "$HOME/.local/bin"
        
        # Add to path if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
            export PATH="$HOME/.local/bin:$PATH"
        fi
        
        cp -r "$CMAKE_DIR"/bin/* "$HOME/.local/bin/"
        mkdir -p "$HOME/.local/share"
        cp -r "$CMAKE_DIR"/share/* "$HOME/.local/share/" || true
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    
    # Verify installation
    if command -v cmake &> /dev/null; then
        CMAKE_VERSION_INSTALLED=$(cmake --version | head -n1 | awk '{print $3}')
        echo -e "${GREEN}✓ CMake v${CMAKE_VERSION_INSTALLED} installed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to install CMake${NC}"
        exit 1
    fi
}

# Install Ninja if needed
install_ninja() {
    if [[ "$INSTALL_NINJA" != "true" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Installing Ninja v${NINJA_VERSION}...${NC}"
    
    # Create temp directory
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR"
    
    # Determine OS and architecture
    case "$(uname -s)" in
        Linux*)
            OS="Linux"
            NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-linux.zip"
            ;;
        Darwin*)
            OS="macOS"
            NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-mac.zip"
            ;;
        MINGW*|MSYS*|CYGWIN*|Windows*)
            OS="Windows"
            NINJA_URL="https://github.com/ninja-build/ninja/releases/download/v${NINJA_VERSION}/ninja-win.zip"
            ;;
        *)
            echo -e "${RED}❌ Unsupported operating system: $(uname -s)${NC}"
            exit 1
            ;;
    esac
    
    # Download and extract Ninja
    echo -e "${YELLOW}Downloading Ninja from: $NINJA_URL${NC}"
    curl -sSL "$NINJA_URL" -o ninja.zip
    unzip ninja.zip
    
    # Install Ninja
    if [[ $EUID -eq 0 ]]; then
        # Running as root, install system-wide
        echo -e "${YELLOW}Installing Ninja system-wide...${NC}"
        cp ninja /usr/local/bin/
        chmod +x /usr/local/bin/ninja
    else
        # Running as user, install to user location
        echo -e "${YELLOW}Installing Ninja to user location...${NC}"
        mkdir -p "$HOME/.local/bin"
        
        # Add to path if not already there
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
            export PATH="$HOME/.local/bin:$PATH"
        fi
        
        cp ninja "$HOME/.local/bin/"
        chmod +x "$HOME/.local/bin/ninja"
    fi
    
    # Clean up
    cd - > /dev/null
    rm -rf "$TMP_DIR"
    
    # Verify installation
    if command -v ninja &> /dev/null; then
        NINJA_VERSION_INSTALLED=$(ninja --version 2>/dev/null)
        echo -e "${GREEN}✓ Ninja v${NINJA_VERSION_INSTALLED} installed successfully${NC}"
    else
        echo -e "${RED}❌ Failed to install Ninja${NC}"
        exit 1
    fi
}

# Create CMake presets file
create_cmake_presets() {
    echo -e "${YELLOW}Creating CMake presets file...${NC}"
    
    PRESETS_FILE="CMakePresets.json"
    
    # Create presets file if it doesn't exist
    cat > "$PRESETS_FILE" << EOF
{
  "version": 3,
  "configurePresets": [
    {
      "name": "default",
      "displayName": "Default Config",
      "description": "Default build using Ninja generator",
      "generator": "Ninja",
      "binaryDir": "${BUILD_DIR}/default",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Release",
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON"
      }
    },
    {
      "name": "debug",
      "displayName": "Debug Build",
      "description": "Debug build with all checks enabled",
      "generator": "Ninja",
      "binaryDir": "${BUILD_DIR}/debug",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Debug",
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON",
        "DEBUG": "ON",
        "CODE_COVERAGE": "ON",
        "ENABLE_SANITIZERS": "ON"
      }
    },
    {
      "name": "release-with-debug",
      "displayName": "Release with Debug Info",
      "description": "Optimized build with debug information",
      "generator": "Ninja",
      "binaryDir": "${BUILD_DIR}/release-with-debug",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "RelWithDebInfo",
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON"
      }
    },
    {
      "name": "ci",
      "displayName": "CI Build",
      "description": "Configuration for CI environment",
      "generator": "Ninja",
      "binaryDir": "${BUILD_DIR}/ci",
      "cacheVariables": {
        "CMAKE_BUILD_TYPE": "Release",
        "BUILD_TESTS": "ON",
        "CMAKE_EXPORT_COMPILE_COMMANDS": "ON"
      }
    }
  ],
  "buildPresets": [
    {
      "name": "default",
      "configurePreset": "default",
      "jobs": ${NUM_JOBS}
    },
    {
      "name": "debug",
      "configurePreset": "debug",
      "jobs": ${NUM_JOBS}
    },
    {
      "name": "release-with-debug",
      "configurePreset": "release-with-debug",
      "jobs": ${NUM_JOBS}
    },
    {
      "name": "ci",
      "configurePreset": "ci",
      "jobs": ${NUM_JOBS}
    }
  ],
  "testPresets": [
    {
      "name": "default",
      "configurePreset": "default",
      "output": {"verbosity": "verbose"},
      "execution": {"noTestsAction": "error", "stopOnFailure": false}
    },
    {
      "name": "ci",
      "configurePreset": "ci",
      "output": {"verbosity": "verbose"},
      "execution": {"noTestsAction": "error", "stopOnFailure": true}
    }
  ]
}
EOF
    
    echo -e "${GREEN}✓ Created CMake presets file: $PRESETS_FILE${NC}"
}

# Set up CMake environment
setup_cmake_environment() {
    echo -e "${YELLOW}Setting up CMake environment...${NC}"
    
    # Create build directory
    mkdir -p "$BUILD_DIR"
    
    # Ensure CMake module directory exists
    mkdir -p "$CONFIG_DIR"
    
    # Create additional utility modules
    create_utility_modules
    
    echo -e "${GREEN}✓ CMake environment configured${NC}"
}

# Create additional utility CMake modules
create_utility_modules() {
    echo -e "${YELLOW}Creating utility CMake modules...${NC}"
    
    # Create project utilities module
    cat > "${CONFIG_DIR}/ProjectUtils.cmake" << 'EOF'
# Project utilities for Watsonx Code Assistant
include(CMakeParseArguments)

# Add a library with proper defaults and configuration
function(wx_add_library)
    cmake_parse_arguments(ARG
        "STATIC;SHARED;MODULE;INTERFACE;OBJECT;CUDA;EXCLUDE_FROM_ALL"
        "NAME"
        "SOURCES;PUBLIC_HEADERS;PRIVATE_HEADERS;PUBLIC_DEPS;PRIVATE_DEPS;INCLUDES"
        ${ARGN}
    )
    
    # Handle library type
    set(LIB_TYPE "")
    if(ARG_STATIC)
        set(LIB_TYPE "STATIC")
    elseif(ARG_SHARED)
        set(LIB_TYPE "SHARED")
    elseif(ARG_MODULE)
        set(LIB_TYPE "MODULE")
    elseif(ARG_INTERFACE)
        set(LIB_TYPE "INTERFACE")
    elseif(ARG_OBJECT)
        set(LIB_TYPE "OBJECT")
    endif()
    
    # Create library target
    add_library(${ARG_NAME} ${LIB_TYPE} ${ARG_SOURCES} ${ARG_PUBLIC_HEADERS} ${ARG_PRIVATE_HEADERS})
    
    # Add includes
    if(ARG_INCLUDES)
        target_include_directories(${ARG_NAME} 
            PUBLIC ${ARG_INCLUDES}
        )
    endif()
    
    # Add dependencies
    if(ARG_PUBLIC_DEPS)
        target_link_libraries(${ARG_NAME} 
            PUBLIC ${ARG_PUBLIC_DEPS}
        )
    endif()
    
    if(ARG_PRIVATE_DEPS)
        target_link_libraries(${ARG_NAME} 
            PRIVATE ${ARG_PRIVATE_DEPS}
        )
    endif()
    
    # If CUDA library, set appropriate properties
    if(ARG_CUDA)
        set_target_properties(${ARG_NAME} PROPERTIES
            CUDA_SEPARABLE_COMPILATION ON
        )
    endif()
    
    # Install rules
    if(NOT ARG_EXCLUDE_FROM_ALL)
        install(TARGETS ${ARG_NAME}
            EXPORT ${PROJECT_NAME}Targets
            LIBRARY DESTINATION lib
            ARCHIVE DESTINATION lib
            RUNTIME DESTINATION bin
            INCLUDES DESTINATION include
        )
        
        if(ARG_PUBLIC_HEADERS)
            install(FILES ${ARG_PUBLIC_HEADERS}
                DESTINATION include/${ARG_NAME}
            )
        endif()
    endif()
endfunction()

# Add an executable with proper defaults and configuration
function(wx_add_executable)
    cmake_parse_arguments(ARG
        "EXCLUDE_FROM_ALL;WIN32;MACOSX_BUNDLE;CUDA"
        "NAME"
        "SOURCES;DEPS;INCLUDES"
        ${ARGN}
    )
    
    # Create executable
    if(ARG_WIN32)
        add_executable(${ARG_NAME} WIN32 ${ARG_SOURCES})
    elseif(ARG_MACOSX_BUNDLE)
        add_executable(${ARG_NAME} MACOSX_BUNDLE ${ARG_SOURCES})
    else()
        add_executable(${ARG_NAME} ${ARG_SOURCES})
    endif()
    
    # Add includes
    if(ARG_INCLUDES)
        target_include_directories(${ARG_NAME} 
            PRIVATE ${ARG_INCLUDES}
        )
    endif()
    
    # Add dependencies
    if(ARG_DEPS)
        target_link_libraries(${ARG_NAME} 
            PRIVATE ${ARG_DEPS}
        )
    endif()
    
    # If CUDA executable, set appropriate properties
    if(ARG_CUDA)
        set_target_properties(${ARG_NAME} PROPERTIES
            CUDA_SEPARABLE_COMPILATION ON
        )
    endif()
    
    # Install rules
    if(NOT ARG_EXCLUDE_FROM_ALL)
        install(TARGETS ${ARG_NAME}
            RUNTIME DESTINATION bin
        )
    endif()
endfunction()

# Add a test with proper defaults
function(wx_add_test)
    cmake_parse_arguments(ARG
        ""
        "NAME;WORKING_DIRECTORY"
        "SOURCES;DEPS;INCLUDES;ARGS"
        ${ARGN}
    )
    
    # Create executable
    add_executable(${ARG_NAME} ${ARG_SOURCES})
    
    # Add includes
    if(ARG_INCLUDES)
        target_include_directories(${ARG_NAME} 
            PRIVATE ${ARG_INCLUDES}
        )
    endif()
    
    # Add dependencies
    if(ARG_DEPS)
        target_link_libraries(${ARG_NAME} 
            PRIVATE ${ARG_DEPS}
        )
    endif()
    
    # Add test
    add_test(NAME ${ARG_NAME} 
        COMMAND ${ARG_NAME} ${ARG_ARGS}
        WORKING_DIRECTORY ${ARG_WORKING_DIRECTORY}
    )
    
    # Set test properties
    set_tests_properties(${ARG_NAME} PROPERTIES
        TIMEOUT 300
    )
endfunction()
EOF
    
    echo -e "${GREEN}✓ CMake utility modules created${NC}"
}

# Generate the project using CMake
generate_cmake_project() {
    echo -e "${YELLOW}Configuring CMake project...${NC}"
    
    # Choose preset based on build type
    PRESET="default"
    if [[ "$BUILD_TYPE" == "Debug" ]]; then
        PRESET="debug"
    elif [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]; then
        PRESET="release-with-debug"
    fi
    
    # Configure the project
    cmake --preset "$PRESET"
    
    echo -e "${GREEN}✓ CMake project configured successfully${NC}"
}

# Build the project using CMake
build_cmake_project() {
    echo -e "${YELLOW}Building project with CMake...${NC}"
    
    # Choose preset based on build type
    PRESET="default"
    if [[ "$BUILD_TYPE" == "Debug" ]]; then
        PRESET="debug"
    elif [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]; then
        PRESET="release-with-debug"
    fi
    
    # Build the project
    cmake --build --preset "$PRESET" -j "$NUM_JOBS"
    
    echo -e "${GREEN}✓ Project built successfully${NC}"
}

# Install the built project
install_project() {
    echo -e "${YELLOW}Installing project...${NC}"
    
    # Choose preset based on build type
    PRESET="default"
    if [[ "$BUILD_TYPE" == "Debug" ]]; then
        PRESET="debug"
    elif [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]; then
        PRESET="release-with-debug"
    fi
    
    # Set install prefix if provided
    INSTALL_ARGS=""
    if [[ -n "$INSTALL_PREFIX" ]]; then
        INSTALL_ARGS="--prefix $INSTALL_PREFIX"
    fi
    
    # Install the project
    cmake --install "${BUILD_DIR}/${PRESET}" $INSTALL_ARGS
    
    echo -e "${GREEN}✓ Project installed successfully${NC}"
}

# Main function
main() {
    # Check prerequisites
    check_prerequisites
    
    # Install CMake if needed
    install_cmake
    
    # Install Ninja if needed
    install_ninja
    
    # Set up CMake environment
    setup_cmake_environment
    
    # Create CMake presets file
    create_cmake_presets
    
    # Generate the project
    generate_cmake_project
    
    # Build the project
    build_cmake_project
    
    # Install if requested
    if [[ -n "$INSTALL_PREFIX" ]]; then
        install_project
    fi
    
    # Show completion message
    echo -e "\n${GREEN}${BOLD}CMake deployment completed successfully!${NC}"
    echo -e "${BLUE}You can now build the project with:${NC}"
    echo -e "  ${YELLOW}cmake --build --preset default${NC}"
    echo -e "\n${BLUE}Or run tests with:${NC}"
    echo -e "  ${YELLOW}ctest --preset default${NC}"
    echo -e "\n${BLUE}Available presets:${NC}"
    echo -e "  - default: Standard optimized build"
    echo -e "  - debug: Debug build with all checks enabled"
    echo -e "  - release-with-debug: Optimized build with debug symbols"
    echo -e "  - ci: Configuration for continuous integration"
}

# Run main function
main "$@"

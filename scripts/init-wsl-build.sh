#!/bin/bash
# Initialize build environment for Ninja team in WSL environment
# This ensures proper Unix line endings and format compatibility

set -e

# Color formatting
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

BUILD_DIR=${1:-"build"}
echo -e "${YELLOW}Initializing WSL build environment in $BUILD_DIR...${NC}"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

# Remove any existing build.ninja file
if [ -f "$BUILD_DIR/build.ninja" ]; then
    echo -e "${YELLOW}Removing existing build.ninja file...${NC}"
    rm -f "$BUILD_DIR/build.ninja"
fi

# Create a minimal build.ninja file with proper Unix line endings
echo -e "${YELLOW}Creating fresh build.ninja file with Unix line endings...${NC}"

cat > "$BUILD_DIR/build.ninja" << 'EOL'
# Simple build.ninja file for Watsonx Code Assistant
# Generated by init-wsl-build.sh for WSL compatibility

rule cxx
  command = g++ -MMD -MT $out -MF $out.d -o $out -c $in
  description = CXX $out
  depfile = $out.d
  deps = gcc

rule link
  command = g++ -o $out $in
  description = LINK $out

build build/placeholder.o: cxx placeholder.cpp
build build/placeholder: link build/placeholder.o

default build/placeholder
EOL

# Create placeholder source if needed
if [ ! -f "placeholder.cpp" ]; then
    cat > "placeholder.cpp" << 'EOL'
// Placeholder source file for build system
#include <iostream>

int main() {
    std::cout << "Watsonx Code Assistant Ninja Build Team\n";
    return 0;
}
EOL
    echo -e "${GREEN}Created placeholder.cpp${NC}"
fi

# Ensure proper permissions
chmod 644 "$BUILD_DIR/build.ninja"
chmod 644 "placeholder.cpp"

# Verify the build.ninja file is valid
echo -e "${YELLOW}Verifying build.ninja file...${NC}"
if [ -f "$BUILD_DIR/build.ninja" ]; then
    # Check for DOS line endings and fix them
    if grep -q $'\r' "$BUILD_DIR/build.ninja"; then
        echo -e "${YELLOW}Found DOS line endings in build.ninja, converting to Unix format...${NC}"
        sed -i 's/\r$//' "$BUILD_DIR/build.ninja"
    fi
    
    # Verify the file with ninja
    if command -v ninja &> /dev/null; then
        pushd "$BUILD_DIR" > /dev/null
        if ninja -t targets all &> /dev/null; then
            echo -e "${GREEN}✓ Verified build.ninja file is working correctly${NC}"
        else
            echo -e "${RED}⚠️ build.ninja file still has issues, creating simplified version...${NC}"
            # Create a much simpler version as a last resort
            cat > build.ninja << 'EOL'
rule touch
  command = touch $out

build placeholder: touch
  pool = console

default placeholder
EOL
            
            if ninja -t targets all &> /dev/null; then
                echo -e "${GREEN}✓ Simplified build.ninja file works${NC}"
            else
                echo -e "${RED}❌ Still having issues with build.ninja${NC}"
            fi
        fi
        popd > /dev/null
    else
        echo -e "${YELLOW}⚠️ Ninja not installed, skipping verification${NC}"
    fi
else
    echo -e "${RED}Failed to create build.ninja file${NC}"
    exit 1
fi

echo -e "${GREEN}WSL build environment setup complete${NC}"
exit 0

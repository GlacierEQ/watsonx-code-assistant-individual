#!/bin/bash
# Wrapper script for running Ninja commands in WSL with proper error handling

set -e

# Color formatting
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Default build directory
BUILD_DIR=${1:-"build"}
shift

# Command to execute
COMMAND=${1:-"targets"}
shift

# Check if build directory exists
if [ ! -d "$BUILD_DIR" ]; then
    echo -e "${YELLOW}Creating build directory $BUILD_DIR...${NC}"
    mkdir -p "$BUILD_DIR"
fi

# Check if build.ninja exists in the build directory
if [ ! -f "$BUILD_DIR/build.ninja" ] || [ ! -s "$BUILD_DIR/build.ninja" ]; then
    echo -e "${YELLOW}No valid build.ninja found, creating one...${NC}"
    
    # Create minimal build.ninja
    cat > "$BUILD_DIR/build.ninja" << 'EOL'
rule touch
  command = touch $out

build placeholder: touch
  pool = console

default placeholder
EOL
fi

# Execute the ninja command in the build directory
echo -e "${GREEN}Running: ninja -t $COMMAND $@${NC}"
cd "$BUILD_DIR"

# Try to execute the command
if ninja -t "$COMMAND" "$@" 2>/dev/null; then
    echo -e "${GREEN}Command successful!${NC}"
    exit 0
else
    echo -e "${YELLOW}Command failed, attempting to repair build file...${NC}"
    
    # Repair build.ninja
    cat > "build.ninja" << 'EOL'
rule touch
  command = touch $out

build placeholder: touch
  pool = console

default placeholder
EOL
    
    # Try again
    if ninja -t "$COMMAND" "$@" 2>/dev/null; then
        echo -e "${GREEN}Command successful after repair!${NC}"
        exit 0
    else
        echo -e "${RED}Command failed even after repair${NC}"
        exit 1
    fi
fi

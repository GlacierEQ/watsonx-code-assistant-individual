#!/bin/bash
# WSL Tools Installer for Ninja Team

# Color formatting
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Installing necessary tools for Ninja Team in WSL...${NC}"

# Update package list
echo -e "${YELLOW}Updating package list...${NC}"
sudo apt-get update

# Install essential build tools
echo -e "${YELLOW}Installing build essentials...${NC}"
sudo apt-get install -y build-essential python3 python3-pip ninja-build

# Install additional tools
echo -e "${YELLOW}Installing additional tools...${NC}"
sudo apt-get install -y ccache rsync curl

# Install Python packages
echo -e "${YELLOW}Installing Python packages...${NC}"
pip3 install --user psutil colorama

# Verify installation
echo -e "${YELLOW}Verifying installation...${NC}"

TOOLS=(gcc g++ python3 ninja ccache rsync curl)
for tool in "${TOOLS[@]}"; do
    if command -v $tool &> /dev/null; then
        echo -e "${GREEN}✓ $tool installed: $($tool --version | head -n1)${NC}"
    else
        echo -e "${RED}✗ $tool not installed${NC}"
    fi
done

echo -e "${GREEN}WSL tools installation complete!${NC}"

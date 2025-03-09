#!/bin/bash

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BLUE}${BOLD}========================================================${NC}"
echo -e "${BLUE}${BOLD}           NINJA BUILD TEAM DEPLOYMENT SYSTEM           ${NC}"
echo -e "${BLUE}${BOLD}                    [Unix/Linux]                        ${NC}"
echo -e "${BLUE}${BOLD}========================================================${NC}"
echo

# Check for required dependencies
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}[ERROR] Python 3 not found. Please install Python 3.x and try again.${NC}"
    exit 1
fi

if ! command -v ninja &> /dev/null; then
    echo -e "${YELLOW}[WARNING] Ninja not found in PATH. Will try to install via pip...${NC}"
    python3 -m pip install ninja
fi

# Create default hosts file if it doesn't exist
if [ ! -f ninja-hosts.txt ]; then
    echo -e "${YELLOW}[INFO] Creating default ninja-hosts.txt file...${NC}"
    echo "localhost 8374" > ninja-hosts.txt
    echo "# Add more hosts below as needed - one per line" >> ninja-hosts.txt
    echo "# hostname1 8374" >> ninja-hosts.txt
    echo "# hostname2 8374" >> ninja-hosts.txt
fi

# Check if we're asked to deploy using Bash script
if [ "$1" == "--full" ]; then
    echo -e "${YELLOW}[INFO] Deploying full ninja team with Bash deployment system...${NC}"
    chmod +x ./scripts/deploy-ninja-team.sh
    ./scripts/deploy-ninja-team.sh "${@:2}"
else
    # Deploy the ninjas!
    echo -e "${YELLOW}[INFO] Deploying ninja build team...${NC}"
    python3 scripts/ninja-team.py --mode recursive --hosts ninja-hosts.txt --recursive-depth 3 --config scripts/ninja-team-config.json "$@"
fi

# Check deployment result
if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}${BOLD}===============================================${NC}"
    echo -e "${GREEN}${BOLD}        NINJA DEPLOYMENT SUCCESSFUL!          ${NC}"
    echo -e "${GREEN}${BOLD}===============================================${NC}"
else
    echo -e "${RED}[ERROR] Ninja deployment failed!${NC}"
fi

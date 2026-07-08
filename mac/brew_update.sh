#!/bin/zsh

clear

# Color codes for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "${BLUE}=== Starting Homebrew Update ===${NC}\n"

# Verify if brew is installed
if ! command -v brew &> /dev/null; then
    echo "${RED}Error: Homebrew is not installed on this system.${NC}"
    echo "To install it, visit: https://brew.sh/"
    exit 1
fi

# 1. brew update
echo "${BLUE}[1/4] Updating Homebrew repositories (brew update)...${NC}"
if brew update; then
    echo "${GREEN}Repositories updated successfully.${NC}\n"
else
    echo "${RED}Warning: A problem occurred while running 'brew update'.${NC}\n"
fi

# 2. brew outdated
echo "${BLUE}[2/4] Checking outdated formulae and casks (brew outdated)...${NC}"
if brew outdated; then
    echo "${GREEN}Outdated packages listed successfully.${NC}\n"
else
    echo "${YELLOW}No outdated packages found, or 'brew outdated' returned a non-zero exit code.${NC}\n"
fi

# 3. brew upgrade
echo "${BLUE}[3/4] Upgrading outdated formulae and casks (brew upgrade)...${NC}"
if brew upgrade; then
    echo "${GREEN}All formulae and casks upgraded successfully.${NC}\n"
else
    echo "${RED}Warning: A problem occurred while running 'brew upgrade'.${NC}\n"
fi

# 4. brew cleanup
echo "${BLUE}[4/4] Cleaning up temporary files and old versions (brew cleanup)...${NC}"
if brew cleanup; then
    echo "${GREEN}Cleanup completed successfully.${NC}\n"
else
    echo "${RED}Warning: A problem occurred while running 'brew cleanup'.${NC}\n"
fi

echo "${GREEN}=== Homebrew Update Completed Successfully ===${NC}"

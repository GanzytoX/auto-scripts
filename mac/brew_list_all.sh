#!/bin/zsh

clear

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "${BLUE}=== Homebrew Inventory ===${NC}"

if ! command -v brew &> /dev/null; then
    echo "${RED}Error: Homebrew is not installed on this system.${NC}"
    echo "To install it, visit: https://brew.sh/"
    exit 1
fi

echo "${BLUE}Homebrew prefix:${NC} $(brew --prefix)"
echo "${BLUE}Homebrew version:${NC} $(brew --version | head -n 1)"

echo ""
echo "${BLUE}[1/4] Installed formulae${NC}"
FORMULAE_LIST=$(brew list --formula 2>/dev/null)
if [ -n "$FORMULAE_LIST" ]; then
    echo "$FORMULAE_LIST" | sort
    echo "${GREEN}Total formulae: $(echo "$FORMULAE_LIST" | wc -l | tr -d ' ')${NC}"
else
    echo "${YELLOW}No formulae installed.${NC}"
fi

echo ""
echo "${BLUE}[2/4] Installed casks${NC}"
CASKS_LIST=$(brew list --cask 2>/dev/null)
if [ -n "$CASKS_LIST" ]; then
    echo "$CASKS_LIST" | sort
    echo "${GREEN}Total casks: $(echo "$CASKS_LIST" | wc -l | tr -d ' ')${NC}"
else
    echo "${YELLOW}No casks installed.${NC}"
fi

echo ""
echo "${BLUE}[3/4] Tapped repositories${NC}"
TAPS_LIST=$(brew tap 2>/dev/null)
if [ -n "$TAPS_LIST" ]; then
    echo "$TAPS_LIST" | sort
    echo "${GREEN}Total taps: $(echo "$TAPS_LIST" | wc -l | tr -d ' ')${NC}"
else
    echo "${YELLOW}No additional taps configured.${NC}"
fi

echo ""
echo "${BLUE}[4/4] Homebrew services${NC}"
if brew services list &> /dev/null; then
    brew services list
else
    echo "${YELLOW}No Homebrew services information available.${NC}"
fi

echo ""
echo "${GREEN}Inventory complete.${NC}"
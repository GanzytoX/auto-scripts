#!/bin/zsh

# Color codes for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "${BLUE}Checking pnpm status...${NC}"

# Check if pnpm is installed
if ! command -v pnpm &> /dev/null; then
    echo "${RED}Error: pnpm is not installed on this system.${NC}"
    echo "To install pnpm, you can run: curl -fsSL https://get.pnpm.io/install.sh | sh -"
    exit 1
fi

CURRENT_VERSION=$(pnpm -v)
# Fetch latest version from registry using curl and extract version
LATEST_VERSION=$(curl -s https://registry.npmjs.org/pnpm/latest | grep -o '"version"\s*:\s*"[^"]*' | grep -o '[0-9][^"]*')

if [ -z "$LATEST_VERSION" ]; then
    echo "${RED}Error: Could not retrieve the latest pnpm version from the registry. Please check your internet connection.${NC}"
    exit 1
fi

echo "Current pnpm version: ${BLUE}$CURRENT_VERSION${NC}"
echo "Latest pnpm version:  ${GREEN}$LATEST_VERSION${NC}"

autoload -Ur is-at-least
if is-at-least "$LATEST_VERSION" "$CURRENT_VERSION"; then
    NEEDS_UPDATE=0
else
    NEEDS_UPDATE=1
fi

if [ $NEEDS_UPDATE -eq 1 ]; then
    echo "${YELLOW}A newer version of pnpm is available. Updating...${NC}"

    # 1. Check if pnpm is managed by Homebrew
    if command -v brew &> /dev/null && brew list pnpm &> /dev/null; then
        echo "${BLUE}Homebrew detected managing pnpm. Updating via Homebrew...${NC}"
        if brew upgrade pnpm; then
            NEW_VERSION=$(pnpm -v)
            if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
                echo "${GREEN}Success: pnpm has been updated to $NEW_VERSION!${NC}"
                exit 0
            fi
        fi
        echo "${RED}Homebrew upgrade did not result in a new version. Trying alternative methods...${NC}"
    fi

    # 2. Try pnpm self-update
    echo "${BLUE}Attempting update via 'pnpm self-update'...${NC}"
    if pnpm self-update; then
        NEW_VERSION=$(pnpm -v)
        if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
            echo "${GREEN}Success: pnpm has been updated to $NEW_VERSION!${NC}"
            exit 0
        else
            echo "${RED}'pnpm self-update' did not result in a new version. Trying alternative methods...${NC}"
        fi
    fi

    # 3. Try global npm install if npm is available
    if command -v npm &> /dev/null; then
        echo "${BLUE}Attempting update via 'npm install -g pnpm'...${NC}"
        if npm install -g pnpm; then
            NEW_VERSION=$(pnpm -v)
            if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
                echo "${GREEN}Success: pnpm has been updated to $NEW_VERSION!${NC}"
                exit 0
            fi
        fi
        
        echo "${RED}npm global install did not result in a new version. Trying with sudo...${NC}"
        if sudo npm install -g pnpm; then
            NEW_VERSION=$(pnpm -v)
            if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
                echo "${GREEN}Success: pnpm has been updated to $NEW_VERSION!${NC}"
                exit 0
            fi
        fi
    fi

    # 4. Fallback to install.sh script
    echo "${BLUE}Attempting update via official installation script...${NC}"
    if curl -fsSL https://get.pnpm.io/install.sh | sh -; then
        NEW_VERSION=$(pnpm -v)
        echo "${GREEN}Success: pnpm update script executed! (Current version: $NEW_VERSION). Please restart your terminal or run 'source ~/.zshrc' to apply.${NC}"
        exit 0
    fi

    echo "${RED}Failed to update pnpm automatically. Please check your setup permissions or install manually.${NC}"
    exit 1
else
    echo "${GREEN}pnpm is already up to date!${NC}"
fi

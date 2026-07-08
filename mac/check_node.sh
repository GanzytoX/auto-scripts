#!/bin/zsh

clear

# Color codes for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "${BLUE}Checking Node.js status...${NC}"

# Check if node is installed
if ! command -v node &> /dev/null; then
    echo "${RED}Error: Node.js is not installed on this system.${NC}"
    echo "Please download it from https://nodejs.org/ or use a manager like Homebrew, fnm, or nvm."
    exit 1
fi

CURRENT_VERSION=$(node -v)
echo "Current Node.js version: ${BLUE}$CURRENT_VERSION${NC}"

# Fetch Node.js release index
echo "${BLUE}Fetching available Node.js versions from nodejs.org...${NC}"
RELEASES_JSON=$(curl -s https://nodejs.org/dist/index.json)

if [ -z "$RELEASES_JSON" ] || [ "$RELEASES_JSON" = "null" ]; then
    echo "${RED}Error: Could not fetch releases from nodejs.org. Please check your internet connection.${NC}"
    exit 1
fi
# Detect version manager
MANAGER_CMD=""
if [[ "$(which node 2>/dev/null)" == *"/pnpm/"* ]]; then
    MANAGER_CMD="pnpm"
elif command -v fnm &> /dev/null; then
    MANAGER_CMD="fnm"
elif command -v nvm &> /dev/null; then
    MANAGER_CMD="nvm"
elif command -v n &> /dev/null; then
    MANAGER_CMD="n"
elif command -v brew &> /dev/null && (brew list node &> /dev/null || brew list | grep -E '^node(@[0-9]+)?$' &> /dev/null); then
    MANAGER_CMD="brew"
fi

# Parse and process releases using Node.js
echo "$RELEASES_JSON" | node -e "
const fs = require('fs');
const releases = JSON.parse(fs.readFileSync(0, 'utf-8'));
const currentVersion = '$CURRENT_VERSION';
const manager = '$MANAGER_CMD';

// Extract latest Current and latest LTS
const latestCurrent = releases[0];
const latestLTS = releases.find(r => r.lts);

console.log('\n\x1b[32mAvailable Node.js Releases:\x1b[0m');
console.log('-------------------------------------------');
console.log('Latest LTS (Recommended):  \x1b[32m' + latestLTS.version + ' (' + latestLTS.lts + ')\x1b[0m');
console.log('Latest Current (Features): \x1b[33m' + latestCurrent.version + '\x1b[0m');
console.log('-------------------------------------------');

// Group by major version to show the latest for each recent major
const majorMap = new Map();
for (const r of releases) {
  const major = r.version.split('.')[0];
  if (!majorMap.has(major)) {
    majorMap.set(major, r);
  }
  if (majorMap.size >= 8) break; // limit to 8 recent major versions
}

console.log('\n\x1b[34mRecent Major Release Lines:\x1b[0m');
for (const [major, r] of majorMap.entries()) {
  const label = r.lts ? 'LTS (' + r.lts + ')' : 'Current';
  const isInstalled = currentVersion.startsWith(major + '.') ? ' \x1b[33m(current installed major)\x1b[0m' : '';
  console.log('  - ' + r.version + ' [' + label + ']' + isInstalled);
}

console.log('\n\x1b[34mHow to upgrade/install on your system:\x1b[0m');
if (manager === 'pnpm') {
    console.log('  Detected Node is managed via \x1b[32mpnpm runtime\x1b[0m. You can install/upgrade by running:');
    console.log('  \x1b[33mpnpm runtime set node ' + latestLTS.version.substring(1) + ' -g\x1b[0m (for LTS) or');
    console.log('  \x1b[33mpnpm runtime set node ' + latestCurrent.version.substring(1) + ' -g\x1b[0m (for Current)');
} else if (manager === 'fnm') {
  console.log('  Detected you use \x1b[32mfnm\x1b[0m. You can install/upgrade by running:');
  console.log('  \x1b[33mfnm install ' + latestLTS.version.substring(1) + '\x1b[0m (for LTS) or');
  console.log('  \x1b[33mfnm install ' + latestCurrent.version.substring(1) + '\x1b[0m (for Current)');
} else if (manager === 'nvm') {
  console.log('  Detected you use \x1b[32mnvm\x1b[0m. You can install/upgrade by running:');
  console.log('  \x1b[33mnvm install --lts\x1b[0m (for LTS) or');
  console.log('  \x1b[33mnvm install node\x1b[0m (for Current)');
} else if (manager === 'n') {
  console.log('  Detected you use \x1b[32mn\x1b[0m. You can install/upgrade by running:');
  console.log('  \x1b[33mn lts\x1b[0m (for LTS) or');
  console.log('  \x1b[33mn latest\x1b[0m (for Current)');
} else if (manager === 'brew') {
  console.log('  Detected Node is managed via \x1b[32mHomebrew\x1b[0m.');
  console.log('  To keep your current major version, you can upgrade with: \x1b[33mbrew upgrade node@<major>\x1b[0m');
  console.log('  To upgrade to the latest major version, run: \x1b[33mbrew upgrade node\x1b[0m');
} else {
  console.log('  No specific version manager (pnpm, fnm, nvm, n, brew) detected.');
  console.log('  You can download the installer from: \x1b[33mhttps://nodejs.org/en/download/\x1b[0m');
}
"

# 4. Check for update in the same major version and execute it
CURRENT_MAJOR=$(echo "$CURRENT_VERSION" | sed 's/^v//' | cut -d. -f1)
LATEST_SAME_MAJOR=$(echo "$RELEASES_JSON" | node -e "
  const fs = require('fs');
  const releases = JSON.parse(fs.readFileSync(0, 'utf-8'));
  const currentMajor = '$CURRENT_MAJOR';
  const match = releases.find(r => r.version.startsWith('v' + currentMajor) || r.version.startsWith(currentMajor));
  console.log(match ? match.version : '');
")

if [ -n "$LATEST_SAME_MAJOR" ]; then
    LATEST_VERSION_CLEAN=$(echo "$LATEST_SAME_MAJOR" | sed 's/^v//')
    CURRENT_VERSION_CLEAN=$(echo "$CURRENT_VERSION" | sed 's/^v//')

    autoload -Ur is-at-least
    if is-at-least "$LATEST_VERSION_CLEAN" "$CURRENT_VERSION_CLEAN"; then
        echo "\n${GREEN}Node.js v$CURRENT_MAJOR is already up to date! (Current version: $CURRENT_VERSION)${NC}"
    else
        echo "\n${YELLOW}A newer version of Node.js v$CURRENT_MAJOR is available: $LATEST_SAME_MAJOR (Current: $CURRENT_VERSION)${NC}"
        echo "${BLUE}Attempting to update...${NC}"

        if [ "$MANAGER_CMD" = "pnpm" ]; then
            echo "${BLUE}Updating via 'pnpm runtime set node $LATEST_VERSION_CLEAN -g'...${NC}"
            if pnpm runtime set node "$LATEST_VERSION_CLEAN" -g; then
                echo "${GREEN}Success: Node.js has been updated to $LATEST_SAME_MAJOR via pnpm!${NC}"
            else
                echo "${RED}Failed to update Node.js via pnpm runtime.${NC}"
            fi
        elif [ "$MANAGER_CMD" = "fnm" ]; then
            echo "${BLUE}Updating via fnm...${NC}"
            if fnm install "$LATEST_VERSION_CLEAN" && fnm default "$LATEST_VERSION_CLEAN"; then
                echo "${GREEN}Success: Node.js has been updated to $LATEST_SAME_MAJOR via fnm!${NC}"
                echo "Please restart your terminal or run 'fnm use $LATEST_VERSION_CLEAN' to apply."
            else
                echo "${RED}Failed to update Node.js via fnm.${NC}"
            fi
        elif [ "$MANAGER_CMD" = "nvm" ]; then
            echo "${BLUE}Updating via nvm...${NC}"
            export NVM_DIR="$HOME/.nvm"
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
            if command -v nvm &> /dev/null; then
                if nvm install "$LATEST_VERSION_CLEAN" && nvm alias default "$LATEST_VERSION_CLEAN"; then
                    echo "${GREEN}Success: Node.js has been updated to $LATEST_SAME_MAJOR via nvm!${NC}"
                    echo "Please restart your terminal or run 'nvm use $LATEST_VERSION_CLEAN' to apply."
                else
                    echo "${RED}Failed to update Node.js via nvm.${NC}"
                fi
            else
                echo "${RED}Could not load nvm automatically. Please run: nvm install $LATEST_VERSION_CLEAN && nvm alias default $LATEST_VERSION_CLEAN${NC}"
            fi
        elif [ "$MANAGER_CMD" = "n" ]; then
            echo "${BLUE}Updating via n...${NC}"
            if n "$LATEST_VERSION_CLEAN"; then
                echo "${GREEN}Success: Node.js has been updated to $LATEST_SAME_MAJOR via n!${NC}"
            else
                echo "${RED}Failed to update Node.js via n (try running the script with sudo).${NC}"
            fi
        elif [ "$MANAGER_CMD" = "brew" ]; then
            if brew list "node@$CURRENT_MAJOR" &> /dev/null; then
                echo "${BLUE}Updating node@$CURRENT_MAJOR via Homebrew...${NC}"
                if brew upgrade "node@$CURRENT_MAJOR"; then
                    echo "${GREEN}Success: node@$CURRENT_MAJOR updated via Homebrew!${NC}"
                else
                    echo "${RED}Failed to upgrade node@$CURRENT_MAJOR via Homebrew.${NC}"
                fi
            else
                echo "${RED}Node.js is managed via Homebrew but node@$CURRENT_MAJOR formula is not detected. We will not run 'brew upgrade node' to avoid upgrading to a newer major version (like v26). Please install 'node@$CURRENT_MAJOR' manually.${NC}"
            fi
        else
            echo "${RED}No supported version manager detected to update Node.js automatically.${NC}"
            echo "Please download and install Node.js $LATEST_SAME_MAJOR manually from: https://nodejs.org/"
        fi
    fi
else
    echo "\n${RED}Error: Could not determine the latest version for Node.js v$CURRENT_MAJOR.${NC}"
fi


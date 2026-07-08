#!/bin/zsh

clear

# Color codes for pretty output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "${BLUE}=== Python Inventory and Update Check ===${NC}\n"

if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
    echo "${RED}Error: Python is not installed on this system.${NC}"
    echo "Install it from https://www.python.org/downloads/ or with a manager like Homebrew, pyenv, or asdf."
    exit 1
fi

PYTHON_BIN="$(command -v python3 2>/dev/null || command -v python 2>/dev/null)"
CURRENT_VERSION_RAW="$($PYTHON_BIN --version 2>&1)"
CURRENT_VERSION="$(echo "$CURRENT_VERSION_RAW" | awk '{print $2}')"
CURRENT_MINOR="$(echo "$CURRENT_VERSION" | cut -d. -f1,2)"
CURRENT_EXECUTABLE="$($PYTHON_BIN -c 'import sys; print(sys.executable)')"

echo "${BLUE}Current Python:${NC} $CURRENT_VERSION"
echo "${BLUE}Python executable:${NC} $CURRENT_EXECUTABLE"

echo "${BLUE}Fetching Python release data from python.org...${NC}"
RELEASES_JSON="$(curl -fsSL 'https://www.python.org/api/v2/downloads/release/?is_published=true&show_on_download_page=true&order_by=-release_date')"

if [ -z "$RELEASES_JSON" ]; then
    echo "${RED}Error: Could not fetch Python releases from python.org.${NC}"
    exit 1
fi

LATEST_SAME_MINOR="$(printf '%s' "$RELEASES_JSON" | CURRENT_MINOR="$CURRENT_MINOR" python3 -c '
import json
import os
import re
import sys


def version_key(version):
    return tuple(int(part) for part in version.split("."))


current_minor = os.environ["CURRENT_MINOR"]
releases = json.load(sys.stdin)
matches = []

for item in releases:
    if item.get("pre_release"):
        continue
    name = item.get("name", "")
    if not name.startswith(f"Python {current_minor}."):
        continue
    match = re.match(r"Python (\d+\.\d+\.\d+)$", name)
    if match:
        matches.append(match.group(1))

if matches:
    print(max(matches, key=version_key))
')"

INSTALLED_VERSIONS_RAW="$(
    {
        echo "$CURRENT_VERSION"

        if command -v pyenv &> /dev/null; then
            pyenv versions --bare 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
        fi

        if command -v asdf &> /dev/null; then
            asdf list python 2>/dev/null | sed -E 's/^[*[:space:]]+//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
        fi

        if command -v brew &> /dev/null; then
            brew list --versions 2>/dev/null | awk '/^python(@[0-9]+\.[0-9]+)? / { for (i = 2; i <= NF; i++) print $i }'
        fi
    } | python3 -c '
import re
import sys


def version_key(version):
    return tuple(int(part) for part in version.split("."))


versions = []
for line in sys.stdin:
    version = line.strip()
    if re.fullmatch(r"\d+\.\d+\.\d+", version):
        versions.append(version)

for version in sorted(set(versions), key=version_key):
    print(version)
')"

echo ""
echo "${BLUE}Installed versions detected:${NC}"
if [ -n "$INSTALLED_VERSIONS_RAW" ]; then
    echo "$INSTALLED_VERSIONS_RAW" | sed 's/^/  - /'
else
    echo "  - No additional installed versions were detected."
fi

echo ""
echo "${BLUE}Latest patch release for ${CURRENT_MINOR}:${NC}"
if [ -n "$LATEST_SAME_MINOR" ]; then
    echo "  - ${LATEST_SAME_MINOR}"
else
    echo "  - No release found for ${CURRENT_MINOR}."
fi

if [ -n "$LATEST_SAME_MINOR" ] && [ "$LATEST_SAME_MINOR" != "$CURRENT_VERSION" ]; then
    echo ""
    echo "${YELLOW}A newer patch release is available for ${CURRENT_MINOR}:${NC} ${CURRENT_VERSION} -> ${LATEST_SAME_MINOR}"
    printf "${BLUE}Do you want to update now? [y/N] ${NC}"
    read -r UPDATE_ANSWER

    case "$UPDATE_ANSWER" in
        [yY]|[yY][eE][sS])
            if command -v pyenv &> /dev/null && pyenv versions --bare 2>/dev/null | grep -qx "$CURRENT_VERSION"; then
                echo "${BLUE}Updating via pyenv...${NC}"
                if pyenv install -s "$LATEST_SAME_MINOR"; then
                    echo "${GREEN}Success: $LATEST_SAME_MINOR has been installed with pyenv.${NC}"
                    echo "${YELLOW}If you want to use it now, run:${NC} pyenv global $LATEST_SAME_MINOR"
                else
                    echo "${RED}Failed to install $LATEST_SAME_MINOR via pyenv.${NC}"
                fi
            elif command -v brew &> /dev/null && brew list --formula 2>/dev/null | grep -qx "python@${CURRENT_MINOR}"; then
                echo "${BLUE}Updating via Homebrew...${NC}"
                if brew upgrade "python@${CURRENT_MINOR}"; then
                    echo "${GREEN}Success: python@${CURRENT_MINOR} has been upgraded via Homebrew.${NC}"
                else
                    echo "${RED}Failed to upgrade python@${CURRENT_MINOR} via Homebrew.${NC}"
                fi
            elif command -v asdf &> /dev/null; then
                echo "${BLUE}Updating via asdf...${NC}"
                if asdf install python "$LATEST_SAME_MINOR"; then
                    echo "${GREEN}Success: $LATEST_SAME_MINOR has been installed with asdf.${NC}"
                    echo "${YELLOW}If you want to use it now, run:${NC} asdf global python $LATEST_SAME_MINOR"
                else
                    echo "${RED}Failed to install $LATEST_SAME_MINOR via asdf.${NC}"
                fi
            else
                echo "${YELLOW}I could not detect a supported manager to update Python automatically.${NC}"
                echo "${BLUE}Install the new version manually from:${NC} https://www.python.org/downloads/"
            fi
        ;;
        *)
            echo "${GREEN}No changes were made.${NC}"
        ;;
    esac
else
    echo ""
    echo "${GREEN}Python ${CURRENT_VERSION} is already up to date for the ${CURRENT_MINOR} line.${NC}"
fi

echo ""
echo "${GREEN}Check complete.${NC}"
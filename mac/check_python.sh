#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

AUTO_YES=0
UPDATE_REQUESTED=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--update] [--yes]"
    print -r -- "  --update  Offer to install the latest patch in the active minor line."
    print -r -- "  --yes     Confirm the update non-interactively (requires --update)."
}

while (( $# > 0 )); do
    case "$1" in
        -u|--update) UPDATE_REQUESTED=1 ;;
        -y|--yes) AUTO_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if (( AUTO_YES && ! UPDATE_REQUESTED )); then
    print_error "--yes can only be used together with --update."
    exit 2
fi

clear_screen
print_info "=== Python Inventory and Update Check ==="

if command_exists python3; then
    PYTHON_BIN="$(command -v python3)"
elif command_exists python; then
    PYTHON_BIN="$(command -v python)"
else
    print_error "Error: Python is not installed on this system."
    print -r -- "Install it from https://www.python.org/downloads/ or with a version manager."
    exit 1
fi

CURRENT_VERSION_RAW="$($PYTHON_BIN --version 2>&1)" || {
    print_error "The Python executable exists but could not report its version."
    exit 1
}
CURRENT_VERSION="${CURRENT_VERSION_RAW#Python }"
if ! is_valid_version "$CURRENT_VERSION"; then
    print_error "Unexpected Python version: $CURRENT_VERSION_RAW"
    exit 1
fi

CURRENT_MINOR="${CURRENT_VERSION%.*}"
CURRENT_EXECUTABLE="$($PYTHON_BIN -c 'import sys; print(sys.executable)')" || exit 1
CURRENT_EXECUTABLE_REAL="${CURRENT_EXECUTABLE:A}"

MANAGER="unknown"
BREW_FORMULA=""
PYENV_BASE="${PYENV_ROOT:-$HOME/.pyenv}"
ASDF_BASE="${ASDF_DATA_DIR:-$HOME/.asdf}"

if [[ "$CURRENT_EXECUTABLE_REAL" == "${PYENV_BASE:A}"/* ]]; then
    MANAGER="pyenv"
elif [[ "$CURRENT_EXECUTABLE_REAL" == "${ASDF_BASE:A}"/* ]]; then
    MANAGER="asdf"
elif command_exists brew; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null)"
    if [[ "$CURRENT_EXECUTABLE_REAL" == "$BREW_PREFIX"/Cellar/python@<->.<->/* ]]; then
        MANAGER="brew"
        BREW_FORMULA="${${CURRENT_EXECUTABLE_REAL#${BREW_PREFIX}/Cellar/}%%/*}"
    elif [[ "$CURRENT_EXECUTABLE_REAL" == "$BREW_PREFIX"/Cellar/python/* ]]; then
        MANAGER="brew"
        BREW_FORMULA="python"
    fi
fi

if [[ "$MANAGER" == "unknown" && "$CURRENT_EXECUTABLE_REAL" == /Library/Frameworks/Python.framework/* ]]; then
    MANAGER="python.org installer"
fi

print -r -- "${BLUE}Current version:${NC} $CURRENT_VERSION"
print -r -- "${BLUE}Active executable:${NC} $CURRENT_EXECUTABLE_REAL"
print -r -- "${BLUE}Detected manager:${NC} $MANAGER"

INSTALLED_VERSIONS_RAW="$({
    print -r -- "$CURRENT_VERSION"

    if command_exists pyenv; then
        pyenv versions --bare 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true
    fi

    if command_exists asdf; then
        asdf list python 2>/dev/null | sed -E 's/^[*[:space:]]+//' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true
    fi

    if command_exists brew; then
        brew list --versions 2>/dev/null | awk '/^python(@[0-9]+\.[0-9]+)? / { for (i = 2; i <= NF; i++) print $i }'
    fi
} | "$PYTHON_BIN" -c '
import re
import sys

def version_key(version):
    return tuple(int(part) for part in version.split("."))

versions = {line.strip() for line in sys.stdin if re.fullmatch(r"\d+\.\d+\.\d+", line.strip())}
for version in sorted(versions, key=version_key):
    print(version)
')" || {
    print_error "Could not build the Python version inventory."
    exit 1
}

print
print_info "Installed versions detected:"
print -r -- "$INSTALLED_VERSIONS_RAW" | sed 's/^/  - /'

if ! command_exists curl; then
    print_error "Error: curl is required to check Python releases."
    exit 1
fi

print_info "Fetching release information from python.org..."
if ! RELEASES_JSON="$(fetch_url 'https://www.python.org/api/v2/downloads/release/?is_published=true&show_on_download_page=true&order_by=-release_date')"; then
    print_error "Could not fetch Python release information."
    exit 1
fi

if ! LATEST_SAME_MINOR="$(print -rn -- "$RELEASES_JSON" | CURRENT_MINOR="$CURRENT_MINOR" "$PYTHON_BIN" -c '
import json
import os
import re
import sys

def version_key(version):
    return tuple(int(part) for part in version.split("."))

releases = json.load(sys.stdin)
if not isinstance(releases, list):
    raise ValueError("expected a release list")

current_minor = os.environ.get("CURRENT_MINOR", "")
prefix = f"Python {current_minor}."
versions = []
for release in releases:
    if release.get("pre_release") or not release.get("name", "").startswith(prefix):
        continue
    match = re.fullmatch(r"Python (\d+\.\d+\.\d+)", release.get("name", ""))
    if match:
        versions.append(match.group(1))

if versions:
    print(max(versions, key=version_key))
')"; then
    print_error "python.org returned release data in an unexpected format."
    exit 1
fi

if [[ -z "$LATEST_SAME_MINOR" ]]; then
    print_warning "python.org did not return a published patch for the $CURRENT_MINOR line."
    exit 1
fi

if ! is_valid_version "$LATEST_SAME_MINOR"; then
    print_error "python.org returned an invalid version: $LATEST_SAME_MINOR"
    exit 1
fi

print -r -- "${BLUE}Latest $CURRENT_MINOR patch:${NC} $LATEST_SAME_MINOR"
if ! version_is_newer "$LATEST_SAME_MINOR" "$CURRENT_VERSION"; then
    print_success "Python $CURRENT_VERSION is already up to date for the $CURRENT_MINOR line."
    exit 0
fi

print_warning "A newer patch is available: $CURRENT_VERSION -> $LATEST_SAME_MINOR"
if (( ! UPDATE_REQUESTED )); then
    print_info "Run '$SCRIPT_NAME --update' to install it with the detected manager."
    exit 0
fi

if ! confirm "Install Python $LATEST_SAME_MINOR using $MANAGER?"; then
    print_success "No changes were made."
    exit 0
fi

case "$MANAGER" in
    pyenv)
        command_exists pyenv || { print_error "pyenv is not available in this shell."; exit 1; }
        print_info "Installing Python $LATEST_SAME_MINOR with pyenv..."
        pyenv install -s "$LATEST_SAME_MINOR" || exit 1
        print_warning "The version was installed but not activated. Run: pyenv global $LATEST_SAME_MINOR"
    ;;
    asdf)
        command_exists asdf || { print_error "asdf is not available in this shell."; exit 1; }
        print_info "Installing Python $LATEST_SAME_MINOR with asdf..."
        asdf install python "$LATEST_SAME_MINOR" || exit 1
        print_warning "The version was installed but not activated. Select it with your asdf configuration."
    ;;
    brew)
        print_info "Upgrading $BREW_FORMULA with Homebrew..."
        brew upgrade "$BREW_FORMULA" || exit 1
    ;;
    "python.org installer")
        print_error "Python.org framework installations require the signed macOS installer and cannot be patched safely by this script."
        print -r -- "Download it from: https://www.python.org/downloads/macos/"
        exit 1
    ;;
    *)
        print_error "The active Python installation is not managed by a supported manager."
        exit 1
    ;;
esac

print_success "Python $LATEST_SAME_MINOR was installed successfully."

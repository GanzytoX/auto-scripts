#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

AUTO_YES=0
CHECK_ONLY=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--check] [--yes]"
    print -r -- "  --check  Only report whether an update is available."
    print -r -- "  --yes    Confirm the update or repair non-interactively."
}

while (( $# > 0 )); do
    case "$1" in
        -c|--check) CHECK_ONLY=1 ;;
        -y|--yes) AUTO_YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

if (( AUTO_YES && CHECK_ONLY )); then
    print_error "--yes cannot be combined with --check."
    exit 2
fi

clear_screen
print_info "=== npm Update Check ==="

if ! command_exists npm; then
    print_error "Error: npm is not installed or is not available in PATH."
    print -r -- "Installation instructions: https://docs.npmjs.com/downloading-and-installing-node-js-and-npm"
    exit 1
fi

if ! command_exists curl; then
    print_error "Error: curl is required to check npm releases."
    exit 1
fi

NPM_PATH="$(command -v npm)"
NPM_REAL_PATH="${NPM_PATH:A}"
CURRENT_VERSION="$(npm --version 2>/dev/null)"
NPM_WORKS=$?

if (( NPM_WORKS == 0 )) && ! is_valid_version "$CURRENT_VERSION"; then
    print_warning "npm returned an unexpected version: $CURRENT_VERSION"
    NPM_WORKS=1
fi

MANAGER="unknown"
if command_exists brew; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null)"
    if [[ -n "$BREW_PREFIX" && ( "$NPM_REAL_PATH" == "$BREW_PREFIX"/Cellar/node* || "$NPM_REAL_PATH" == "$BREW_PREFIX"/bin/npm ) ]]; then
        MANAGER="brew"
    fi
fi

if [[ "$MANAGER" == "unknown" ]]; then
    case "$NPM_REAL_PATH" in
        */.fnm/*|*/fnm_multishells/*) MANAGER="fnm" ;;
        */.nvm/*) MANAGER="nvm" ;;
        */.volta/*) MANAGER="volta" ;;
        */n/versions/node/*) MANAGER="n" ;;
        */Library/pnpm/*|*/.local/share/pnpm/*) MANAGER="pnpm" ;;
        */usr/local/*|*/usr/bin/*|*/opt/*) MANAGER="official" ;;
    esac
fi

if [[ "$MANAGER" == "unknown" && (( NPM_WORKS == 0 )) ]]; then
    MANAGER="npm"
fi

print -r -- "${BLUE}Active executable:${NC} $NPM_REAL_PATH"
print -r -- "${BLUE}Detected manager:${NC} $MANAGER"
if (( NPM_WORKS == 0 )); then
    print -r -- "${BLUE}Current version:${NC} $CURRENT_VERSION"
else
    print_warning "The npm executable is present but does not work."
fi

print_info "Fetching the latest npm version from the npm registry..."
if ! REGISTRY_JSON="$(fetch_url 'https://registry.npmjs.org/npm/latest')"; then
    print_error "Could not fetch npm release information."
    exit 1
fi

LATEST_VERSION="$(print -rn -- "$REGISTRY_JSON" | sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p')"
if ! is_valid_version "$LATEST_VERSION"; then
    print_error "The npm registry returned an invalid npm version: ${LATEST_VERSION:-<empty>}"
    exit 1
fi

print -r -- "${GREEN}Latest version:${NC} $LATEST_VERSION"
if (( NPM_WORKS == 0 )) && ! version_is_newer "$LATEST_VERSION" "$CURRENT_VERSION"; then
    print_success "npm is already up to date."
    exit 0
fi

if (( CHECK_ONLY )); then
    if (( NPM_WORKS == 0 )); then
        print_warning "An npm update is available: $CURRENT_VERSION -> $LATEST_VERSION"
    else
        print_warning "npm needs to be repaired. Latest available version: $LATEST_VERSION"
    fi
    exit 0
fi

if [[ "$MANAGER" == "unknown" ]]; then
    print_error "The active npm installation method could not be identified safely."
    print -r -- "Reinstall or update Node.js/npm using the same method originally used."
    exit 1
fi

if (( NPM_WORKS == 0 )); then
    ACTION_PROMPT="Update npm from $CURRENT_VERSION to $LATEST_VERSION using $MANAGER?"
else
    ACTION_PROMPT="Repair npm by installing $LATEST_VERSION using $MANAGER?"
fi

if ! confirm "$ACTION_PROMPT"; then
    print_success "No changes were made."
    exit 0
fi

case "$MANAGER" in
    brew)
        if (( NPM_WORKS == 0 )); then
            print_info "Updating npm with npm..."
            npm install --global "npm@$LATEST_VERSION" || exit 1
        else
            print_info "Upgrading Node.js/npm with Homebrew..."
            brew upgrade node || exit 1
        fi
    ;;
    fnm|nvm|volta|n|pnpm|official|npm)
        if (( NPM_WORKS == 0 )); then
            print_info "Updating npm with npm..."
            npm install --global "npm@$LATEST_VERSION" || exit 1
        else
            print_error "npm is broken and cannot self-update. Reinstall Node.js using $MANAGER."
            exit 1
        fi
    ;;
esac

NEW_VERSION="$(npm --version 2>/dev/null)" || {
    print_error "The update command completed, but npm still does not run."
    exit 1
}

if ! is_valid_version "$NEW_VERSION"; then
    print_error "npm returned an invalid version after the update: $NEW_VERSION"
    exit 1
fi

if version_is_newer "$LATEST_VERSION" "$NEW_VERSION"; then
    print_error "npm is still older than expected after the update: $NEW_VERSION"
    exit 1
fi

print_success "npm is ready. Active version: $NEW_VERSION"

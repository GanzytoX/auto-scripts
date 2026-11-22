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
    print -r -- "Exit status: 0 up to date or updated, 1 error, $EXIT_UPDATE_AVAILABLE update available (--check)."
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
print_info "=== pnpm Update Check ==="

if ! command_exists pnpm; then
    print_error "Error: pnpm is not installed or is not available in PATH."
    print -r -- "Installation instructions: https://pnpm.io/installation"
    exit 1
fi

if ! command_exists curl; then
    print_error "Error: curl is required to check pnpm releases."
    exit 1
fi

PNPM_PATH="$(command -v pnpm)"
PNPM_REAL_PATH="${PNPM_PATH:A}"
CURRENT_VERSION="$(pnpm --version 2>/dev/null)"
PNPM_WORKS=$?

if (( PNPM_WORKS == 0 )) && ! is_valid_version "$CURRENT_VERSION"; then
    print_warning "pnpm returned an unexpected version: $CURRENT_VERSION"
    PNPM_WORKS=1
fi

MANAGER="unknown"
if command_exists brew; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null)"
    if [[ "$PNPM_REAL_PATH" == "$BREW_PREFIX"/Cellar/pnpm/* ]] && brew list --formula pnpm >/dev/null 2>&1; then
        MANAGER="brew"
    fi
fi

if [[ "$MANAGER" == "unknown" && "$PNPM_REAL_PATH" == */Library/pnpm/* ]]; then
    MANAGER="standalone"
elif [[ "$MANAGER" == "unknown" && "$PNPM_REAL_PATH" == */.local/share/pnpm/* ]]; then
    MANAGER="standalone"
elif [[ "$MANAGER" == "unknown" ]] && command_exists corepack && grep -q 'corepack' "$PNPM_PATH" 2>/dev/null; then
    MANAGER="corepack"
elif [[ "$MANAGER" == "unknown" ]] && command_exists npm; then
    NPM_PREFIX="$(npm prefix --global 2>/dev/null)"
    if [[ -n "$NPM_PREFIX" && "$PNPM_PATH" == "$NPM_PREFIX/bin/pnpm" ]]; then
        MANAGER="npm"
    fi
fi

print -r -- "${BLUE}Active executable:${NC} $PNPM_REAL_PATH"
print -r -- "${BLUE}Detected manager:${NC} $MANAGER"
if (( PNPM_WORKS == 0 )); then
    print -r -- "${BLUE}Current version:${NC} $CURRENT_VERSION"
else
    print_warning "The pnpm executable is present but does not work."
fi

print_info "Fetching the latest pnpm version from the npm registry..."
if ! REGISTRY_JSON="$(fetch_url 'https://registry.npmjs.org/pnpm/latest')"; then
    print_error "Could not fetch pnpm release information."
    exit 1
fi

# Parse the top-level "version" key properly; never regex over the JSON.
if command_exists jq; then
    LATEST_VERSION="$(print -rn -- "$REGISTRY_JSON" | jq -r '.version // empty' 2>&1)"
elif command_exists python3; then
    LATEST_VERSION="$(print -rn -- "$REGISTRY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>&1)"
else
    print_error "jq or python3 is required to read the npm registry response."
    exit 1
fi
if ! is_valid_version "$LATEST_VERSION"; then
    print_error "The npm registry returned an invalid pnpm version: ${LATEST_VERSION:-<empty>}"
    exit 1
fi

print -r -- "${GREEN}Latest version:${NC} $LATEST_VERSION"
if (( PNPM_WORKS == 0 )) && ! version_is_newer "$LATEST_VERSION" "$CURRENT_VERSION"; then
    print_success "pnpm is already up to date."
    exit 0
fi

if (( CHECK_ONLY )); then
    if (( PNPM_WORKS == 0 )); then
        print_warning "A pnpm update is available: $CURRENT_VERSION -> $LATEST_VERSION"
    else
        print_warning "pnpm needs to be repaired. Latest available version: $LATEST_VERSION"
    fi
    exit $EXIT_UPDATE_AVAILABLE
fi

if [[ "$MANAGER" == "unknown" ]]; then
    print_error "The active pnpm installation method could not be identified safely."
    print -r -- "Reinstall or update pnpm using the same method originally used."
    exit 1
fi

if (( PNPM_WORKS == 0 )); then
    ACTION_PROMPT="Update pnpm from $CURRENT_VERSION to $LATEST_VERSION using $MANAGER?"
else
    ACTION_PROMPT="Repair pnpm by installing $LATEST_VERSION using $MANAGER?"
fi

if ! confirm "$ACTION_PROMPT"; then
    print_success "No changes were made."
    exit 0
fi

case "$MANAGER" in
    brew)
        print_info "Updating pnpm with Homebrew..."
        run_step "brew upgrade pnpm" brew upgrade pnpm || exit 1
    ;;
    corepack)
        if (( PNPM_WORKS != 0 )); then
            print_error "The Corepack shim is not working. Repair Corepack before updating pnpm."
            exit 1
        fi
        print_info "Updating pnpm with Corepack..."
        run_step "corepack install --global pnpm@$LATEST_VERSION" corepack install --global "pnpm@$LATEST_VERSION" || exit 1
    ;;
    npm)
        print_info "Updating pnpm with npm..."
        run_step "npm install --global pnpm@$LATEST_VERSION" npm install --global "pnpm@$LATEST_VERSION" || exit 1
    ;;
    standalone)
        if (( PNPM_WORKS == 0 )); then
            SAFE_WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pnpm-self-update.XXXXXX")" || exit 1
            print_info "Updating the standalone pnpm installation..."
            (
                cd "$SAFE_WORKDIR" || exit 1
                pnpm self-update "$LATEST_VERSION"
            )
            UPDATE_STATUS=$?
            rmdir "$SAFE_WORKDIR" || print_warning "Could not remove temporary directory: $SAFE_WORKDIR"
            if (( UPDATE_STATUS != 0 )); then
                print_error "FAILED: pnpm self-update $LATEST_VERSION (exit status $UPDATE_STATUS); no alternative installation method was attempted."
                exit 1
            fi
        else
            INSTALLER_FILE="$(mktemp "${TMPDIR:-/tmp}/pnpm-install.XXXXXX")" || exit 1
            print_info "Downloading the official pnpm installer to repair the standalone installation..."
            if ! fetch_url 'https://get.pnpm.io/install.sh' > "$INSTALLER_FILE"; then
                rm -f "$INSTALLER_FILE"
                print_error "The pnpm installer could not be downloaded."
                exit 1
            fi
            if [[ ! -s "$INSTALLER_FILE" ]] || [[ "$(head -c 2 "$INSTALLER_FILE")" != "#!" ]]; then
                rm -f "$INSTALLER_FILE"
                print_error "The downloaded pnpm installer is empty or is not a shell script; it was not executed."
                exit 1
            fi
            print_info "Installer sha256: $(shasum -a 256 "$INSTALLER_FILE" | cut -d' ' -f1)"
            if ! run_step "official pnpm installer (get.pnpm.io/install.sh)" /bin/sh "$INSTALLER_FILE"; then
                rm -f "$INSTALLER_FILE"
                exit 1
            fi
            rm -f "$INSTALLER_FILE"
            rehash
        fi
    ;;
esac

NEW_VERSION="$(pnpm --version 2>/dev/null)" || {
    print_error "The update command completed, but pnpm still does not run."
    exit 1
}

if ! is_valid_version "$NEW_VERSION"; then
    print_error "pnpm returned an invalid version after the update: $NEW_VERSION"
    exit 1
fi

if version_is_newer "$LATEST_VERSION" "$NEW_VERSION"; then
    print_error "pnpm is still older than expected after the update: $NEW_VERSION"
    exit 1
fi

print_success "pnpm is ready. Active version: $NEW_VERSION"

#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

AUTO_YES=0
UPDATE_REQUESTED=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--update] [--yes]"
    print -r -- "  --update  Offer to install the latest patch in the active major line."
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
print_info "=== Node.js Status ==="

if ! command_exists node; then
    print_error "Error: Node.js is not installed on this system."
    print -r -- "Install it from https://nodejs.org/ or with a version manager."
    exit 1
fi

if ! command_exists curl; then
    print_error "Error: curl is required to check Node.js releases."
    exit 1
fi

CURRENT_VERSION_RAW="$(node --version 2>/dev/null)" || {
    print_error "The Node.js executable exists but could not report its version."
    exit 1
}
CURRENT_VERSION="${CURRENT_VERSION_RAW#v}"
if ! is_valid_version "$CURRENT_VERSION"; then
    print_error "Unexpected Node.js version: $CURRENT_VERSION_RAW"
    exit 1
fi

NODE_PATH="$(command -v node)"
NODE_REAL_PATH="${NODE_PATH:A}"
CURRENT_MAJOR="${CURRENT_VERSION%%.*}"

print -r -- "${BLUE}Current version:${NC} v$CURRENT_VERSION"
print -r -- "${BLUE}Active executable:${NC} $NODE_REAL_PATH"

MANAGER="unknown"
BREW_FORMULA=""
case "$NODE_REAL_PATH" in
    */Library/pnpm/*|*/.local/share/pnpm/*) MANAGER="pnpm" ;;
    */.fnm/*|*/fnm_multishells/*) MANAGER="fnm" ;;
    */.nvm/*) MANAGER="nvm" ;;
    */n/versions/node/*) MANAGER="n" ;;
esac

if [[ "$MANAGER" == "unknown" ]] && command_exists brew; then
    BREW_PREFIX="$(brew --prefix 2>/dev/null)"
    if [[ "$NODE_REAL_PATH" == "$BREW_PREFIX"/Cellar/node/* ]]; then
        MANAGER="brew"
        BREW_FORMULA="node"
    elif [[ "$NODE_REAL_PATH" == "$BREW_PREFIX"/Cellar/node@<->/* ]]; then
        MANAGER="brew"
        BREW_FORMULA="${${NODE_REAL_PATH#${BREW_PREFIX}/Cellar/}%%/*}"
    fi
fi

print -r -- "${BLUE}Detected manager:${NC} $MANAGER"
print_info "Fetching release information from nodejs.org..."

if ! RELEASES_JSON="$(fetch_url 'https://nodejs.org/dist/index.json')"; then
    print_error "Could not fetch Node.js release information."
    exit 1
fi

if ! RELEASE_INFO="$(print -rn -- "$RELEASES_JSON" | CURRENT_MAJOR="$CURRENT_MAJOR" node -e '
const fs = require("fs");
const releases = JSON.parse(fs.readFileSync(0, "utf8"));
if (!Array.isArray(releases) || releases.length === 0) process.exit(2);
const current = releases[0];
const lts = releases.find((release) => release.lts);
const sameMajor = releases.find((release) => release.version.startsWith(`v${process.env.CURRENT_MAJOR}.`));
if (!current || !lts || !sameMajor) process.exit(3);
process.stdout.write([current.version, lts.version, lts.lts, sameMajor.version].join("\t"));
')"; then
    print_error "nodejs.org returned release data in an unexpected format."
    exit 1
fi

IFS=$'\t' read -r LATEST_CURRENT LATEST_LTS LTS_NAME LATEST_SAME_MAJOR <<< "$RELEASE_INFO"
LATEST_CURRENT="${LATEST_CURRENT#v}"
LATEST_LTS="${LATEST_LTS#v}"
LATEST_SAME_MAJOR="${LATEST_SAME_MAJOR#v}"

for version in "$LATEST_CURRENT" "$LATEST_LTS" "$LATEST_SAME_MAJOR"; do
    if ! is_valid_version "$version"; then
        print_error "nodejs.org returned an invalid version: $version"
        exit 1
    fi
done

print
print -r -- "${GREEN}Latest LTS:${NC}     v$LATEST_LTS ($LTS_NAME)"
print -r -- "${YELLOW}Latest Current:${NC} v$LATEST_CURRENT"
print -r -- "${BLUE}Latest v$CURRENT_MAJOR patch:${NC} v$LATEST_SAME_MAJOR"

if ! version_is_newer "$LATEST_SAME_MAJOR" "$CURRENT_VERSION"; then
    print_success "Node.js v$CURRENT_MAJOR is already up to date."
    exit 0
fi

print_warning "A newer v$CURRENT_MAJOR patch is available: v$CURRENT_VERSION -> v$LATEST_SAME_MAJOR"
if (( ! UPDATE_REQUESTED )); then
    print_info "Run '$SCRIPT_NAME --update' to install it with the detected manager."
    exit 0
fi

if ! confirm "Install Node.js v$LATEST_SAME_MAJOR using $MANAGER?"; then
    print_success "No changes were made."
    exit 0
fi

case "$MANAGER" in
    pnpm)
        if ! command_exists pnpm || ! pnpm --version >/dev/null 2>&1; then
            print_error "Node.js is managed by pnpm, but the pnpm executable is not working. Repair pnpm first."
            exit 1
        fi
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with pnpm runtime..."
        pnpm runtime set node "$LATEST_SAME_MAJOR" --global || exit 1
    ;;
    fnm)
        command_exists fnm || { print_error "fnm is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with fnm..."
        fnm install "$LATEST_SAME_MAJOR" && fnm default "$LATEST_SAME_MAJOR" || exit 1
    ;;
    nvm)
        NVM_SCRIPT_DIR="${NVM_DIR:-$HOME/.nvm}"
        if ! command_exists nvm && [[ -s "$NVM_SCRIPT_DIR/nvm.sh" ]]; then
            source "$NVM_SCRIPT_DIR/nvm.sh"
        fi
        command_exists nvm || { print_error "nvm could not be loaded."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with nvm..."
        nvm install "$LATEST_SAME_MAJOR" && nvm alias default "$LATEST_SAME_MAJOR" || exit 1
    ;;
    n)
        command_exists n || { print_error "n is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with n..."
        n "$LATEST_SAME_MAJOR" || exit 1
    ;;
    brew)
        if [[ "$BREW_FORMULA" == "node" ]]; then
            print_error "The active Homebrew formula is unversioned. 'brew upgrade node' could cross major versions, so it was not run."
            print -r -- "Use Homebrew directly if you intend to upgrade to its current Node.js major."
            exit 1
        fi
        print_info "Upgrading $BREW_FORMULA with Homebrew..."
        brew upgrade "$BREW_FORMULA" || exit 1
    ;;
    *)
        print_error "The active Node.js installation is not managed by a supported manager."
        exit 1
    ;;
esac

print_success "Node.js v$LATEST_SAME_MAJOR was installed successfully."

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
    print -r -- "Exit status: 0 up to date or updated, 1 error, $EXIT_UPDATE_AVAILABLE update available (not installed)."
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

NODE_BIN_PATH="$(command -v node)"   # not NODE_PATH: that is a Node.js env variable
NODE_REAL_PATH="${NODE_BIN_PATH:A}"
CURRENT_MAJOR="${CURRENT_VERSION%%.*}"

print -r -- "${BLUE}Current version:${NC} v$CURRENT_VERSION"
print -r -- "${BLUE}Active executable:${NC} $NODE_REAL_PATH"

MANAGER="unknown"
BREW_FORMULA=""
# Match both the raw and the resolved path: shims (volta, mise, asdf) resolve to the manager binary.
case "$NODE_BIN_PATH|$NODE_REAL_PATH" in
    */Library/pnpm/*|*/.local/share/pnpm/*) MANAGER="pnpm" ;;
    */.fnm/*|*/fnm_multishells/*|*/.local/share/fnm/*) MANAGER="fnm" ;;
    */.nvm/*) MANAGER="nvm" ;;
    */n/versions/node/*) MANAGER="n" ;;
    */.volta/*) MANAGER="volta" ;;
    */.asdf/*) MANAGER="asdf" ;;
    */mise/*|*/.mise/*) MANAGER="mise" ;;
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

# Prefer jq for parsing: relying on the same Node.js binary being evaluated to parse
# its own upstream release feed is a needless circular dependency, and jq is the more
# conventional tool for this. Fall back to node only if jq is unavailable.
if command_exists jq; then
    RELEASE_INFO="$(print -rn -- "$RELEASES_JSON" | jq -r --arg major "$CURRENT_MAJOR" '
        if (type != "array") then empty else
        # Ignore pre-release entries (alpha/beta/rc/nightly) such as v27.0.0-alpha.0.1.0
        map(select(.version | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$"))) as $stable |
        if ($stable | length) == 0 then empty else
        ($stable | .[0]) as $current |
        ($stable | map(select(.lts != false)) | first) as $lts |
        ($stable | map(select(.version | startswith("v" + $major + "."))) | first) as $sameMajor |
        if ($current == null or $lts == null or $sameMajor == null) then empty else
        [$current.version, $lts.version, $lts.lts, $sameMajor.version] | @tsv
        end end end
    ')"
    PARSE_STATUS=$?
else
    print_warning "jq not found; falling back to Node.js to parse release data."
    RELEASE_INFO="$(print -rn -- "$RELEASES_JSON" | CURRENT_MAJOR="$CURRENT_MAJOR" node -e '
const fs = require("fs");
const all = JSON.parse(fs.readFileSync(0, "utf8"));
if (!Array.isArray(all)) process.exit(2);
// Ignore pre-release entries (alpha/beta/rc/nightly) such as v27.0.0-alpha.0.1.0
const releases = all.filter((release) => /^v\d+\.\d+\.\d+$/.test(release.version));
if (releases.length === 0) process.exit(2);
const current = releases[0];
const lts = releases.find((release) => release.lts);
const sameMajor = releases.find((release) => release.version.startsWith(`v${process.env.CURRENT_MAJOR}.`));
if (!current || !lts || !sameMajor) process.exit(3);
process.stdout.write([current.version, lts.version, lts.lts, sameMajor.version].join("\t"));
')"
    PARSE_STATUS=$?
fi

if (( PARSE_STATUS != 0 )) || [[ -z "$RELEASE_INFO" ]]; then
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

LTS_MAJOR="${LATEST_LTS%%.*}"
if (( LTS_MAJOR > CURRENT_MAJOR )); then
    print_warning "Active major v$CURRENT_MAJOR is older than the current LTS line v$LTS_MAJOR; this script only updates within v$CURRENT_MAJOR."
fi

if ! version_is_newer "$LATEST_SAME_MAJOR" "$CURRENT_VERSION"; then
    print_success "Node.js v$CURRENT_MAJOR is already up to date."
    exit 0
fi

print_warning "A newer v$CURRENT_MAJOR patch is available: v$CURRENT_VERSION -> v$LATEST_SAME_MAJOR"
if (( ! UPDATE_REQUESTED )); then
    print_info "Run '${0:A} --update' to install it with the detected manager."
    exit $EXIT_UPDATE_AVAILABLE
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
        run_step "pnpm runtime set node $LATEST_SAME_MAJOR" pnpm runtime set node "$LATEST_SAME_MAJOR" --global || exit 1
    ;;
    fnm)
        command_exists fnm || { print_error "fnm is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with fnm..."
        run_step "fnm install $LATEST_SAME_MAJOR" fnm install "$LATEST_SAME_MAJOR" || exit 1
        run_step "fnm default $LATEST_SAME_MAJOR" fnm default "$LATEST_SAME_MAJOR" || exit 1
    ;;
    nvm)
        NVM_SCRIPT_DIR="${NVM_DIR:-$HOME/.nvm}"
        if ! command_exists nvm && [[ -s "$NVM_SCRIPT_DIR/nvm.sh" ]]; then
            source "$NVM_SCRIPT_DIR/nvm.sh"
        fi
        command_exists nvm || { print_error "nvm could not be loaded."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with nvm..."
        run_step "nvm install $LATEST_SAME_MAJOR" nvm install "$LATEST_SAME_MAJOR" || exit 1
        run_step "nvm alias default $LATEST_SAME_MAJOR" nvm alias default "$LATEST_SAME_MAJOR" || exit 1
    ;;
    n)
        command_exists n || { print_error "n is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with n..."
        run_step "n $LATEST_SAME_MAJOR" n "$LATEST_SAME_MAJOR" || exit 1
    ;;
    volta)
        command_exists volta || { print_error "volta is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with volta..."
        run_step "volta install node@$LATEST_SAME_MAJOR" volta install "node@$LATEST_SAME_MAJOR" || exit 1
    ;;
    asdf)
        command_exists asdf || { print_error "asdf is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with asdf..."
        run_step "asdf install nodejs $LATEST_SAME_MAJOR" asdf install nodejs "$LATEST_SAME_MAJOR" || exit 1
        # asdf >= 0.16 replaced 'asdf global' with 'asdf set'.
        if asdf set --help >/dev/null 2>&1; then
            run_step "asdf set --home nodejs $LATEST_SAME_MAJOR" asdf set --home nodejs "$LATEST_SAME_MAJOR" || exit 1
        else
            run_step "asdf global nodejs $LATEST_SAME_MAJOR" asdf global nodejs "$LATEST_SAME_MAJOR" || exit 1
        fi
    ;;
    mise)
        command_exists mise || { print_error "mise is not available in this shell."; exit 1; }
        print_info "Installing Node.js v$LATEST_SAME_MAJOR with mise..."
        run_step "mise use --global node@$LATEST_SAME_MAJOR" mise use --global "node@$LATEST_SAME_MAJOR" || exit 1
    ;;
    brew)
        # Formula "node" is unversioned: it is only safe when Homebrew still offers the same major.
        if [[ "$BREW_FORMULA" == "node" ]]; then
            BREW_AVAILABLE=""
            if command_exists jq; then
                BREW_AVAILABLE="$(brew info --json=v2 node 2>/dev/null | jq -r '.formulae[0].versions.stable // empty')"
            fi
            if [[ -z "$BREW_AVAILABLE" ]]; then
                print_error "Could not read the version Homebrew offers for 'node' (jq missing or brew info failed); nothing was changed."
                exit 1
            fi
            if [[ "${BREW_AVAILABLE%%.*}" != "$CURRENT_MAJOR" ]]; then
                print_error "Homebrew's 'node' formula is now v$BREW_AVAILABLE, a different major than your v$CURRENT_MAJOR; 'brew upgrade node' would cross major versions, so it was not run."
                print -r -- "To stay on v$CURRENT_MAJOR: brew install node@$CURRENT_MAJOR (versioned formula). To move to v${BREW_AVAILABLE%%.*}: brew upgrade node"
                exit 1
            fi
            if ! version_is_newer "$BREW_AVAILABLE" "$CURRENT_VERSION"; then
                print_error "Homebrew still offers v$BREW_AVAILABLE for 'node' (latest upstream v$LATEST_SAME_MAJOR); the formula has not caught up yet. Nothing was changed."
                exit 1
            fi
            LATEST_SAME_MAJOR_TARGET="$BREW_AVAILABLE"
        fi
        print_info "Upgrading $BREW_FORMULA with Homebrew..."
        run_step "brew upgrade $BREW_FORMULA" brew upgrade "$BREW_FORMULA" || exit 1
    ;;
    *)
        print_error "The active Node.js installation is not managed by a supported manager."
        exit 1
    ;;
esac

# Verify what the active node reports now, instead of assuming the command worked.
rehash
EXPECTED="${LATEST_SAME_MAJOR_TARGET:-$LATEST_SAME_MAJOR}"
NEW_VERSION="$(node --version 2>/dev/null)"
NEW_VERSION="${NEW_VERSION#v}"
if [[ "$NEW_VERSION" == "$EXPECTED" ]]; then
    print_success "Node.js v$NEW_VERSION is now active."
    exit 0
fi
case "$MANAGER" in
    fnm|nvm|volta|asdf|mise)
        print_warning "Node.js v$EXPECTED was installed and set as default, but this shell still reports v${NEW_VERSION:-unknown}. Open a new terminal to use it."
        exit 0
    ;;
    *)
        print_error "The update command succeeded but the active node still reports v${NEW_VERSION:-unknown} (expected v$EXPECTED)."
        exit 1
    ;;
esac

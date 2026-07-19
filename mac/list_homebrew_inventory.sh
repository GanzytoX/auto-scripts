#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

if (( $# > 0 )); then
    if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        print -r -- "Usage: $SCRIPT_NAME"
        exit 0
    fi
    print_error "Unknown option: $1"
    print -r -- "Usage: $SCRIPT_NAME" >&2
    exit 2
fi

clear_screen
print_info "=== Homebrew Inventory ==="

if ! command_exists brew; then
    print_error "Error: Homebrew is not installed on this system."
    print -r -- "To install it, visit: https://brew.sh/"
    exit 1
fi

BREW_PREFIX="$(brew --prefix)" || exit 1
BREW_VERSION_OUTPUT="$(brew --version)" || exit 1
BREW_VERSION="${BREW_VERSION_OUTPUT%%$'\n'*}"
print -r -- "${BLUE}Homebrew prefix:${NC} $BREW_PREFIX"
print -r -- "${BLUE}Homebrew version:${NC} $BREW_VERSION"

print
print_info "[1/4] Installed formulae"
if ! FORMULAE_LIST="$(brew list --formula)"; then
    print_error "Could not list installed formulae."
    exit 1
fi
if [ -n "$FORMULAE_LIST" ]; then
    print -r -- "$FORMULAE_LIST" | sort
    print_success "Total formulae: $(print -r -- "$FORMULAE_LIST" | wc -l | tr -d ' ')"
else
    print_warning "No formulae installed."
fi

print
print_info "[2/4] Installed casks"
if ! CASKS_LIST="$(brew list --cask)"; then
    print_error "Could not list installed casks."
    exit 1
fi
if [ -n "$CASKS_LIST" ]; then
    print -r -- "$CASKS_LIST" | sort
    print_success "Total casks: $(print -r -- "$CASKS_LIST" | wc -l | tr -d ' ')"
else
    print_warning "No casks installed."
fi

print
print_info "[3/4] Tapped repositories"
if ! TAPS_LIST="$(brew tap)"; then
    print_error "Could not list tapped repositories."
    exit 1
fi
if [ -n "$TAPS_LIST" ]; then
    print -r -- "$TAPS_LIST" | sort
    print_success "Total taps: $(print -r -- "$TAPS_LIST" | wc -l | tr -d ' ')"
else
    print_warning "No additional taps configured."
fi

print
print_info "[4/4] Homebrew services"
SERVICES_OUTPUT="$(brew services list 2>&1)"
SERVICES_STATUS=$?
if (( SERVICES_STATUS == 0 )); then
    print -r -- "$SERVICES_OUTPUT"
else
    print_warning "Homebrew services could not be listed:"
    print -r -- "$SERVICES_OUTPUT" >&2
    exit 1
fi

print
print_success "Inventory complete."

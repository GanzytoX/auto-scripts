#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

AUTO_YES=0
DRY_RUN=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--yes] [--dry-run]"
}

while (( $# > 0 )); do
    case "$1" in
        -y|--yes) AUTO_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

clear_screen
print_info "=== Homebrew Update ==="

if ! command_exists brew; then
    print_error "Error: Homebrew is not installed on this system."
    print -r -- "To install it, visit: https://brew.sh/"
    exit 1
fi

print_info "Refreshing Homebrew metadata..."
if ! brew update-if-needed; then
    print_error "Homebrew metadata could not be updated. No packages were changed."
    exit 1
fi

print_info "Checking outdated formulae and casks..."
if ! OUTDATED="$(brew outdated --verbose)"; then
    print_error "Homebrew could not determine which packages are outdated."
    exit 1
fi

if [[ -z "$OUTDATED" ]]; then
    print_success "Everything managed by Homebrew is already up to date."
    exit 0
fi

print
print -r -- "$OUTDATED"
print

if (( DRY_RUN )); then
    print_info "Dry run: Homebrew reports the following upgrade plan:"
    brew upgrade --dry-run
    exit $?
fi

if ! confirm "Upgrade all outdated Homebrew packages?"; then
    print_success "No packages were changed."
    exit 0
fi

print_info "Upgrading outdated packages..."
if ! brew upgrade; then
    print_error "One or more Homebrew packages could not be upgraded."
    exit 1
fi

print_success "Homebrew packages were upgraded successfully."

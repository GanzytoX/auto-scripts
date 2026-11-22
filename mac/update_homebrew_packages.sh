#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

AUTO_YES=0
DRY_RUN=0
GREEDY=1

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--yes] [--dry-run] [--no-greedy]"
    print -r -- "  --no-greedy  Skip casks that update themselves (auto_updates / latest)."
}

while (( $# > 0 )); do
    case "$1" in
        -y|--yes) AUTO_YES=1 ;;
        -n|--dry-run) DRY_RUN=1 ;;
        --no-greedy) GREEDY=0 ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

# Every failed operation is logged with its real error and printed in a final summary.
typeset -a FAIL_LOG=()
# log_failure <action> <target> <error output>
log_failure() {
    local err="${3//$'\n'/ | }"
    [[ -z "$err" ]] && err="(no error output)"
    FAIL_LOG+=("$1: $2 -> $err")
    print_error "  FAILED: $1: $2"
    print_error "    reason: $err"
}

# Same package set for outdated, dry-run and upgrade.
typeset -a GREEDY_FLAG=()
(( GREEDY )) && GREEDY_FLAG=(--greedy)

finish() {
    print
    if (( ${#FAIL_LOG[@]} > 0 )); then
        print_error "=== ${#FAIL_LOG[@]} operation(s) FAILED ==="
        local f
        for f in "${FAIL_LOG[@]}"; do print_error "  - $f"; done
        print_warning "Failed packages will show up again as outdated on the next run."
        exit 1
    fi
    exit 0
}

clear_screen
print_info "=== Homebrew Update ==="
(( GREEDY )) && print_info "Mode: greedy (includes casks that update themselves). Use --no-greedy to skip them."

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

# Pinned formulae are never upgraded; say so instead of hiding them.
PINNED="$(brew list --pinned 2>&1)"
if [[ -n "$PINNED" ]]; then
    print_warning "Pinned (will NOT be upgraded): ${PINNED//$'\n'/, }"
fi

print_info "Checking outdated formulae and casks..."
if ! OUTDATED="$(brew outdated --verbose "${GREEDY_FLAG[@]}")"; then
    print_error "Homebrew could not determine which packages are outdated."
    exit 1
fi

# Deprecated / disabled packages (they keep working until disabled, then break).
report_deprecated() {
    command_exists python3 || return 0
    local info
    info="$(brew info --json=v2 --installed 2>&1)" || {
        print -r -- "  Could not read installed package info: ${info//$'\n'/ | }"
        return 0
    }
    print -r -- "$info" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for kind in ("formulae", "casks"):
    for p in d.get(kind, []):
        name = p.get("name") if kind == "formulae" else p.get("token")
        if p.get("disabled"):
            reason = p.get("disable_reason")
            print("DISABLED: " + name + " (" + str(reason) + ")")
        elif p.get("deprecated"):
            reason = p.get("deprecation_reason")
            when = p.get("disable_date")
            extra = "; will be disabled on " + when if when else ""
            print("DEPRECATED: " + name + " (" + str(reason) + extra + ")")
' 2>&1 | sed 's/^/  /'
}

if [[ -z "$OUTDATED" ]]; then
    print_success "Everything managed by Homebrew is already up to date."
else
    print
    print -r -- "$OUTDATED"
    print

    if (( DRY_RUN )); then
        print_info "Dry run: Homebrew reports the following upgrade plan:"
        brew upgrade --dry-run "${GREEDY_FLAG[@]}" || log_failure "brew upgrade --dry-run" "all" "exit status $?"
    elif ! confirm "Upgrade all outdated Homebrew packages?"; then
        print_success "No packages were changed."
        finish
    else
        # Casks may need the admin password (pkg installers); warn if it cannot be asked.
        if [[ -n "$(brew outdated --cask --quiet "${GREEDY_FLAG[@]}" 2>/dev/null)" && ! -t 0 ]]; then
            print_warning "Some casks may need your admin password but stdin is not a terminal; they can fail."
        fi

        # One package at a time so a failure names the exact package and its real error.
        UPGRADED=0
        LOG="$(mktemp -t brew-upgrade)"
        while IFS= read -r -u3 pkg; do
            [[ -z "$pkg" ]] && continue
            print_info "Upgrading $pkg..."
            brew upgrade "${GREEDY_FLAG[@]}" "$pkg" 2>&1 | tee "$LOG"
            if (( ${pipestatus[1]} == 0 )); then
                (( UPGRADED++ ))
            else
                log_failure "brew upgrade" "$pkg" "$(grep -iE 'error|failed|not permitted|denied' "$LOG" | tail -3)"
            fi
        done 3< <(brew outdated --quiet "${GREEDY_FLAG[@]}")
        rm -f "$LOG"
        print_success "Upgraded $UPGRADED package(s)."
    fi
fi

print
print_info "Checking deprecated or disabled packages..."
DEPRECATED_OUT="$(report_deprecated)"
if [[ -n "$DEPRECATED_OUT" ]]; then
    print_warning "$DEPRECATED_OUT"
else
    print_success "No deprecated or disabled packages installed."
fi

print
if (( DRY_RUN )); then
    print_info "Dry run: cleanup that would be performed:"
    brew cleanup -n 2>&1 | tail -5
    brew autoremove -n 2>&1 | tail -5
else
    print_info "Running 'brew autoremove' and 'brew cleanup'..."
    out="$(brew autoremove 2>&1)" || log_failure "brew autoremove" "all" "$out"
    out="$(brew cleanup 2>&1)" || log_failure "brew cleanup" "all" "$out"
    print_success "Cleanup finished."
fi

if (( ${#FAIL_LOG[@]} == 0 )); then
    print_success "Homebrew maintenance completed successfully."
fi
finish

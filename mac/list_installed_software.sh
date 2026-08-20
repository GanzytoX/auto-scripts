#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

# Output inventory warnings/notices to stdout so report redirections remain complete
print_warning() {
    print -r -- "${YELLOW}$*${NC}"
}

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
print_info "=== Installed Software Inventory ==="

print
print_info "[1/9] macOS applications"
if ! APPLICATIONS_OUTPUT="$(system_profiler SPApplicationsDataType 2>/dev/null)"; then
    print_error "Could not list macOS applications."
    exit 1
fi

APPLICATIONS_LIST="$(print -r -- "$APPLICATIONS_OUTPUT" | awk '
function emit() {
    if (name != "") {
        print name "\t" version "\t" location
    }
}

/^    [^[:space:]].*:$/ {
    emit()
    name = $0
    sub(/^    /, "", name)
    sub(/:$/, "", name)
    version = "Unknown"
    location = "Unknown"
    next
}

/^      Version:/ {
    version = $0
    sub(/^      Version:[[:space:]]*/, "", version)
    next
}

/^      Location:/ {
    location = $0
    sub(/^      Location:[[:space:]]*/, "", location)
    next
}

END { emit() }
')"

if [[ -n "$APPLICATIONS_LIST" ]]; then
    printf '  %-40s %-18s %s\n' "Application" "Version" "Location"
    printf '  %-40s %-18s %s\n' "----------------------------------------" "------------------" "------------------------------"
    while IFS=$'\t' read -r application_name application_version application_location; do
        printf '  %-40s %-18s %s\n' "$application_name" "$application_version" "$application_location"
    done <<< "$APPLICATIONS_LIST"
    print_success "Total applications: $(print -r -- "$APPLICATIONS_LIST" | wc -l | tr -d ' ')"
else
    print_warning "No macOS applications were found."
fi

print
print_info "[2/9] Homebrew formulae"
if command_exists brew; then
    if ! FORMULAE_LIST="$(brew list --formula --versions 2>/dev/null)"; then
        print_error "Could not list Homebrew formulae."
        exit 1
    fi
    if [[ -n "$FORMULAE_LIST" ]]; then
        print -r -- "$FORMULAE_LIST" | sort
        print_success "Total formulae: $(print -r -- "$FORMULAE_LIST" | wc -l | tr -d ' ')"
    else
        print_warning "No Homebrew formulae installed."
    fi
else
    print_warning "Homebrew is not installed or is not available in PATH."
fi

print
print_info "[3/9] Homebrew casks"
if command_exists brew; then
    if ! CASKS_LIST="$(brew list --cask --versions 2>/dev/null)"; then
        print_error "Could not list Homebrew casks."
        exit 1
    fi
    if [[ -n "$CASKS_LIST" ]]; then
        print -r -- "$CASKS_LIST" | sort
        print_success "Total casks: $(print -r -- "$CASKS_LIST" | wc -l | tr -d ' ')"
    else
        print_warning "No Homebrew casks installed."
    fi
else
    print_warning "Homebrew is not installed or is not available in PATH."
fi

print
print_info "[4/9] PATH directories"
PATH_DIRECTORIES=()
typeset -A SEEN_PATH_DIRECTORIES
for path_directory in ${(s.:.)PATH}; do
    [[ -z "$path_directory" || -n "${SEEN_PATH_DIRECTORIES[$path_directory]:-}" ]] && continue
    SEEN_PATH_DIRECTORIES[$path_directory]=1
    PATH_DIRECTORIES+=("$path_directory")
done

for path_directory in "${PATH_DIRECTORIES[@]}"; do
    if [[ -d "$path_directory" ]]; then
        print -r -- "  [available] $path_directory"
    else
        print_warning "  [missing]   $path_directory"
    fi
done
print_success "Total PATH directories: ${#PATH_DIRECTORIES[@]}"

print
print_info "[5/9] Executables available in PATH"
rehash
PATH_COMMANDS="$(print -rl -- ${(k)commands} | sort)"
if [[ -n "$PATH_COMMANDS" ]]; then
    while IFS= read -r command_name; do
        printf '  %-32s %s\n' "$command_name" "${commands[$command_name]}"
    done <<< "$PATH_COMMANDS"
    print_success "Total commands in PATH: $(print -r -- "$PATH_COMMANDS" | wc -l | tr -d ' ')"
else
    print_warning "No executable commands were found in PATH."
fi

print
print_info "[6/9] macOS package receipts"
if ! PACKAGE_RECEIPTS="$(pkgutil --pkgs 2>/dev/null | sort)"; then
    print_error "Could not list macOS package receipts."
    exit 1
fi
if [[ -n "$PACKAGE_RECEIPTS" ]]; then
    print -r -- "$PACKAGE_RECEIPTS"
    print_success "Total package receipts: $(print -r -- "$PACKAGE_RECEIPTS" | wc -l | tr -d ' ')"
else
    print_warning "No macOS package receipts were found."
fi

print
print_info "[7/9] Selected command versions"
print -r -- "  PATH: $PATH"
for tool_name in brew git node npm pnpm python3 ruby swift clang docker kubectl; do
    if command_exists "$tool_name"; then
        tool_path="$(command -v "$tool_name")"
        if [[ "$tool_name" == "kubectl" ]]; then
            tool_version="$(kubectl version --client 2>/dev/null | sed -n '1p')"
            [[ -z "$tool_version" ]] && tool_version="$(kubectl version --client=true 2>/dev/null | sed -n '1p')"
            [[ -z "$tool_version" ]] && tool_version="$(kubectl version 2>/dev/null | sed -n '1p')"
        else
            tool_version="$("$tool_name" --version 2>/dev/null | sed -n '1p')"
        fi
        [[ -z "$tool_version" ]] && tool_version="Version unavailable"
        printf '  %-12s %-36s %s\n' "$tool_name" "$tool_version" "$tool_path"
    fi
done

if [[ -x /usr/bin/git ]]; then
    system_git_version="$(/usr/bin/git --version 2>/dev/null)"
    printf '  %-12s %-36s %s\n' "system git" "$system_git_version" "/usr/bin/git"
fi

print
print_info "[8/9] Global Node.js packages"
for package_manager in npm pnpm; do
    if command_exists "$package_manager"; then
        print -r -- "  --- $package_manager ---"
        if ! "$package_manager" list --global --depth=0 2>&1 | sed 's/^/  /'; then
            print_warning "Could not list global $package_manager packages."
        fi
    else
        print_warning "$package_manager is not installed or is not available in PATH."
    fi
done

print
print_info "[9/9] Python packages"
if command_exists python3; then
    if python3 -m pip --version >/dev/null 2>&1; then
        python3 -m pip list 2>&1 | sed 's/^/  /'
    else
        print_warning "pip is not available for the active Python 3 installation."
    fi
else
    print_warning "Python 3 is not installed or is not available in PATH."
fi

print
print_success "Installed software inventory complete."
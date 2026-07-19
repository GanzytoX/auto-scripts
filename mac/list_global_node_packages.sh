#!/bin/zsh

SCRIPT_DIR="${0:A:h}"
SCRIPT_NAME="${0:t}"
source "$SCRIPT_DIR/lib/common.zsh" || exit 1

CHECK_NPM=1
CHECK_PNPM=1
FILTER_SELECTED=0
SUCCESS_COUNT=0

usage() {
    print -r -- "Usage: $SCRIPT_NAME [--npm] [--pnpm]"
    print -r -- "  --npm   List only global npm packages."
    print -r -- "  --pnpm  List only global pnpm packages."
}

while (( $# > 0 )); do
    case "$1" in
        --npm)
            if (( ! FILTER_SELECTED )); then
                CHECK_NPM=0
                CHECK_PNPM=0
                FILTER_SELECTED=1
            fi
            CHECK_NPM=1
        ;;
        --pnpm)
            if (( ! FILTER_SELECTED )); then
                CHECK_NPM=0
                CHECK_PNPM=0
                FILTER_SELECTED=1
            fi
            CHECK_PNPM=1
        ;;
        -h|--help) usage; exit 0 ;;
        *) print_error "Unknown option: $1"; usage >&2; exit 2 ;;
    esac
    shift
done

parse_package_json() {
    if command_exists node && node --version >/dev/null 2>&1; then
        node -e '
const fs = require("fs");
const input = JSON.parse(fs.readFileSync(0, "utf8"));
const roots = Array.isArray(input) ? input : [input];
const packages = new Map();

for (const root of roots) {
  for (const [name, metadata] of Object.entries(root?.dependencies ?? {})) {
    packages.set(name, metadata?.version ?? "unknown");
  }
}

for (const [name, version] of [...packages].sort(([left], [right]) => left.localeCompare(right))) {
  process.stdout.write(`${name}\t${version}\n`);
}
'
        return $?
    fi

    if command_exists python3 && python3 --version >/dev/null 2>&1; then
        python3 -c '
import json
import sys

payload = json.load(sys.stdin)
roots = payload if isinstance(payload, list) else [payload]
packages = {}

for root in roots:
    if not isinstance(root, dict):
        continue
    for name, metadata in root.get("dependencies", {}).items():
        version = metadata.get("version", "unknown") if isinstance(metadata, dict) else "unknown"
        packages[name] = version

for name in sorted(packages, key=str.casefold):
    print(f"{name}\t{packages[name]}")
'
        return $?
    fi

    print_error "Node.js or Python 3 is required to parse package information."
    return 1
}

query_global_packages() {
    local manager="$1"
    local display_name="${(U)manager}"
    local manager_version
    local global_path
    local package_json
    local packages
    local query_error
    local error_file
    local query_status
    local count=0

    print_info "--- $display_name global packages ---"

    if ! command_exists "$manager"; then
        print_warning "$display_name is not installed or is not available in PATH."
        print
        return 1
    fi

    manager_version="$("$manager" --version 2>/dev/null)"
    if (( $? != 0 )) || [[ -z "$manager_version" ]]; then
        print_error "$display_name is present but its executable is not working."
        print -r -- "Executable: $(command -v "$manager")" >&2
        print
        return 1
    fi

    if [[ "$manager" == "npm" ]]; then
        global_path="$(npm root --global 2>/dev/null)"
    else
        global_path="$(pnpm root --global 2>/dev/null)"
    fi

    print -r -- "${BLUE}Version:${NC} $manager_version"
    if [[ -n "$global_path" ]]; then
        print -r -- "${BLUE}Global directory:${NC} $global_path"
    fi

    error_file="$(mktemp "${TMPDIR:-/tmp}/global-packages.XXXXXX")" || return 1
    package_json="$("$manager" list --global --depth=0 --json 2>"$error_file")"
    query_status=$?
    query_error="$(<"$error_file")"
    rm -f "$error_file"
    if (( query_status != 0 )); then
        print_error "$display_name could not list its global packages."
        [[ -n "$query_error" ]] && print -r -- "$query_error" >&2
        [[ -n "$package_json" ]] && print -r -- "$package_json" >&2
        print
        return 1
    fi

    if [[ -n "$query_error" ]]; then
        print_warning "$display_name reported a warning:"
        print -r -- "$query_error" >&2
    fi

    if ! packages="$(print -rn -- "$package_json" | parse_package_json)"; then
        print_error "$display_name returned package information in an unexpected format."
        print
        return 1
    fi

    if [[ -z "$packages" ]]; then
        print_warning "No global $display_name packages were found."
        print
        (( SUCCESS_COUNT++ ))
        return 0
    fi

    printf '\n  %-42s %s\n' "Package" "Version"
    printf '  %-42s %s\n' "------------------------------------------" "---------------"
    while IFS=$'\t' read -r package_name package_version; do
        printf '  %-42s %s\n' "$package_name" "$package_version"
        (( count++ ))
    done <<< "$packages"

    print_success "Total $display_name packages: $count"
    print
    (( SUCCESS_COUNT++ ))
    return 0
}

clear_screen
print_info "=== Global Node.js Packages ==="
print

(( CHECK_NPM )) && query_global_packages npm
(( CHECK_PNPM )) && query_global_packages pnpm

if (( SUCCESS_COUNT == 0 )); then
    print_error "No package manager could be queried successfully."
    exit 1
fi

print_success "Global package inventory complete."

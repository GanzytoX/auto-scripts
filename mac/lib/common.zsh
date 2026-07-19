#!/bin/zsh

# Shared helpers for the macOS maintenance scripts.

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    readonly GREEN=$'\033[0;32m'
    readonly BLUE=$'\033[0;34m'
    readonly YELLOW=$'\033[1;33m'
    readonly RED=$'\033[0;31m'
    readonly NC=$'\033[0m'
else
    readonly GREEN=''
    readonly BLUE=''
    readonly YELLOW=''
    readonly RED=''
    readonly NC=''
fi

print_info() {
    print -r -- "${BLUE}$*${NC}"
}

print_success() {
    print -r -- "${GREEN}$*${NC}"
}

print_warning() {
    print -r -- "${YELLOW}$*${NC}" >&2
}

print_error() {
    print -r -- "${RED}$*${NC}" >&2
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

clear_screen() {
    if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]]; then
        clear
    fi
}

confirm() {
    local prompt="$1"

    if [[ "${AUTO_YES:-0}" == "1" ]]; then
        return 0
    fi

    if [[ ! -t 0 ]]; then
        return 1
    fi

    printf '%s [y/N] ' "$prompt"
    local answer
    read -r answer
    [[ "$answer" == [yY] || "$answer" == [yY][eE][sS] ]]
}

fetch_url() {
    local url="$1"

    curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 60 \
        --retry 2 \
        "$url"
}

is_valid_version() {
    [[ "$1" =~ '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' ]]
}

version_is_newer() {
    local candidate="$1"
    local current="$2"

    autoload -Uz is-at-least
    ! is-at-least "$candidate" "$current"
}

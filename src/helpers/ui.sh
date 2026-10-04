#!/usr/bin/env bash
# Shared console UI. Source this file; do not execute it.

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    BLUE='\033[0;34m' CYAN='\033[0;36m' BOLD='\033[1m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

info() { printf '%bℹ%b %s\n' "$BLUE" "$RESET" "$*"; }
success() { printf '%b✔%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b⚠%b %s\n' "$YELLOW" "$RESET" "$*"; }
error() { printf '%b✘%b %s\n' "$RED" "$RESET" "$*" >&2; }
die() { error "$@"; exit 1; }

pause() {
    printf '\n'
    read -r -p 'Нажми Enter, чтобы продолжить...' _ || true
}

confirm() {
    local answer
    read -r -p "${1:-Продолжить?} [y/N]: " answer || return 1
    case "$answer" in
        y|Y|yes|YES|д|Д|да|Да|ДА) return 0 ;;
        *) return 1 ;;
    esac
}

clear_screen() {
    if [[ -t 1 && -n "${TERM:-}" && "$TERM" != dumb ]] && command -v clear >/dev/null 2>&1; then
        clear || true
    fi
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            exec sudo -- "$0" "$@"
        fi
        die 'Скрипт необходимо запустить от root.'
    fi
}

ui_header() {
    printf '\n%b┌──────────────────────────────────────────────┐%b\n' "${CYAN}${BOLD}" "$RESET"
    printf '%b│ %-44s │%b\n' "${CYAN}${BOLD}" "$1" "$RESET"
    printf '%b└──────────────────────────────────────────────┘%b\n\n' "${CYAN}${BOLD}" "$RESET"
}

menu_item() {
    printf ' %b%2s)%b %s\n' "${3:-$CYAN}" "$1" "$RESET" "$2"
}

section_title() {
    printf '%b%s%b\n' "$BOLD" "$1" "$RESET"
}

read_menu_choice() {
    read -r -p 'Выбери действие: ' choice
}

bool_text() {
    if [[ "$1" == true ]]; then
        printf '%bВКЛ%b\n' "$GREEN" "$RESET"
    else
        printf '%bВЫКЛ%b\n' "$RED" "$RESET"
    fi
}

yes_no() {
    if [[ "$1" == true ]]; then printf 'Да\n'; else printf 'Нет\n'; fi
}

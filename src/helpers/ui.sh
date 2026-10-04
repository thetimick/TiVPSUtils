#!/usr/bin/env bash
# Shared console UI. Source this file; do not execute it.

if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]]; then
    RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
    BLUE=$'\033[34m' ACCENT=$'\033[35m' BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
    # Lavender palette, with fallbacks for terminals with fewer colors.
    case "${COLORTERM:-}:${TERM:-}" in
        truecolor:*|24bit:*|*:*-direct|*:*truecolor*)
            ACCENT=$'\033[38;2;196;161;241m'
            GREEN=$'\033[38;2;145;215;175m'
            YELLOW=$'\033[38;2;239;199;131m'
            RED=$'\033[38;2;241;148;172m'
            BLUE=$'\033[38;2;145;189;244m'
            ;;
        *:*256color*)
            ACCENT=$'\033[38;5;183m' GREEN=$'\033[38;5;115m'
            YELLOW=$'\033[38;5;222m' RED=$'\033[38;5;211m' BLUE=$'\033[38;5;111m'
            ;;
    esac
else
    RED='' GREEN='' YELLOW='' BLUE='' ACCENT='' BOLD='' DIM='' RESET=''
fi

# Lavender: navigation; green: success; yellow: caution; rose: failure/destruction.
# Muted text: secondary information, exit and cancel. Labels work without color.
info() { printf '%b[INFO]%b %s\n' "$BLUE" "$RESET" "$*"; }
success() { printf '%b[ OK ]%b %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$RESET" "$*"; }
error() { printf '%b[FAIL]%b %s\n' "$RED" "$RESET" "$*" >&2; }
die() { error "$@"; exit 1; }

ui_read() {
    printf '%b%s%b ' "$BOLD" "$1" "$RESET" >&2
    read -r "${2:-REPLY}"
}

pause() {
    printf '\n'
    local reply
    ui_read 'Нажми Enter, чтобы продолжить...' reply || true
}

confirm() {
    local answer
    ui_read "${1:-Продолжить?} [y/N]:" answer || return 1
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
    printf '\n%bTiVPSUtils%b\n' "$DIM" "$RESET"
    printf '%b%s%b\n' "${ACCENT}${BOLD}" "$1" "$RESET"
    separator
    printf '\n'
}

separator() {
    printf '%b──────────────────────────────────────────────%b\n' "$DIM" "$RESET"
}

ui_field() {
    printf '  %b%s%b %s\n' "$DIM" "$1" "$RESET" "$2"
}

ui_command() {
    if [[ -n "${2:-}" ]]; then
        printf '  %b%-20s%b %s\n' "${ACCENT}${BOLD}" "$1" "$RESET" "$2"
    else
        printf '  %b%s%b\n' "${ACCENT}${BOLD}" "$1" "$RESET"
    fi
}

menu_item() {
    printf ' %b%2s)%b %b%s%b\n' "${3:-$ACCENT}${BOLD}" "$1" "$RESET" "$BOLD" "$2" "$RESET"
}

section_title() {
    printf '%b%s%b\n' "$BOLD" "$1" "$RESET"
}

read_menu_choice() {
    ui_read 'Выбери действие:' choice
}

bool_text() {
    if [[ "$1" == true ]]; then
        printf '%bВКЛ%b\n' "$GREEN" "$RESET"
    else
        printf '%bВЫКЛ%b\n' "$DIM" "$RESET"
    fi
}

yes_no() {
    if [[ "$1" == true ]]; then printf 'Да\n'; else printf 'Нет\n'; fi
}

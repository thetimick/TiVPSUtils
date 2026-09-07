#!/usr/bin/env bash

set -Eeuo pipefail

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────

REPO="thetimick/TiVPSUtils"
BRANCH="main"

INSTALL_DIR="/opt/TiVPSUtils"
SCRIPTS_DIR="${INSTALL_DIR}/src"

PROFILE_FILE="/etc/profile.d/tivpsutils.sh"

ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

# ──────────────────────────────────────────────
# Colors
# ──────────────────────────────────────────────

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'

    RED=$'\033[31m'
    GREEN=$'\033[32m'
    YELLOW=$'\033[33m'
    BLUE=$'\033[34m'
    MAGENTA=$'\033[35m'
    CYAN=$'\033[36m'
else
    RESET=""
    BOLD=""
    DIM=""

    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    MAGENTA=""
    CYAN=""
fi

# ──────────────────────────────────────────────
# Output
# ──────────────────────────────────────────────

info() {
    printf "%b[INFO]%b %s\n" \
        "${BLUE}${BOLD}" \
        "$RESET" \
        "$*"
}

success() {
    printf "%b[ OK ]%b %s\n" \
        "${GREEN}${BOLD}" \
        "$RESET" \
        "$*"
}

warn() {
    printf "%b[WARN]%b %s\n" \
        "${YELLOW}${BOLD}" \
        "$RESET" \
        "$*"
}

error() {
    printf "%b[FAIL]%b %s\n" \
        "${RED}${BOLD}" \
        "$RESET" \
        "$*" >&2
}

title() {
    printf "%b%s%b\n" \
        "${CYAN}${BOLD}" \
        "$*" \
        "$RESET"
}

command_text() {
    printf "%b%s%b" \
        "$CYAN" \
        "$*" \
        "$RESET"
}

separator() {
    printf "%b──────────────────────────────────────────────%b\n" \
        "$DIM" \
        "$RESET"
}

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

require_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Операция требует root."
        printf "\n"
        printf "Запусти команду через sudo или от пользователя root.\n"
        exit 1
    fi
}

require_tar() {
    if ! command -v tar >/dev/null 2>&1; then
        error "tar не установлен."
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
        return
    fi

    if command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url"
        return
    fi

    error "Требуется curl или wget."
    exit 1
}

confirm() {
    local message="$1"
    local answer

    printf "%b%s%b %b[y/N]%b: " \
        "$YELLOW" \
        "$message" \
        "$RESET" \
        "$DIM" \
        "$RESET"

    read -r answer

    case "$answer" in
        y|Y|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

get_metadata() {
    local script="$1"
    local key="$2"

    sed -n \
        "s/^#[[:space:]]*${key}[[:space:]]*=[[:space:]]*//p" \
        "$script" \
        | head -n 1
}

get_command_name() {
    local script="$1"
    local filename
    local name

    filename="$(basename "$script")"
    name="$(get_metadata "$script" "TI_ALIAS")"

    if [[ -z "$name" ]]; then
        name="${filename%.sh}"

        # Backward compatibility:
        # updater.sh -> tiupdate
        if [[ "$name" == "updater" ]]; then
            name="update"
        fi
    fi

    if [[ ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        return 1
    fi

    printf "%s" "$name"
}

get_description() {
    local script="$1"
    local description

    description="$(get_metadata "$script" "TI_DESCRIPTION")"

    if [[ -z "$description" ]]; then
        description="$(basename "$script")"
    fi

    printf "%s" "$description"
}

is_installed() {
    [[ -f "${INSTALL_DIR}/install.sh" ]]
}

is_running_installed_manager() {
    local source_path="${BASH_SOURCE[0]:-}"

    [[ -n "$source_path" ]] || return 1

    local resolved_source
    resolved_source="$(readlink -f "$source_path" 2>/dev/null || true)"

    [[ "$resolved_source" == "${INSTALL_DIR}/install.sh" ]]
}

# ──────────────────────────────────────────────
# Aliases
# ──────────────────────────────────────────────

generate_aliases() {
    require_root

    if ! is_installed; then
        error "TiVPSUtils не установлен."
        return 1
    fi

    info "Обновление aliases..."

    local temp_file
    temp_file="$(mktemp)"

    cat > "$temp_file" <<EOF
# TiVPSUtils
# Generated automatically by TiVPSUtils Manager.
# Do not edit manually.

alias tiinstall='${INSTALL_DIR}/install.sh'
EOF

    declare -A used_aliases
    used_aliases["tiinstall"]=1

    if [[ -d "$SCRIPTS_DIR" ]]; then
        while IFS= read -r -d '' script; do
            local command_name
            local alias_name

            if ! command_name="$(get_command_name "$script")"; then
                warn "Пропущен $(basename "$script"): некорректный TI_ALIAS."
                continue
            fi

            alias_name="ti${command_name}"

            if [[ -n "${used_aliases[$alias_name]:-}" ]]; then
                warn "Пропущен ${alias_name}: alias уже существует."
                continue
            fi

            used_aliases["$alias_name"]=1

            printf "alias %s='%s'\n" \
                "$alias_name" \
                "$script" \
                >> "$temp_file"

        done < <(
            find "$SCRIPTS_DIR" \
                -maxdepth 1 \
                -type f \
                -name "*.sh" \
                -print0 \
                | sort -z
        )
    fi

    install -m 0644 "$temp_file" "$PROFILE_FILE"
    rm -f "$temp_file"

    success "Aliases обновлены."
}

show_aliases() {
    printf "\n"
    title "Aliases TiVPSUtils"
    separator
    printf "\n"

    if [[ ! -f "$PROFILE_FILE" ]]; then
        warn "Aliases TiVPSUtils не установлены."
        printf "\n"
        return
    fi

    local found=false

    while IFS= read -r line; do
        if [[ "$line" =~ ^alias[[:space:]]+([^=]+)=\'(.*)\'$ ]]; then
            local alias_name="${BASH_REMATCH[1]}"
            local alias_path="${BASH_REMATCH[2]}"

            printf "  %b%-20s%b %s\n" \
                "$CYAN" \
                "$alias_name" \
                "$RESET" \
                "$alias_path"

            found=true
        fi
    done < "$PROFILE_FILE"

    if [[ "$found" == false ]]; then
        warn "Aliases не найдены."
    fi

    printf "\n"
}

clear_aliases() {
    require_root

    if [[ ! -f "$PROFILE_FILE" ]]; then
        warn "Aliases уже отсутствуют."
        return
    fi

    rm -f "$PROFILE_FILE"

    success "Aliases TiVPSUtils удалены."

    printf "\n"
    warn "Aliases, уже загруженные в текущую shell-сессию,"
    printf "останутся активными до повторного входа или перезапуска shell.\n"

    printf "\n"
    printf "Менеджер всё ещё можно запустить напрямую:\n"
    printf "  %b%s/install.sh%b\n" \
        "$CYAN" \
        "$INSTALL_DIR" \
        "$RESET"
}

# ──────────────────────────────────────────────
# Commands
# ──────────────────────────────────────────────

list_commands() {
    printf "\n"
    title "Доступные команды TiVPSUtils"
    separator
    printf "\n"

    printf "  %b%-20s%b %s\n" \
        "$CYAN" \
        "tiinstall" \
        "$RESET" \
        "Менеджер TiVPSUtils"

    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        printf "\n"
        warn "Скрипты не установлены."
        printf "\n"
        return
    fi

    while IFS= read -r -d '' script; do
        local command_name
        local description

        if ! command_name="$(get_command_name "$script")"; then
            continue
        fi

        description="$(get_description "$script")"

        printf "  %b%-20s%b %s\n" \
            "$CYAN" \
            "ti${command_name}" \
            "$RESET" \
            "$description"

    done < <(
        find "$SCRIPTS_DIR" \
            -maxdepth 1 \
            -type f \
            -name "*.sh" \
            -print0 \
            | sort -z
    )

    printf "\n"
}

# ──────────────────────────────────────────────
# Install / Update
# ──────────────────────────────────────────────

install_latest() (
    require_root
    require_tar

    local temp_dir
    local archive_path
    local extracted_dir
    local staging_dir=""
    local old_dir=""

    temp_dir="$(mktemp -d)"
    archive_path="${temp_dir}/repo.tar.gz"
    extracted_dir="${temp_dir}/repo"

    cleanup_install() {
        if [[ -n "${staging_dir:-}" && -d "${staging_dir:-}" ]]; then
            rm -rf "$staging_dir"
        fi

        if [[ -n "${temp_dir:-}" && -d "${temp_dir:-}" ]]; then
            rm -rf "$temp_dir"
        fi
    }

    trap cleanup_install EXIT

    printf "\n"

    info "Загрузка TiVPSUtils..."
    download_file "$ARCHIVE_URL" "$archive_path"

    info "Распаковка архива..."

    mkdir -p "$extracted_dir"

    tar \
        -xzf "$archive_path" \
        -C "$extracted_dir" \
        --strip-components=1

    if [[ ! -f "${extracted_dir}/install.sh" ]]; then
        error "install.sh отсутствует в репозитории."
        exit 1
    fi

    if [[ ! -d "${extracted_dir}/src" ]]; then
        warn "Директория src отсутствует в репозитории."
    fi

    info "Подготовка файлов..."

    staging_dir="$(mktemp -d "${INSTALL_DIR}.new.XXXXXX")"

    cp -a "${extracted_dir}/." "$staging_dir/"

    find "$staging_dir" \
        -type f \
        -name "*.sh" \
        -exec chmod 0755 {} \;

    info "Установка в ${INSTALL_DIR}..."

    if [[ -d "$INSTALL_DIR" ]]; then
        old_dir="${INSTALL_DIR}.old.$$"

        rm -rf "$old_dir"
        mv "$INSTALL_DIR" "$old_dir"
    fi

    if ! mv "$staging_dir" "$INSTALL_DIR"; then
        error "Не удалось установить TiVPSUtils."

        if [[ -n "$old_dir" && -d "$old_dir" ]]; then
            warn "Восстановление предыдущей версии..."
            mv "$old_dir" "$INSTALL_DIR"
        fi

        exit 1
    fi

    staging_dir=""

    if [[ -n "$old_dir" && -d "$old_dir" ]]; then
        rm -rf "$old_dir"
    fi

    generate_aliases

    printf "\n"
    success "TiVPSUtils успешно установлен."

    printf "\n"
    printf "Путь: %b%s%b\n" \
        "$CYAN" \
        "$INSTALL_DIR" \
        "$RESET"

    list_commands

    printf "Для применения aliases в текущей shell-сессии:\n"
    printf "\n"
    printf "  %bsource %s%b\n" \
        "$CYAN" \
        "$PROFILE_FILE" \
        "$RESET"

    printf "\n"
)

# ──────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────

uninstall_all() {
    require_root

    local force="${1:-false}"

    if [[ "$force" != "true" ]]; then
        printf "\n"

        if ! confirm "Полностью удалить TiVPSUtils?"; then
            warn "Удаление отменено."
            return
        fi
    fi

    printf "\n"
    info "Удаление aliases..."

    rm -f "$PROFILE_FILE"

    info "Удаление ${INSTALL_DIR}..."

    # Если менеджер запущен из INSTALL_DIR, Bash уже держит
    # открытый скрипт, поэтому удалить каталог безопасно.
    rm -rf "$INSTALL_DIR"

    printf "\n"
    success "TiVPSUtils полностью удалён."

    printf "\n"
    warn "Aliases текущей shell-сессии могут оставаться активными"
    printf "до повторного входа или перезапуска shell.\n"

    printf "\n"
}

# ──────────────────────────────────────────────
# Header
# ──────────────────────────────────────────────

show_header() {
    printf "\n"
    printf "%b┌──────────────────────────────────────────────┐%b\n" \
        "${CYAN}${BOLD}" \
        "$RESET"

    printf "%b│              TiVPSUtils Manager              │%b\n" \
        "${CYAN}${BOLD}" \
        "$RESET"

    printf "%b└──────────────────────────────────────────────┘%b\n" \
        "${CYAN}${BOLD}" \
        "$RESET"
}

# ──────────────────────────────────────────────
# Menu
# ──────────────────────────────────────────────

show_menu() {
    while true; do
        show_header

        printf "\n"

        printf "  %b1)%b Установить / обновить TiVPSUtils\n" \
            "$CYAN" "$RESET"

        printf "  %b2)%b Показать доступные команды\n" \
            "$CYAN" "$RESET"

        printf "  %b3)%b Показать aliases\n" \
            "$CYAN" "$RESET"

        printf "  %b4)%b Пересоздать aliases\n" \
            "$CYAN" "$RESET"

        printf "  %b5)%b Очистить aliases\n" \
            "$YELLOW" "$RESET"

        printf "  %b6)%b Полностью удалить TiVPSUtils\n" \
            "$RED" "$RESET"

        printf "\n"

        printf "  %b0)%b Выход\n" \
            "$DIM" "$RESET"

        printf "\n"

        local choice

        printf "%bВыбери действие%b: " \
            "$BOLD" \
            "$RESET"

        read -r choice

        case "$choice" in
            1)
                install_latest
                ;;
            2)
                list_commands
                ;;
            3)
                show_aliases
                ;;
            4)
                printf "\n"
                generate_aliases
                printf "\n"
                ;;
            5)
                printf "\n"

                if confirm "Удалить все aliases TiVPSUtils?"; then
                    printf "\n"
                    clear_aliases
                else
                    warn "Операция отменена."
                fi
                ;;
            6)
                uninstall_all
                return
                ;;
            0)
                printf "\n"
                return
                ;;
            *)
                printf "\n"
                error "Неизвестный пункт: ${choice}"
                ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────

show_help() {
    show_header

    printf "\n"
    title "Использование"
    separator
    printf "\n"

    printf "  %btiinstall%b\n" \
        "$CYAN" "$RESET"
    printf "      Открыть интерактивный менеджер.\n"

    printf "\n"

    printf "  %btiinstall update%b\n" \
        "$CYAN" "$RESET"
    printf "      Скачать и установить последнюю версию.\n"

    printf "\n"

    printf "  %btiinstall list%b\n" \
        "$CYAN" "$RESET"
    printf "      Показать доступные команды.\n"

    printf "\n"

    printf "  %btiinstall aliases%b\n" \
        "$CYAN" "$RESET"
    printf "      Показать установленные aliases.\n"

    printf "\n"

    printf "  %btiinstall rebuild-aliases%b\n" \
        "$CYAN" "$RESET"
    printf "      Пересоздать aliases.\n"

    printf "\n"

    printf "  %btiinstall clear-aliases%b\n" \
        "$CYAN" "$RESET"
    printf "      Удалить aliases TiVPSUtils.\n"

    printf "\n"

    printf "  %btiinstall uninstall%b\n" \
        "$CYAN" "$RESET"
    printf "      Полностью удалить TiVPSUtils.\n"

    printf "\n"

    printf "  %btiinstall uninstall --yes%b\n" \
        "$CYAN" "$RESET"
    printf "      Удалить TiVPSUtils без подтверждения.\n"

    printf "\n"

    printf "  %btiinstall help%b\n" \
        "$CYAN" "$RESET"
    printf "      Показать справку.\n"

    printf "\n"
}

# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────

main() {
    local command="${1:-}"

    # При запуске через:
    #
    # curl .../install.sh | sudo bash
    #
    # автоматически запускаем установку.
    #
    # При запуске установленного:
    #
    # tiinstall
    #
    # открываем менеджер.

    if [[ -z "$command" ]]; then
        if ! is_running_installed_manager; then
            install_latest
            return
        fi

        show_menu
        return
    fi

    case "$command" in
        install|update|upgrade)
            install_latest
            ;;

        list|commands)
            list_commands
            ;;

        aliases)
            show_aliases
            ;;

        rebuild-aliases)
            printf "\n"
            generate_aliases
            printf "\n"
            ;;

        clear-aliases)
            printf "\n"
            clear_aliases
            printf "\n"
            ;;

        uninstall|remove)
            if [[ "${2:-}" == "--yes" ]]; then
                uninstall_all true
            else
                uninstall_all false
            fi
            ;;

        help|-h|--help)
            show_help
            ;;

        *)
            error "Неизвестная команда: ${command}"
            printf "\n"
            show_help
            exit 1
            ;;
    esac
}

main "$@"

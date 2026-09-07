#!/usr/bin/env bash

set -Eeuo pipefail

REPO="thetimick/TiVPSUtils"
BRANCH="main"

INSTALL_DIR="/opt/TiVPSUtils"
SCRIPTS_DIR="${INSTALL_DIR}/src"

PROFILE_FILE="/etc/profile.d/tivpsutils.sh"

ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Ошибка: операция требует root."
        echo
        echo "Запусти команду от root."
        exit 1
    fi
}

download_file() {
    local url="$1"
    local output="$2"

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$output" "$url"
    else
        echo "Ошибка: требуется curl или wget."
        exit 1
    fi
}

confirm() {
    local message="$1"

    read -r -p "${message} [y/N]: " answer

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

        # Backward compatibility
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
        echo "TiVPSUtils не установлен."
        return 1
    fi

    echo "Обновление aliases..."

    local temp_file
    temp_file="$(mktemp)"

    cat > "$temp_file" <<EOF
# TiVPSUtils
# Generated automatically by TiVPSUtils manager.
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
                echo "Пропущен $(basename "$script"): некорректный TI_ALIAS."
                continue
            fi

            alias_name="ti${command_name}"

            if [[ -n "${used_aliases[$alias_name]:-}" ]]; then
                echo "Пропущен ${alias_name}: alias уже существует."
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

    echo "Aliases обновлены."
    echo
    echo "Для применения в текущей shell-сессии:"
    echo "  source ${PROFILE_FILE}"
}

show_aliases() {
    if [[ ! -f "$PROFILE_FILE" ]]; then
        echo "Aliases TiVPSUtils не установлены."
        return
    fi

    echo
    echo "Aliases:"
    echo

    grep '^alias ' "$PROFILE_FILE" || true
}

clear_aliases() {
    require_root

    if [[ ! -f "$PROFILE_FILE" ]]; then
        echo "Aliases уже отсутствуют."
        return
    fi

    rm -f "$PROFILE_FILE"

    echo "Aliases TiVPSUtils удалены."
    echo
    echo "Важно: aliases, уже загруженные в текущую shell-сессию,"
    echo "останутся до повторного входа или перезапуска shell."
    echo
    echo "Менеджер всё ещё доступен напрямую:"
    echo "  ${INSTALL_DIR}/install.sh"
}

# ──────────────────────────────────────────────
# Commands
# ──────────────────────────────────────────────

list_commands() {
    echo
    echo "Доступные команды TiVPSUtils:"
    echo

    printf "  %-20s %s\n" \
        "tiinstall" \
        "Менеджер TiVPSUtils"

    if [[ ! -d "$SCRIPTS_DIR" ]]; then
        echo
        echo "Скрипты не установлены."
        return
    fi

    while IFS= read -r -d '' script; do
        local command_name
        local description

        if ! command_name="$(get_command_name "$script")"; then
            continue
        fi

        description="$(get_description "$script")"

        printf "  %-20s %s\n" \
            "ti${command_name}" \
            "$description"

    done < <(
        find "$SCRIPTS_DIR" \
            -maxdepth 1 \
            -type f \
            -name "*.sh" \
            -print0 \
            | sort -z
    )

    echo
}

# ──────────────────────────────────────────────
# Install / Update
# ──────────────────────────────────────────────

install_latest() {
    require_root

    if ! command -v tar >/dev/null 2>&1; then
        echo "Ошибка: tar не установлен."
        exit 1
    fi

    local temp_dir
    local archive_path
    local extracted_dir
    local staging_dir
    local old_dir=""

    temp_dir="$(mktemp -d)"
    archive_path="${temp_dir}/repo.tar.gz"
    extracted_dir="${temp_dir}/repo"

    cleanup_install() {
        rm -rf "$temp_dir"

        if [[ -n "${staging_dir:-}" && -d "${staging_dir:-}" ]]; then
            rm -rf "$staging_dir"
        fi
    }

    trap cleanup_install RETURN

    echo
    echo "Загрузка TiVPSUtils..."

    download_file "$ARCHIVE_URL" "$archive_path"

    mkdir -p "$extracted_dir"

    tar \
        -xzf "$archive_path" \
        -C "$extracted_dir" \
        --strip-components=1

    if [[ ! -f "${extracted_dir}/install.sh" ]]; then
        echo "Ошибка: install.sh отсутствует в репозитории."
        return 1
    fi

    staging_dir="$(mktemp -d "${INSTALL_DIR}.new.XXXXXX")"

    cp -a "${extracted_dir}/." "$staging_dir/"

    find "$staging_dir" \
        -type f \
        -name "*.sh" \
        -exec chmod 0755 {} \;

    if [[ -d "$INSTALL_DIR" ]]; then
        old_dir="${INSTALL_DIR}.old.$$"

        rm -rf "$old_dir"
        mv "$INSTALL_DIR" "$old_dir"
    fi

    mv "$staging_dir" "$INSTALL_DIR"
    staging_dir=""

    if [[ -n "$old_dir" ]]; then
        rm -rf "$old_dir"
    fi

    generate_aliases

    echo
    echo "TiVPSUtils успешно установлен."
    echo
    echo "Путь:"
    echo "  ${INSTALL_DIR}"
    echo

    list_commands
}

# ──────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────

uninstall_all() {
    require_root

    local force="${1:-false}"

    if [[ "$force" != "true" ]]; then
        if ! confirm "Полностью удалить TiVPSUtils?"; then
            echo "Отменено."
            return
        fi
    fi

    echo
    echo "Удаление TiVPSUtils..."

    rm -f "$PROFILE_FILE"
    rm -rf "$INSTALL_DIR"

    echo
    echo "TiVPSUtils полностью удалён."
    echo
    echo "Aliases исчезнут из текущей shell-сессии"
    echo "после повторного входа или перезапуска shell."
}

# ──────────────────────────────────────────────
# Menu
# ──────────────────────────────────────────────

show_menu() {
    while true; do
        echo
        echo "┌──────────────────────────────────────────────┐"
        echo "│               TiVPSUtils Manager             │"
        echo "└──────────────────────────────────────────────┘"
        echo
        echo "  1) Установить / обновить TiVPSUtils"
        echo "  2) Показать доступные команды"
        echo "  3) Показать aliases"
        echo "  4) Пересоздать aliases"
        echo "  5) Очистить aliases"
        echo "  6) Полностью удалить TiVPSUtils"
        echo
        echo "  0) Выход"
        echo

        read -r -p "Выбери действие: " choice

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
                generate_aliases
                ;;
            5)
                if confirm "Удалить все aliases TiVPSUtils?"; then
                    clear_aliases
                fi
                ;;
            6)
                uninstall_all
                return
                ;;
            0)
                return
                ;;
            *)
                echo "Неизвестный пункт."
                ;;
        esac
    done
}

# ──────────────────────────────────────────────
# CLI
# ──────────────────────────────────────────────

show_help() {
    cat <<EOF
TiVPSUtils Manager

Использование:

  tiinstall
      Открыть интерактивное меню.

  tiinstall update
      Скачать и установить последнюю версию TiVPSUtils.

  tiinstall list
      Показать доступные команды.

  tiinstall aliases
      Показать установленные aliases.

  tiinstall rebuild-aliases
      Пересоздать aliases.

  tiinstall clear-aliases
      Удалить aliases.

  tiinstall uninstall
      Полностью удалить TiVPSUtils.

  tiinstall uninstall --yes
      Удалить TiVPSUtils без подтверждения.

  tiinstall help
      Показать эту справку.
EOF
}

main() {
    local command="${1:-}"

    if [[ -z "$command" ]]; then
        # curl ... | sudo bash
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
            generate_aliases
            ;;

        clear-aliases)
            clear_aliases
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
            echo "Неизвестная команда: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

main "$@"
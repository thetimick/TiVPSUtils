#!/usr/bin/env bash

set -Eeuo pipefail

# Resolve helpers relative to this script, independently of the working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/ui.sh
source "${SCRIPT_DIR}/helpers/ui.sh"
# shellcheck source=helpers/update.sh
source "${SCRIPT_DIR}/helpers/update.sh"

main_menu() {
    local choice
    while true; do
        clear_screen
        show_header

        section_title "Управление:"
        echo
        menu_item "1" "Показать состояние"
        echo
        menu_item "2" "Включить / выключить автообновления"
        menu_item "3" "Изменить время обновления"
        menu_item "4" "Изменить время запуска apt update"
        echo
        menu_item "5" "Включить / выключить обычные Ubuntu updates"
        echo
        menu_item "6" "Включить / выключить автоматический reboot"
        menu_item "7" "Разрешить / запретить reboot с активными users"
        menu_item "8" "Изменить время reboot"
        echo
        menu_item "9" "Включить / выключить очистку зависимостей"
        menu_item "10" "Включить / выключить очистку старых ядер"
        menu_item "11" "Включить / выключить Persistent timers"
        menu_item "12" "Изменить период autoclean"
        echo
        menu_item "13" "Применить конфигурацию заново"
        echo
        menu_item "14" "Dry-run обновления"
        menu_item "15" "Показать лог unattended-upgrades"
        menu_item "16" "Показать dpkg log"
        menu_item "17" "Показать эффективный APT config"
        menu_item "18" "Выполнить apt update сейчас"
        echo
        menu_item "19" "Удалить настройки менеджера" "$RED"
        echo
        menu_item "0" "Выход" "$YELLOW"
        echo

        read_menu_choice || return 0

        case "$choice" in
            1)
                show_status
                ;;

            2)
                toggle_auto_updates
                ;;

            3)
                change_upgrade_time
                ;;

            4)
                change_package_list_advance
                ;;

            5)
                toggle_regular_updates
                ;;

            6)
                toggle_auto_reboot
                ;;

            7)
                toggle_reboot_with_users
                ;;

            8)
                change_reboot_time
                ;;

            9)
                toggle_remove_dependencies
                ;;

            10)
                toggle_remove_kernels
                ;;

            11)
                toggle_persistent
                ;;

            12)
                change_autoclean_days
                ;;

            13)
                apply_config
                pause
                ;;

            14)
                dry_run
                ;;

            15)
                show_logs
                ;;

            16)
                show_dpkg_logs
                ;;

            17)
                show_effective_config
                ;;

            18)
                manual_apt_update
                ;;

            19)
                remove_manager_config
                ;;

            0)
                exit 0
                ;;

            *)
                echo
                error "Неизвестный пункт."
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

require_root "$@"
require_ubuntu

initialize_config

main_menu

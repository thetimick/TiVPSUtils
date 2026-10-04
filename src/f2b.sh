#!/usr/bin/env bash

set -Eeuo pipefail

# Resolve helpers relative to this script, independently of the working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers/ui.sh
source "${SCRIPT_DIR}/helpers/ui.sh"
# shellcheck source=helpers/f2b.sh
source "${SCRIPT_DIR}/helpers/f2b.sh"

main_menu() {
    local choice

    while true; do

        clear_screen
        show_header

        section_title "Управление:"
        echo

        menu_item "1" "Установить Fail2ban"
        echo
        menu_item "2" "Статус"
        menu_item "3" "Показать jail"
        menu_item "4" "Показать заблокированные IP"
        echo
        menu_item "5" "Заблокировать IP"
        menu_item "6" "Разблокировать IP"
        echo
        menu_item "7" "Последние события Fail2ban"
        menu_item "8" "Последние неудачные SSH-входы"
        echo
        menu_item "9" "Настроить SSH jail"
        menu_item "10" "Показать SSH-конфиг"
        echo
        menu_item "11" "Добавить IP в whitelist"
        menu_item "12" "Показать whitelist"
        echo
        menu_item "13" "Перезапустить Fail2ban"
        echo
        menu_item "14" "Удалить Fail2ban" "$RED"
        echo
        menu_item "0" "Выход" "$YELLOW"
        echo

        read_menu_choice || return 0

        case "$choice" in

            1)
                install_fail2ban
                ;;

            2)
                show_status
                ;;

            3)
                show_jails
                ;;

            4)
                show_banned_ips
                ;;

            5)
                ban_ip
                ;;

            6)
                unban_ip
                ;;

            7)
                show_recent_events
                ;;

            8)
                show_failed_ssh
                ;;

            9)
                configure_sshd
                ;;

            10)
                show_sshd_config
                ;;

            11)
                add_ignore_ip
                ;;

            12)
                show_ignore_ips
                ;;

            13)
                restart_fail2ban
                ;;

            14)
                remove_fail2ban
                ;;

            0)
                exit 0
                ;;

            *)
                error "Неизвестный пункт."
                sleep 1
                ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────

require_root "$@"
main_menu

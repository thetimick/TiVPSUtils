#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# Ubuntu Auto Updates Manager
# ============================================================

CONFIG_FILE="/etc/auto-updates-manager.conf"

APT_PERIODIC_CONFIG="/etc/apt/apt.conf.d/99-auto-updates-manager-periodic"
UNATTENDED_CONFIG="/etc/apt/apt.conf.d/99-unattended-upgrades-manager"

APT_DAILY_DROPIN_DIR="/etc/systemd/system/apt-daily.timer.d"
APT_DAILY_DROPIN="${APT_DAILY_DROPIN_DIR}/auto-updates-manager.conf"

APT_UPGRADE_DROPIN_DIR="/etc/systemd/system/apt-daily-upgrade.timer.d"
APT_UPGRADE_DROPIN="${APT_UPGRADE_DROPIN_DIR}/auto-updates-manager.conf"

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    BOLD=''
    RESET=''
fi

# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------

ENABLE_AUTO_UPDATES=true

UPGRADE_TIME="03:00"

# apt update будет запускаться за N минут до upgrade.
PACKAGE_LIST_ADVANCE=10

# Помимо security устанавливать обычные Ubuntu updates.
ENABLE_REGULAR_UPDATES=true

AUTO_REBOOT=true

# Разрешить reboot при активных пользователях / SSH-сессиях.
REBOOT_WITH_USERS=true

# "now" или HH:MM.
REBOOT_TIME="now"

REMOVE_UNUSED_DEPENDENCIES=true
REMOVE_UNUSED_KERNELS=true

# Запустить пропущенный timer после включения VPS.
PERSISTENT_TIMERS=true

# apt autoclean каждые N дней.
AUTOCLEAN_DAYS=7

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------

die() {
    echo -e "${RED}Ошибка:${RESET} $*" >&2
    exit 1
}

pause() {
    echo
    read -r -p "Нажмите Enter для продолжения..." _
}

clear_screen() {
    if command -v clear >/dev/null 2>&1; then
        clear
    fi
}

bool_text() {
    if [[ "$1" == "true" ]]; then
        echo -e "${GREEN}ВКЛ${RESET}"
    else
        echo -e "${RED}ВЫКЛ${RESET}"
    fi
}

yes_no() {
    if [[ "$1" == "true" ]]; then
        echo "Да"
    else
        echo "Нет"
    fi
}

validate_time() {
    local value="$1"

    if [[ ! "$value" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
        return 1
    fi

    local hour=$((10#${BASH_REMATCH[1]}))
    local minute=$((10#${BASH_REMATCH[2]}))

    (( hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ))
}

require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "запустите скрипт через sudo:

sudo $0"
    fi
}

require_ubuntu() {
    [[ -f /etc/os-release ]] || die "/etc/os-release не найден."

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "этот скрипт предназначен для Ubuntu.

Обнаружена система: ${PRETTY_NAME:-unknown}"
    fi
}

package_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null \
        | grep -q "install ok installed"
}

# ------------------------------------------------------------
# Configuration storage
# ------------------------------------------------------------

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Файл создаётся root и содержит только значения этого скрипта.
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
ENABLE_AUTO_UPDATES="$ENABLE_AUTO_UPDATES"
UPGRADE_TIME="$UPGRADE_TIME"
PACKAGE_LIST_ADVANCE="$PACKAGE_LIST_ADVANCE"
ENABLE_REGULAR_UPDATES="$ENABLE_REGULAR_UPDATES"
AUTO_REBOOT="$AUTO_REBOOT"
REBOOT_WITH_USERS="$REBOOT_WITH_USERS"
REBOOT_TIME="$REBOOT_TIME"
REMOVE_UNUSED_DEPENDENCIES="$REMOVE_UNUSED_DEPENDENCIES"
REMOVE_UNUSED_KERNELS="$REMOVE_UNUSED_KERNELS"
PERSISTENT_TIMERS="$PERSISTENT_TIMERS"
AUTOCLEAN_DAYS="$AUTOCLEAN_DAYS"
EOF

    chmod 600 "$CONFIG_FILE"
}

# ------------------------------------------------------------
# Time calculation
# ------------------------------------------------------------

package_list_time() {
    local hour="${UPGRADE_TIME%%:*}"
    local minute="${UPGRADE_TIME##*:}"

    local total=$((10#$hour * 60 + 10#$minute))
    local list_total=$(((total - PACKAGE_LIST_ADVANCE + 1440) % 1440))

    local list_hour=$((list_total / 60))
    local list_minute=$((list_total % 60))

    printf "%02d:%02d" "$list_hour" "$list_minute"
}

# ------------------------------------------------------------
# Installation
# ------------------------------------------------------------

ensure_packages() {
    local need_install=false

    if ! package_installed unattended-upgrades; then
        need_install=true
    fi

    # На minimal Ubuntu этот пакет полезен для reboot-required.
    if ! package_installed update-notifier-common; then
        need_install=true
    fi

    if [[ "$need_install" == "true" ]]; then
        echo
        echo -e "${CYAN}==> Установка необходимых пакетов...${RESET}"

        apt-get update

        DEBIAN_FRONTEND=noninteractive \
            apt-get install -y \
            unattended-upgrades \
            update-notifier-common
    fi
}

# ------------------------------------------------------------
# Generate APT configuration
# ------------------------------------------------------------

write_periodic_config() {
    if [[ "$ENABLE_AUTO_UPDATES" == "true" ]]; then
        cat > "$APT_PERIODIC_CONFIG" <<EOF
APT::Periodic::Enable "1";
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "$AUTOCLEAN_DAYS";

// Не использовать дополнительную случайную задержку APT.
APT::Periodic::RandomSleep "0";
EOF
    else
        cat > "$APT_PERIODIC_CONFIG" <<'EOF'
APT::Periodic::Enable "0";
APT::Periodic::Update-Package-Lists "0";
APT::Periodic::Unattended-Upgrade "0";
EOF
    fi
}

write_unattended_config() {
    cat > "$UNATTENDED_CONFIG" <<EOF
// ============================================================
// Generated by Ubuntu Auto Updates Manager
// ============================================================

// Полностью задаём разрешённые источники.
// Штатный /etc/apt/apt.conf.d/50unattended-upgrades
// при этом не изменяется.

#clear Unattended-Upgrade::Allowed-Origins;

Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
EOF

    if [[ "$ENABLE_REGULAR_UPDATES" == "true" ]]; then
        cat >> "$UNATTENDED_CONFIG" <<'EOF'
    "${distro_id}:${distro_codename}-updates";
EOF
    fi

    cat >> "$UNATTENDED_CONFIG" <<EOF
};

Unattended-Upgrade::AutoFixInterruptedDpkg "true";

Unattended-Upgrade::MinimalSteps "true";

Unattended-Upgrade::Remove-Unused-Kernel-Packages "$REMOVE_UNUSED_KERNELS";

Unattended-Upgrade::Remove-New-Unused-Dependencies "$REMOVE_UNUSED_DEPENDENCIES";

Unattended-Upgrade::Remove-Unused-Dependencies "$REMOVE_UNUSED_DEPENDENCIES";

Unattended-Upgrade::Automatic-Reboot "$AUTO_REBOOT";

Unattended-Upgrade::Automatic-Reboot-WithUsers "$REBOOT_WITH_USERS";

Unattended-Upgrade::Automatic-Reboot-Time "$REBOOT_TIME";

Unattended-Upgrade::SyslogEnable "true";
EOF
}

# ------------------------------------------------------------
# Generate systemd timers
# ------------------------------------------------------------

write_timer_config() {
    local list_time
    list_time="$(package_list_time)"

    mkdir -p "$APT_DAILY_DROPIN_DIR"
    mkdir -p "$APT_UPGRADE_DROPIN_DIR"

    cat > "$APT_DAILY_DROPIN" <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* ${list_time}:00
RandomizedDelaySec=0
AccuracySec=1s
Persistent=$PERSISTENT_TIMERS
EOF

    cat > "$APT_UPGRADE_DROPIN" <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* ${UPGRADE_TIME}:00
RandomizedDelaySec=0
AccuracySec=1s
Persistent=$PERSISTENT_TIMERS
EOF
}

# ------------------------------------------------------------
# Apply
# ------------------------------------------------------------

apply_config() {
    ensure_packages
    save_config

    write_periodic_config
    write_unattended_config
    write_timer_config

    systemctl daemon-reload

    if [[ "$ENABLE_AUTO_UPDATES" == "true" ]]; then
        systemctl enable apt-daily.timer >/dev/null 2>&1 || true
        systemctl enable apt-daily-upgrade.timer >/dev/null 2>&1 || true

        systemctl restart apt-daily.timer
        systemctl restart apt-daily-upgrade.timer
    else
        systemctl disable --now apt-daily.timer >/dev/null 2>&1 || true
        systemctl disable --now apt-daily-upgrade.timer >/dev/null 2>&1 || true
    fi

    echo
    echo -e "${GREEN}Настройки применены.${RESET}"
}

apply_quiet() {
    apply_config
    sleep 1
}

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

show_header() {
    local list_time
    list_time="$(package_list_time)"

    echo -e "${BOLD}┌──────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}│          Ubuntu Auto Updates Manager         │${RESET}"
    echo -e "${BOLD}└──────────────────────────────────────────────┘${RESET}"
    echo

    printf "  %-29s %b\n" \
        "Автообновления:" \
        "$(bool_text "$ENABLE_AUTO_UPDATES")"

    printf "  %-29s %s\n" \
        "Время обновления:" \
        "$UPGRADE_TIME"

    printf "  %-29s %s\n" \
        "Обновление package lists:" \
        "$list_time"

    printf "  %-29s %b\n" \
        "Обычные Ubuntu updates:" \
        "$(bool_text "$ENABLE_REGULAR_UPDATES")"

    printf "  %-29s %b\n" \
        "Автоматический reboot:" \
        "$(bool_text "$AUTO_REBOOT")"

    printf "  %-29s %b\n" \
        "Reboot с users:" \
        "$(bool_text "$REBOOT_WITH_USERS")"

    if [[ "$REBOOT_TIME" == "now" ]]; then
        printf "  %-29s %s\n" \
            "Время reboot:" \
            "сразу после обновления"
    else
        printf "  %-29s %s\n" \
            "Время reboot:" \
            "$REBOOT_TIME"
    fi

    printf "  %-29s %b\n" \
        "Очистка зависимостей:" \
        "$(bool_text "$REMOVE_UNUSED_DEPENDENCIES")"

    printf "  %-29s %b\n" \
        "Очистка старых ядер:" \
        "$(bool_text "$REMOVE_UNUSED_KERNELS")"

    printf "  %-29s %b\n" \
        "Persistent timers:" \
        "$(bool_text "$PERSISTENT_TIMERS")"

    printf "  %-29s %s дней\n" \
        "Autoclean:" \
        "$AUTOCLEAN_DAYS"

    echo
}

show_status() {
    clear_screen

    show_header

    echo -e "${BOLD}Systemd:${RESET}"
    echo

    printf "  apt-daily.timer:          "
    systemctl is-active apt-daily.timer 2>/dev/null || true

    printf "  apt-daily-upgrade.timer:  "
    systemctl is-active apt-daily-upgrade.timer 2>/dev/null || true

    echo
    echo -e "${BOLD}Следующие запуски:${RESET}"
    echo

    systemctl list-timers \
        apt-daily.timer \
        apt-daily-upgrade.timer \
        --all \
        --no-pager || true

    echo

    if [[ -f /var/run/reboot-required ]]; then
        echo -e "${YELLOW}Система требует перезагрузки.${RESET}"

        if [[ -f /var/run/reboot-required.pkgs ]]; then
            echo
            echo "Причина:"
            sed 's/^/  /' /var/run/reboot-required.pkgs
        fi
    else
        echo -e "${GREEN}Перезагрузка сейчас не требуется.${RESET}"
    fi

    echo
    echo -e "${BOLD}Timezone:${RESET}"
    timedatectl | grep "Time zone" || true

    pause
}

# ------------------------------------------------------------
# Change settings
# ------------------------------------------------------------

change_upgrade_time() {
    echo
    read -r -p "Введите время обновления [HH:MM]: " value

    if ! validate_time "$value"; then
        echo -e "${RED}Некорректное время.${RESET}"
        sleep 2
        return
    fi

    UPGRADE_TIME="$value"

    apply_quiet
}

change_package_list_advance() {
    echo
    echo "Сейчас apt update выполняется за $PACKAGE_LIST_ADVANCE мин. до обновления."
    echo

    read -r -p "Введите количество минут [0-1440]: " value

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Введите число.${RESET}"
        sleep 2
        return
    fi

    if (( value < 0 || value > 1440 )); then
        echo -e "${RED}Допустимый диапазон: 0-1440.${RESET}"
        sleep 2
        return
    fi

    PACKAGE_LIST_ADVANCE="$value"

    apply_quiet
}

change_reboot_time() {
    echo
    echo "Когда выполнять reboot после обновления:"
    echo
    echo "  1) Сразу после завершения обновления"
    echo "  2) В заданное время"
    echo

    read -r -p "Выберите вариант: " choice

    case "$choice" in
        1)
            REBOOT_TIME="now"
            apply_quiet
            ;;

        2)
            echo
            read -r -p "Введите время reboot [HH:MM]: " value

            if ! validate_time "$value"; then
                echo -e "${RED}Некорректное время.${RESET}"
                sleep 2
                return
            fi

            REBOOT_TIME="$value"
            apply_quiet
            ;;

        *)
            echo -e "${RED}Неверный пункт.${RESET}"
            sleep 1
            ;;
    esac
}

change_autoclean_days() {
    echo
    read -r -p "Запускать apt autoclean каждые N дней [0-365]: " value

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Введите число.${RESET}"
        sleep 2
        return
    fi

    if (( value < 0 || value > 365 )); then
        echo -e "${RED}Допустимый диапазон: 0-365.${RESET}"
        sleep 2
        return
    fi

    AUTOCLEAN_DAYS="$value"

    apply_quiet
}

toggle_auto_updates() {
    if [[ "$ENABLE_AUTO_UPDATES" == "true" ]]; then
        ENABLE_AUTO_UPDATES=false
    else
        ENABLE_AUTO_UPDATES=true
    fi

    apply_quiet
}

toggle_regular_updates() {
    if [[ "$ENABLE_REGULAR_UPDATES" == "true" ]]; then
        ENABLE_REGULAR_UPDATES=false
    else
        ENABLE_REGULAR_UPDATES=true
    fi

    apply_quiet
}

toggle_auto_reboot() {
    if [[ "$AUTO_REBOOT" == "true" ]]; then
        AUTO_REBOOT=false
    else
        AUTO_REBOOT=true
    fi

    apply_quiet
}

toggle_reboot_with_users() {
    if [[ "$REBOOT_WITH_USERS" == "true" ]]; then
        REBOOT_WITH_USERS=false
    else
        REBOOT_WITH_USERS=true
    fi

    apply_quiet
}

toggle_remove_dependencies() {
    if [[ "$REMOVE_UNUSED_DEPENDENCIES" == "true" ]]; then
        REMOVE_UNUSED_DEPENDENCIES=false
    else
        REMOVE_UNUSED_DEPENDENCIES=true
    fi

    apply_quiet
}

toggle_remove_kernels() {
    if [[ "$REMOVE_UNUSED_KERNELS" == "true" ]]; then
        REMOVE_UNUSED_KERNELS=false
    else
        REMOVE_UNUSED_KERNELS=true
    fi

    apply_quiet
}

toggle_persistent() {
    if [[ "$PERSISTENT_TIMERS" == "true" ]]; then
        PERSISTENT_TIMERS=false
    else
        PERSISTENT_TIMERS=true
    fi

    apply_quiet
}

# ------------------------------------------------------------
# Dry run
# ------------------------------------------------------------

dry_run() {
    clear_screen

    ensure_packages

    echo -e "${BOLD}Dry-run unattended-upgrades${RESET}"
    echo
    echo "Пакеты реально устанавливаться не будут."
    echo

    unattended-upgrade --dry-run --debug || true

    pause
}

# ------------------------------------------------------------
# Logs
# ------------------------------------------------------------

show_logs() {
    clear_screen

    local log="/var/log/unattended-upgrades/unattended-upgrades.log"

    echo -e "${BOLD}Последние события unattended-upgrades:${RESET}"
    echo

    if [[ -f "$log" ]]; then
        tail -n 100 "$log"
    else
        echo "Лог пока отсутствует:"
        echo "$log"
    fi

    pause
}

show_dpkg_logs() {
    clear_screen

    local log="/var/log/unattended-upgrades/unattended-upgrades-dpkg.log"

    echo -e "${BOLD}Последний dpkg log:${RESET}"
    echo

    if [[ -f "$log" ]]; then
        tail -n 100 "$log"
    else
        echo "Лог пока отсутствует:"
        echo "$log"
    fi

    pause
}

# ------------------------------------------------------------
# Effective APT config
# ------------------------------------------------------------

show_effective_config() {
    clear_screen

    echo -e "${BOLD}Эффективная конфигурация APT:${RESET}"
    echo

    apt-config dump \
        | grep -E \
            'APT::Periodic|Unattended-Upgrade::Allowed-Origins|Unattended-Upgrade::Automatic-Reboot|Unattended-Upgrade::Remove-' \
        || true

    pause
}

# ------------------------------------------------------------
# Manual apt update
# ------------------------------------------------------------

manual_apt_update() {
    clear_screen

    echo -e "${BOLD}Обновление package lists...${RESET}"
    echo

    apt-get update

    echo
    echo -e "${GREEN}apt update завершён.${RESET}"

    pause
}

# ------------------------------------------------------------
# Remove manager
# ------------------------------------------------------------

remove_manager_config() {
    clear_screen

    echo -e "${YELLOW}Будут удалены настройки Auto Updates Manager.${RESET}"
    echo
    echo "Штатный /etc/apt/apt.conf.d/50unattended-upgrades"
    echo "изменён не будет."
    echo
    echo "После удаления будут включены стандартные Ubuntu"
    echo "apt-daily.timer и apt-daily-upgrade.timer."
    echo

    read -r -p "Продолжить? [y/N]: " answer

    case "$answer" in
        y|Y|yes|YES)
            ;;
        *)
            return
            ;;
    esac

    rm -f "$CONFIG_FILE"
    rm -f "$APT_PERIODIC_CONFIG"
    rm -f "$UNATTENDED_CONFIG"
    rm -f "$APT_DAILY_DROPIN"
    rm -f "$APT_UPGRADE_DROPIN"

    rmdir "$APT_DAILY_DROPIN_DIR" 2>/dev/null || true
    rmdir "$APT_UPGRADE_DROPIN_DIR" 2>/dev/null || true

    systemctl daemon-reload

    systemctl enable apt-daily.timer >/dev/null 2>&1 || true
    systemctl enable apt-daily-upgrade.timer >/dev/null 2>&1 || true

    systemctl restart apt-daily.timer || true
    systemctl restart apt-daily-upgrade.timer || true

    echo
    echo -e "${GREEN}Настройки менеджера удалены.${RESET}"
    echo
    echo "Восстановлено стандартное расписание Ubuntu."

    pause

    exit 0
}

# ------------------------------------------------------------
# Main menu
# ------------------------------------------------------------

main_menu() {
    while true; do
        clear_screen
        show_header

        echo -e "${BOLD}Управление:${RESET}"
        echo
        echo "  1)  Показать состояние"
        echo
        echo "  2)  Включить / выключить автообновления"
        echo "  3)  Изменить время обновления"
        echo "  4)  Изменить время запуска apt update"
        echo
        echo "  5)  Включить / выключить обычные Ubuntu updates"
        echo
        echo "  6)  Включить / выключить автоматический reboot"
        echo "  7)  Разрешить / запретить reboot с активными users"
        echo "  8)  Изменить время reboot"
        echo
        echo "  9)  Включить / выключить очистку зависимостей"
        echo " 10)  Включить / выключить очистку старых ядер"
        echo " 11)  Включить / выключить Persistent timers"
        echo " 12)  Изменить период autoclean"
        echo
        echo " 13)  Применить конфигурацию заново"
        echo
        echo " 14)  Dry-run обновления"
        echo " 15)  Показать лог unattended-upgrades"
        echo " 16)  Показать dpkg log"
        echo " 17)  Показать эффективный APT config"
        echo " 18)  Выполнить apt update сейчас"
        echo
        echo " 19)  Удалить настройки менеджера"
        echo
        echo "  0)  Выход"
        echo

        read -r -p "Выберите пункт: " choice

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
                clear_screen
                exit 0
                ;;

            *)
                echo
                echo -e "${RED}Неизвестный пункт.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# ------------------------------------------------------------
# Start
# ------------------------------------------------------------

require_root
require_ubuntu

load_config

main_menu

#!/usr/bin/env bash

APP_NAME="Автообновления Ubuntu"
SCHEDULE_TIMEZONE="Europe/Moscow"

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

validate_time() {
    local value="$1"

    if [[ ! "$value" =~ ^([0-9]{2}):([0-9]{2})$ ]]; then
        return 1
    fi

    local hour=$((10#${BASH_REMATCH[1]}))
    local minute=$((10#${BASH_REMATCH[2]}))

    (( hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59 ))
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

initialize_config() {
    load_config
    ensure_schedule_timezone || return $?

    # Defaults in memory do not mean that APT and systemd are configured.
    # Also recover an interrupted setup without changing saved preferences.
    if [[ ! -f "$CONFIG_FILE" || ! -f "$APT_PERIODIC_CONFIG" \
        || ! -f "$UNATTENDED_CONFIG" || ! -f "$APT_DAILY_DROPIN" \
        || ! -f "$APT_UPGRADE_DROPIN" ]]; then
        info "Применяю начальную конфигурацию автообновлений..."
        apply_config || return $?
    fi
}

ensure_schedule_timezone() {
    local current_timezone
    current_timezone="$(timedatectl show --property=Timezone --value)" || return $?
    if [[ "$current_timezone" != "$SCHEDULE_TIMEZONE" ]]; then
        info "Устанавливаю часовой пояс VPS: МСК ($SCHEDULE_TIMEZONE)..."
        timedatectl set-timezone "$SCHEDULE_TIMEZONE" || return $?
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
        info "Установка необходимых пакетов..."

        apt-get update || return $?

        DEBIAN_FRONTEND=noninteractive \
            apt-get install -y \
            unattended-upgrades \
            update-notifier-common || return $?
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

    mkdir -p "$APT_DAILY_DROPIN_DIR" || return $?
    mkdir -p "$APT_UPGRADE_DROPIN_DIR" || return $?

    cat > "$APT_DAILY_DROPIN" <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* ${list_time}:00
RandomizedDelaySec=0
AccuracySec=1s
Persistent=$PERSISTENT_TIMERS
EOF
    local write_status=$?
    (( write_status == 0 )) || return "$write_status"

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
    ensure_schedule_timezone || return $?
    ensure_packages || return $?

    write_periodic_config || return $?
    write_unattended_config || return $?
    write_timer_config || return $?

    systemctl daemon-reload || return $?

    if [[ "$ENABLE_AUTO_UPDATES" == "true" ]]; then
        systemctl enable apt-daily.timer || return $?
        systemctl enable apt-daily-upgrade.timer || return $?

        systemctl restart apt-daily.timer || return $?
        systemctl restart apt-daily-upgrade.timer || return $?
    else
        systemctl disable --now apt-daily.timer || return $?
        systemctl disable --now apt-daily-upgrade.timer || return $?
    fi

    # Record preferences only after all configuration and timer operations succeed.
    save_config || return $?

    echo
    success "Настройки применены."
}

apply_quiet() {
    apply_config || return $?
    sleep 1
}

# ------------------------------------------------------------
# Status
# ------------------------------------------------------------

show_header() {
    ui_header "$APP_NAME"
    local list_time
    list_time="$(package_list_time)"

    ui_field "Часовой пояс расписания:" "МСК ($SCHEDULE_TIMEZONE)"

    ui_field \
        "Автообновления:" \
        "$(bool_text "$ENABLE_AUTO_UPDATES")"

    ui_field \
        "Время обновления:" \
        "$UPGRADE_TIME"

    ui_field \
        "Обновление package lists:" \
        "$list_time"

    ui_field \
        "Обычные Ubuntu updates:" \
        "$(bool_text "$ENABLE_REGULAR_UPDATES")"

    ui_field \
        "Автоматический reboot:" \
        "$(bool_text "$AUTO_REBOOT")"

    ui_field \
        "Reboot с users:" \
        "$(bool_text "$REBOOT_WITH_USERS")"

    if [[ "$REBOOT_TIME" == "now" ]]; then
        ui_field \
            "Время reboot:" \
            "сразу после обновления"
    else
        ui_field \
            "Время reboot:" \
            "$REBOOT_TIME"
    fi

    ui_field \
        "Очистка зависимостей:" \
        "$(bool_text "$REMOVE_UNUSED_DEPENDENCIES")"

    ui_field \
        "Очистка старых ядер:" \
        "$(bool_text "$REMOVE_UNUSED_KERNELS")"

    ui_field \
        "Persistent timers:" \
        "$(bool_text "$PERSISTENT_TIMERS")"

    ui_field \
        "Autoclean:" \
        "$AUTOCLEAN_DAYS дней"

    echo
}

show_status() {
    clear_screen

    show_header

    section_title "Systemd:"
    echo

    printf "  apt-daily.timer:          "
    systemctl is-active apt-daily.timer 2>/dev/null || true

    printf "  apt-daily-upgrade.timer:  "
    systemctl is-active apt-daily-upgrade.timer 2>/dev/null || true

    echo
    section_title "Следующие запуски:"
    echo

    TZ="$SCHEDULE_TIMEZONE" systemctl list-timers \
        apt-daily.timer \
        apt-daily-upgrade.timer \
        --all \
        --no-pager || true

    echo

    if [[ -f /var/run/reboot-required ]]; then
        warn "Система требует перезагрузки."

        if [[ -f /var/run/reboot-required.pkgs ]]; then
            echo
            echo "Причина:"
            sed 's/^/  /' /var/run/reboot-required.pkgs
        fi
    else
        success "Перезагрузка сейчас не требуется."
    fi

    echo
    section_title "Часовой пояс VPS (расписание по МСК):"
    timedatectl | grep "Time zone" || true

    pause
}

# ------------------------------------------------------------
# Change settings
# ------------------------------------------------------------

change_upgrade_time() {
    echo
    ui_read "Введите время обновления по МСК [HH:MM]:" value

    if ! validate_time "$value"; then
        error "Некорректное время."
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

    ui_read "Введите количество минут [0-1440]:" value

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        error "Введите число."
        sleep 2
        return
    fi

    if (( value < 0 || value > 1440 )); then
        error "Допустимый диапазон: 0-1440."
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
    menu_item "1" "Сразу после завершения обновления"
    menu_item "2" "В заданное время"
    echo

    ui_read "Выберите вариант:" choice

    case "$choice" in
        1)
            REBOOT_TIME="now"
            apply_quiet
            ;;

        2)
            echo
            ui_read "Введите время reboot по МСК [HH:MM]:" value

            if ! validate_time "$value"; then
                error "Некорректное время."
                sleep 2
                return
            fi

            REBOOT_TIME="$value"
            apply_quiet
            ;;

        *)
            error "Неверный пункт."
            sleep 1
            ;;
    esac
}

change_autoclean_days() {
    echo
    ui_read "Запускать apt autoclean каждые N дней [0-365]:" value

    if [[ ! "$value" =~ ^[0-9]+$ ]]; then
        error "Введите число."
        sleep 2
        return
    fi

    if (( value < 0 || value > 365 )); then
        error "Допустимый диапазон: 0-365."
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

    section_title "Dry-run unattended-upgrades"
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

    section_title "Последние события unattended-upgrades:"
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

    section_title "Последний dpkg log:"
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

    section_title "Эффективная конфигурация APT:"
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

    section_title "Обновление package lists..."
    echo

    apt-get update

    echo
    success "apt update завершён."

    pause
}

# ------------------------------------------------------------
# Remove manager
# ------------------------------------------------------------

remove_manager_config() {
    clear_screen

    warn "Будут удалены настройки Auto Updates Manager."
    echo
    echo "Штатный /etc/apt/apt.conf.d/50unattended-upgrades"
    echo "изменён не будет."
    echo
    echo "После удаления будут включены стандартные Ubuntu"
    echo "apt-daily.timer и apt-daily-upgrade.timer."
    echo

    confirm "Удалить настройки менеджера?" || return

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
    success "Настройки менеджера удалены."
    echo
    echo "Восстановлено стандартное расписание Ubuntu."

    pause

    exit 0
}

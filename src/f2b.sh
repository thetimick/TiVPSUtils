#!/usr/bin/env bash

set -Eeuo pipefail

APP_NAME="Fail2ban Manager"

MANAGED_SSHD_CONF="/etc/fail2ban/jail.d/99-f2ban-manager-sshd.local"
MANAGED_IGNORE_CONF="/etc/fail2ban/jail.d/99-f2ban-manager-ignore.local"

# ─────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────

if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    RESET=''
fi

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

info() {
    echo -e "${BLUE}ℹ${RESET} $*"
}

success() {
    echo -e "${GREEN}✔${RESET} $*"
}

warn() {
    echo -e "${YELLOW}⚠${RESET} $*"
}

error() {
    echo -e "${RED}✘${RESET} $*" >&2
}

pause() {
    echo
    read -r -p "Нажми Enter, чтобы продолжить..." _ || true
}

confirm() {
    local prompt="${1:-Продолжить?}"
    local answer

    read -r -p "$prompt [y/N]: " answer || true
    [[ "$answer" =~ ^[YyДд]$ ]]
}

clear_screen() {
    [[ -t 1 ]] && clear || true
}

require_root() {
    if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
        if command -v sudo >/dev/null 2>&1; then
            exec sudo -- "$0" "$@"
        fi

        error "Скрипт необходимо запустить от root."
        exit 1
    fi
}

is_installed() {
    command -v fail2ban-client >/dev/null 2>&1
}

service_active() {
    systemctl is-active --quiet fail2ban 2>/dev/null
}

# ─────────────────────────────────────────────────────────────
# Jail helpers
# ─────────────────────────────────────────────────────────────

get_jails() {
    if ! is_installed || ! service_active; then
        return 0
    fi

    fail2ban-client status 2>/dev/null \
        | sed -n 's/.*Jail list:[[:space:]]*//p' \
        | tr ',' ' '
}

choose_jail() {
    local -a jails=()
    local i
    local choice

    read -r -a jails <<< "$(get_jails)"

    if (( ${#jails[@]} == 0 )); then
        warn "Нет активных jail."
        return 1
    fi

    echo
    echo "Доступные jail:"
    echo

    for i in "${!jails[@]}"; do
        printf "  %d) %s\n" "$((i + 1))" "${jails[$i]}"
    done

    echo
    echo "  0) Отмена"
    echo

    read -r -p "Выбери jail: " choice

    [[ "$choice" == "0" ]] && return 1

    if ! [[ "$choice" =~ ^[0-9]+$ ]] \
        || (( choice < 1 || choice > ${#jails[@]} )); then

        error "Неверный выбор."
        return 1
    fi

    SELECTED_JAIL="${jails[$((choice - 1))]}"
}

# ─────────────────────────────────────────────────────────────
# Header
# ─────────────────────────────────────────────────────────────

show_header() {
    local installed="нет"
    local service="—"
    local version="—"
    local jails="—"

    if is_installed; then
        installed="да"

        version="$(
            fail2ban-client --version 2>/dev/null \
                | head -n1 \
                | awk '{print $NF}' \
                || true
        )"

        if service_active; then
            service="активен"
            jails="$(get_jails | wc -w | tr -d ' ')"
        else
            service="остановлен"
        fi
    fi

    echo -e "${BOLD}┌──────────────────────────────────────────────┐${RESET}"
    echo -e "${BOLD}│              Fail2ban Manager                │${RESET}"
    echo -e "${BOLD}└──────────────────────────────────────────────┘${RESET}"
    echo

    printf "  %-22s %s\n" "Установлен:" "$installed"
    printf "  %-22s %s\n" "Версия:" "$version"
    printf "  %-22s %s\n" "Сервис:" "$service"
    printf "  %-22s %s\n" "Активных jail:" "$jails"

    echo
}

# ─────────────────────────────────────────────────────────────
# Install
# ─────────────────────────────────────────────────────────────

install_fail2ban() {
    if is_installed; then
        success "Fail2ban уже установлен."
        pause
        return
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        error "Автоматическая установка поддерживает Debian/Ubuntu."
        pause
        return
    fi

    info "Обновляю список пакетов..."
    apt-get update

    info "Устанавливаю Fail2ban..."

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y fail2ban

    systemctl enable --now fail2ban

    success "Fail2ban установлен и запущен."

    pause
}

# ─────────────────────────────────────────────────────────────
# Remove
# ─────────────────────────────────────────────────────────────

remove_fail2ban() {
    if ! is_installed; then
        warn "Fail2ban не установлен."
        pause
        return
    fi

    if ! confirm "Удалить Fail2ban?"; then
        return
    fi

    systemctl disable --now fail2ban 2>/dev/null || true

    if command -v apt-get >/dev/null 2>&1; then

        if confirm "Удалить также конфигурацию /etc/fail2ban?"; then
            apt-get purge -y fail2ban
            rm -rf /etc/fail2ban
        else
            apt-get remove -y fail2ban
        fi

        apt-get autoremove -y
    else
        warn "Неизвестный пакетный менеджер."
        warn "Сервис остановлен, но пакет автоматически не удалён."
    fi

    success "Готово."
    pause
}

# ─────────────────────────────────────────────────────────────
# Status
# ─────────────────────────────────────────────────────────────

show_status() {
    if ! is_installed; then
        warn "Fail2ban не установлен."
        pause
        return
    fi

    echo -e "${BOLD}Сервис:${RESET}"
    echo

    systemctl \
        --no-pager \
        --full \
        status fail2ban 2>/dev/null || true

    echo
    echo -e "${BOLD}Fail2ban:${RESET}"
    echo

    fail2ban-client status 2>/dev/null || true

    pause
}

# ─────────────────────────────────────────────────────────────
# Jails
# ─────────────────────────────────────────────────────────────

show_jails() {
    local jail

    if ! service_active; then
        warn "Fail2ban не запущен."
        pause
        return
    fi

    echo -e "${BOLD}Активные jail:${RESET}"
    echo

    for jail in $(get_jails); do
        echo -e "${CYAN}[$jail]${RESET}"

        fail2ban-client status "$jail" || true

        echo
    done

    pause
}

# ─────────────────────────────────────────────────────────────
# Banned IP
# ─────────────────────────────────────────────────────────────

show_banned_ips() {
    local jail
    local ip
    local count=0
    local -a ips=()

    if ! service_active; then
        warn "Fail2ban не запущен."
        pause
        return
    fi

    echo -e "${BOLD}Заблокированные IP:${RESET}"
    echo

    for jail in $(get_jails); do

        read -r -a ips <<< "$(
            fail2ban-client get "$jail" banip 2>/dev/null || true
        )"

        if (( ${#ips[@]} > 0 )); then

            echo -e "${CYAN}[$jail]${RESET}"

            for ip in "${ips[@]}"; do
                [[ -z "$ip" ]] && continue

                echo "  $ip"

                ((count += 1))
            done

            echo
        fi
    done

    if (( count == 0 )); then
        echo "  Заблокированных IP нет."
    else
        echo "Всего блокировок: $count"
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# Manual ban
# ─────────────────────────────────────────────────────────────

ban_ip() {
    local ip

    if ! service_active; then
        warn "Fail2ban не запущен."
        pause
        return
    fi

    choose_jail || {
        pause
        return
    }

    echo
    read -r -p "IP для блокировки: " ip

    if [[ -z "$ip" ]]; then
        error "IP не указан."
        pause
        return
    fi

    fail2ban-client \
        set "$SELECTED_JAIL" \
        banip "$ip"

    success "$ip заблокирован в jail '$SELECTED_JAIL'."

    pause
}

# ─────────────────────────────────────────────────────────────
# Unban
# ─────────────────────────────────────────────────────────────

unban_ip() {
    local ip
    local jail
    local found=0

    if ! service_active; then
        warn "Fail2ban не запущен."
        pause
        return
    fi

    read -r -p "IP для разблокировки: " ip

    if [[ -z "$ip" ]]; then
        error "IP не указан."
        pause
        return
    fi

    for jail in $(get_jails); do

        if fail2ban-client get "$jail" banip 2>/dev/null \
            | tr ' ' '\n' \
            | grep -Fxq "$ip"; then

            fail2ban-client \
                set "$jail" \
                unbanip "$ip" \
                >/dev/null

            success "$ip разблокирован в jail '$jail'."

            found=1
        fi
    done

    if (( found == 0 )); then
        warn "$ip не найден среди активных блокировок."
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# Fail2ban logs
# ─────────────────────────────────────────────────────────────

show_recent_events() {
    local lines

    read -r -p "Сколько последних событий показать? [50]: " lines
    lines="${lines:-50}"

    if ! [[ "$lines" =~ ^[0-9]+$ ]] || (( lines < 1 )); then
        lines=50
    fi

    echo
    echo -e "${BOLD}Последние события Fail2ban:${RESET}"
    echo

    if command -v journalctl >/dev/null 2>&1; then

        journalctl \
            -u fail2ban \
            --no-pager \
            -n "$lines" \
            2>/dev/null || true

    elif [[ -f /var/log/fail2ban.log ]]; then

        tail -n "$lines" /var/log/fail2ban.log

    else
        warn "Лог Fail2ban не найден."
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# SSH failures
# ─────────────────────────────────────────────────────────────

show_failed_ssh() {
    local lines

    read -r -p "Сколько попыток показать? [50]: " lines
    lines="${lines:-50}"

    if ! [[ "$lines" =~ ^[0-9]+$ ]] || (( lines < 1 )); then
        lines=50
    fi

    echo
    echo -e "${BOLD}Последние неудачные SSH-входы:${RESET}"
    echo

    if command -v journalctl >/dev/null 2>&1; then

        journalctl \
            -u ssh \
            -u sshd \
            --no-pager \
            -n 2000 \
            2>/dev/null \
            | grep -Ei \
                'Failed password|Invalid user|authentication failure|Disconnected from authenticating user' \
            | tail -n "$lines" \
            || true

    elif [[ -f /var/log/auth.log ]]; then

        grep -Ei \
            'Failed password|Invalid user|authentication failure' \
            /var/log/auth.log \
            | tail -n "$lines" \
            || true

    else
        warn "SSH-лог не найден."
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# SSH jail configuration
# ─────────────────────────────────────────────────────────────

configure_sshd() {
    local port
    local bantime
    local findtime
    local maxretry
    local mode

    if ! is_installed; then
        warn "Сначала установи Fail2ban."
        pause
        return
    fi

    echo -e "${BOLD}Настройка jail [sshd]${RESET}"
    echo

    read -r -p "SSH порт [ssh]: " port
    read -r -p "Время бана [1h]: " bantime
    read -r -p "Окно попыток [10m]: " findtime
    read -r -p "Максимум попыток [5]: " maxretry
    read -r -p "Режим normal/ddos/extra/aggressive [normal]: " mode

    port="${port:-ssh}"
    bantime="${bantime:-1h}"
    findtime="${findtime:-10m}"
    maxretry="${maxretry:-5}"
    mode="${mode:-normal}"

    if ! [[ "$maxretry" =~ ^[1-9][0-9]*$ ]]; then
        error "maxretry должен быть положительным числом."
        pause
        return
    fi

    case "$mode" in
        normal|ddos|extra|aggressive)
            ;;
        *)
            error "Неизвестный режим sshd."
            pause
            return
            ;;
    esac

    mkdir -p /etc/fail2ban/jail.d

    if [[ -f "$MANAGED_SSHD_CONF" ]]; then

        cp -a \
            "$MANAGED_SSHD_CONF" \
            "${MANAGED_SSHD_CONF}.bak.$(date +%Y%m%d-%H%M%S)"
    fi

    cat > "$MANAGED_SSHD_CONF" <<EOF
# Managed by Fail2ban Manager

[sshd]
enabled  = true
port     = ${port}
mode     = ${mode}

bantime  = ${bantime}
findtime = ${findtime}
maxretry = ${maxretry}
EOF

    echo
    info "Проверяю конфигурацию..."

    if fail2ban-client -t; then

        systemctl restart fail2ban

        success "SSH jail настроен."

    else

        error "Конфигурация Fail2ban содержит ошибку."
        warn "Файл: $MANAGED_SSHD_CONF"
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# Show managed config
# ─────────────────────────────────────────────────────────────

show_sshd_config() {
    if [[ -f "$MANAGED_SSHD_CONF" ]]; then

        echo -e "${BOLD}$MANAGED_SSHD_CONF${RESET}"
        echo

        cat "$MANAGED_SSHD_CONF"

    else
        warn "Конфигурация SSH через менеджер ещё не создавалась."
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# Whitelist
# ─────────────────────────────────────────────────────────────

add_ignore_ip() {
    local ip
    local current="127.0.0.1/8 ::1"

    if ! is_installed; then
        warn "Fail2ban не установлен."
        pause
        return
    fi

    read -r -p "IP/CIDR для whitelist: " ip

    if [[ -z "$ip" ]]; then
        error "Адрес не указан."
        pause
        return
    fi

    if [[ -f "$MANAGED_IGNORE_CONF" ]]; then

        current="$(
            sed -n \
                's/^[[:space:]]*ignoreip[[:space:]]*=[[:space:]]*//p' \
                "$MANAGED_IGNORE_CONF" \
                | tail -n1
        )"

        current="${current:-127.0.0.1/8 ::1}"
    fi

    if tr ' ' '\n' <<< "$current" | grep -Fxq "$ip"; then
        warn "$ip уже находится в whitelist."
        pause
        return
    fi

    mkdir -p /etc/fail2ban/jail.d

    cat > "$MANAGED_IGNORE_CONF" <<EOF
# Managed by Fail2ban Manager

[DEFAULT]
ignoreip = ${current} ${ip}
EOF

    if fail2ban-client -t; then

        systemctl restart fail2ban

        success "$ip добавлен в whitelist."

    else
        error "Конфигурация содержит ошибку."
    fi

    pause
}

show_ignore_ips() {
    echo -e "${BOLD}Whitelist:${RESET}"
    echo

    if [[ -f "$MANAGED_IGNORE_CONF" ]]; then

        sed -n \
            's/^[[:space:]]*ignoreip[[:space:]]*=[[:space:]]*/  /p' \
            "$MANAGED_IGNORE_CONF"

    else
        echo "  Whitelist менеджера не настроен."
    fi

    pause
}

# ─────────────────────────────────────────────────────────────
# Restart
# ─────────────────────────────────────────────────────────────

restart_fail2ban() {
    if ! is_installed; then
        warn "Fail2ban не установлен."
        pause
        return
    fi

    info "Проверяю конфигурацию..."

    if ! fail2ban-client -t; then
        error "Конфигурация содержит ошибки."
        error "Перезапуск отменён."
        pause
        return
    fi

    systemctl restart fail2ban

    success "Fail2ban перезапущен."

    pause
}

# ─────────────────────────────────────────────────────────────
# Main menu
# ─────────────────────────────────────────────────────────────

main_menu() {
    local choice

    while true; do

        clear_screen
        show_header

        echo "  1) Установить Fail2ban"
        echo
        echo "  2) Статус"
        echo "  3) Показать jail"
        echo "  4) Показать заблокированные IP"
        echo
        echo "  5) Заблокировать IP"
        echo "  6) Разблокировать IP"
        echo
        echo "  7) Последние события Fail2ban"
        echo "  8) Последние неудачные SSH-входы"
        echo
        echo "  9) Настроить SSH jail"
        echo " 10) Показать SSH-конфиг"
        echo
        echo " 11) Добавить IP в whitelist"
        echo " 12) Показать whitelist"
        echo
        echo " 13) Перезапустить Fail2ban"
        echo
        echo " 14) Удалить Fail2ban"
        echo
        echo "  0) Выход"
        echo

        read -r -p "Выбери действие: " choice

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

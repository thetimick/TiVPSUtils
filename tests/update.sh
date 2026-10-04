#!/usr/bin/env bash
# Regression checks with temporary configuration files and mocked system commands.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/src/helpers/ui.sh"
source "$ROOT/src/helpers/update.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT
CONFIG_FILE="$TEST_DIR/preferences.conf"
APT_PERIODIC_CONFIG="$TEST_DIR/periodic.conf"
UNATTENDED_CONFIG="$TEST_DIR/unattended.conf"
APT_DAILY_DROPIN_DIR="$TEST_DIR/daily"
APT_DAILY_DROPIN="$APT_DAILY_DROPIN_DIR/manager.conf"
APT_UPGRADE_DROPIN_DIR="$TEST_DIR/upgrade"
APT_UPGRADE_DROPIN="$APT_UPGRADE_DROPIN_DIR/manager.conf"
CALLS="$TEST_DIR/calls"
FAIL_COMMAND=''
FAIL_APT=false
TEST_TIMEZONE=UTC
FAIL_TIMEZONE=false

timedatectl() {
    case "$1" in
        show) printf '%s\n' "$TEST_TIMEZONE" ;;
        set-timezone)
            printf 'timedatectl %s\n' "$*" >> "$CALLS"
            [[ "$FAIL_TIMEZONE" == false ]] || return 1
            TEST_TIMEZONE="$2"
            ;;
        *) return 1 ;;
    esac
}

apt-get() {
    printf 'apt-get %s\n' "$*" >> "$CALLS"
    [[ "$FAIL_APT" == false ]]
}
package_installed() { return 1; }
systemctl() {
    printf 'systemctl %s\n' "$*" >> "$CALLS"
    [[ "$*" != "$FAIL_COMMAND" ]]
}
sleep() { :; }

# First launch installs dependencies, writes configuration, and starts both timers.
initialize_config
[[ "$TEST_TIMEZONE" == Europe/Moscow ]]
grep -Fq 'timedatectl set-timezone Europe/Moscow' "$CALLS"
grep -Fq 'apt-get install -y unattended-upgrades update-notifier-common' "$CALLS"
grep -Fq 'APT::Periodic::Enable "1";' "$APT_PERIODIC_CONFIG"
grep -Fq 'OnCalendar=*-*-* 02:50:00' "$APT_DAILY_DROPIN"
grep -Fq 'OnCalendar=*-*-* 03:00:00' "$APT_UPGRADE_DROPIN"
grep -Fq 'systemctl restart apt-daily.timer' "$CALLS"
grep -Fq 'systemctl restart apt-daily-upgrade.timer' "$CALLS"
[[ -f "$CONFIG_FILE" ]]

# A complete installation is loaded without restarting timers on every menu launch.
: > "$CALLS"
initialize_config
[[ ! -s "$CALLS" ]]

# An existing installation adopts Moscow time without changing its schedule.
TEST_TIMEZONE=UTC
initialize_config
[[ "$TEST_TIMEZONE" == Europe/Moscow && "$UPGRADE_TIME" == 03:00 ]]

# Failure to set the timezone must stop initialization.
TEST_TIMEZONE=UTC
FAIL_TIMEZONE=true
if initialize_config; then
    printf 'Expected timezone setup failure\n' >&2
    exit 1
fi
FAIL_TIMEZONE=false
TEST_TIMEZONE=Europe/Moscow

# Saved disabled state and a custom schedule survive recovery of missing files.
ENABLE_AUTO_UPDATES=false
UPGRADE_TIME=06:15
apply_config
rm -- "$APT_UPGRADE_DROPIN"
ENABLE_AUTO_UPDATES=true
UPGRADE_TIME=03:00
: > "$CALLS"
initialize_config
[[ "$ENABLE_AUTO_UPDATES" == false && "$UPGRADE_TIME" == 06:15 ]]
grep -Fq 'APT::Periodic::Enable "0";' "$APT_PERIODIC_CONFIG"
grep -Fq 'OnCalendar=*-*-* 06:15:00' "$APT_UPGRADE_DROPIN"
grep -Fq 'systemctl disable --now apt-daily-upgrade.timer' "$CALLS"

# Failed first setup does not persist a misleading successful configuration.
rm -- "$CONFIG_FILE"
ENABLE_AUTO_UPDATES=true
FAIL_COMMAND='enable apt-daily.timer'
if initialize_config; then
    printf 'Expected setup failure\n' >&2
    exit 1
fi
[[ ! -f "$CONFIG_FILE" ]]
FAIL_COMMAND=''
initialize_config
[[ -f "$CONFIG_FILE" ]]

# Package installation failure must stop setup before timers are touched.
rm -- "$CONFIG_FILE"
: > "$CALLS"
FAIL_APT=true
if initialize_config; then
    printf 'Expected package installation failure\n' >&2
    exit 1
fi
[[ ! -f "$CONFIG_FILE" ]]
if grep -q '^systemctl ' "$CALLS"; then exit 1; fi

printf 'tiupdate regression checks passed\n'

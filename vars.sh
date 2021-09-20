# shellcheck shell=sh
set -eu

set +e
if ! command -v command > /dev/null ; then
    echo "shell builtin 'command' not posix compliant"
    exit 1
fi
# Happens on posh < 0.14.1
set -e

### Pull in settings
# All of the variables listed here can be overridden by changing them in
# default-valheim.profile.yaml. For example:
#
# config:
#   environment.TIMEZONE: "Asia/Jakarta"
#
# For timezone names, run the command:
# timedatectl list-timezones
#
# This can be done for any of the variables listed in this file, but really the only
# ones that need changing are the ones listed in default-valheim.profile.yaml already
export TIMEZONE="${TIMEZONE:-"UTC"}"
export VALHEIM_START_PORT="${VALHEIM_START_PORT:-"2456"}"
export VALHEIM_WORLD_NAME="${VALHEIM_WORLD_NAME:-"Dedicated Server"}"
export VALHEIM_WORLD_FILE_NAME="${VALHEIM_WORLD_FILE_NAME:-"dedicated"}"
export VALHEIM_SERVER_IS_PUBLIC="${VALHEIM_SERVER_IS_PUBLIC:-"yes"}"
export VALHEIM_PASSWORD="${VALHEIM_PASSWORD:-"secret"}"
export VALHEIM_SHOULD_AUTO_UPDATE="${VALHEIM_SHOULD_AUTO_UPDATE:-"yes"}"

### Probably don't need to change any of these
# If you do, these should be changed by creating a file locally, called:
# extra_vars.sh, in the same directory as this file
#
# It should contain lines like the following:
# export LOG_PREFIX='###CUSTOM PREFIX###'
#
# This way, any variables listed here can be overridden.
# This file is uploaded to the instance as part of install.sh,
# and used by the uploaded vars.sh
export STEAM_USER_NAME="${STEAM_USER_NAME:-"steam"}"
# If the uid and gid of the created user need to be set to specific values, in
# extra_vars.sh, set the variables
# STEAM_USER_UID
# STEAM_USER_GID
# Be aware that the default cloud lxd image usually gives a new user account
# the uid 1001 and gid 1003
export STEAM_USER_HOMEDIR="${STEAM_USER_HOMEDIR:-"/home/${STEAM_USER_NAME}"}"
export VALHEIM_DIR="${VALHEIM_DIR:-"${STEAM_USER_HOMEDIR}/valheim"}"
export VALHEIM_WORLD_DIR="${VALHEIM_WORLD_DIR:-"${STEAM_USER_HOMEDIR}/valheim-worlds"}"
# If this is changed, a line should be added in
# ./environment.yaml -> config: -> snapshots.schedule
# so that a snapshot of the container is taken first, and then the server in
# the container is stopped, updated, and restarted.
# In short, the snapshot.schedule setting needs to describe a time that comes
# before the VALHEIM_AUTO_UPDATE_SCHEDULE setting:
# If the server should be restarted daily at 2am, the container snapshot needs
# to be taken before that happens, so something like the following would work:
# snapshots.schedule           -> 55 1 * * *
# VALHEIM_AUTO_UPDATE_SCHEDULE -> *-*-* 02:00:00
# The value of VALHEIM_AUTO_UPDATE_SCHEDULE is used in an "OnCalendar="
# directive in a systemd.timer file. The following links have for more info:
# https://www.freedesktop.org/software/systemd/man/systemd.timer.html#OnCalendar=
# https://www.freedesktop.org/software/systemd/man/systemd.time.html#Calendar%20Events
# The format of snapshots.schedule is less flexible:
# Cron expression (<minute> <hour> <dom> <month> <dow>)
# It does not currently accept shortcuts like @daily
# See the links for more info:
# https://linuxcontainers.org/lxd/docs/master/instances#snapshot-scheduling
# https://cron.help/#1_5_*_*_1
#
# Also, in order for 2am in the container to be the same as 2am on the host,
# the timezones need to be set to the same value. The timezone in the container
# is set to the value of the TIMEZONE variable in this file (or the
# environment.yaml file, if set there), but the timezone of the host is never
# set. A common way to do this is to run the following command on the host:
# sudo timedatectl set-timezone "UTC"
#
# Where "UTC" can be replaced with the same timezone as is set in the
# container. This should keep the two in sync.
# To keep them in sync with reality, and your schedule, the NTP server on the
# host needs to be running and functional. One command that may make this happen
# is the following:
# sudo timedatectl set-ntp true
#
# But searching for "enable ntp <name of host computer's operating system>"
# will probably help more.
# As far as I know, lxd sets up the container to use the host's time
# information, so no NTP servers are configured in the container, nor need to
# be.
export VALHEIM_AUTO_UPDATE_SCHEDULE="${VALHEIM_AUTO_UPDATE_SCHEDULE:-"*-*-* 05:10:00"}"

### Almost definitely don't need to change these
export REMOTE_NAME="${REMOTE_NAME:-"valheim"}"
export CONTAINER_NAME="${CONTAINER_NAME:-"valheim"}"
export PROFILE_NAME="${PROFILE_NAME:-"${CONTAINER_NAME}"}"
export ENVIRONMENT_PROFILE_NAME="${ENVIRONMENT_PROFILE_NAME:-"${PROFILE_NAME}-environment"}"
export TEMPORARY_PROFILE_NAME="${TEMPORARY_OVERRIDE_FILE_NAME:-"${PROFILE_NAME}-temporary"}"
export FIRST_SNAPSHOT_NAME="${FIRST_SNAPSHOT_NAME:-"right-after-installation"}"
export LOGIN_ALIAS_NAME="${LOGIN_ALIAS_NAME:-"login"}"
export CONTAINER_STATUS_TIMEOUT="${CONTAINER_STATUS_TIMEOUT:-"20"}"
export LOG_PREFIX="${LOG_PREFIX-"--VALHEIM--"}" # allowed to be null

### Only change if the sources of these values have changed
# lxd constants
# https://lxd.readthedocs.io/en/latest/rest-api/#list-of-current-status-codes
export STOPPED_STATUS="102"
export RUNNING_STATUS="103"
# Steam Application ID constants
# https://steamdb.info/app/896660/
export VALHEIM_SERVER_APPID="896660"
# https://steamdb.info/app/892970/
export VALHEIM_GAME_APPID="892970"
export TRANSIENT_OVERRIDE_PATH="${TRANSIENT_OVERRIDE_PATH:-"${STEAM_USER_HOMEDIR}/systemd/user/valheim-update.service.d/"}"
# The lexicographic order of override files is important
export OVERRIDE_FILE_NAME="${OVERRIDE_FILE_NAME:-"10-override.conf"}"
export TEMPORARY_OVERRIDE_FILE_NAME="${TEMPORARY_OVERRIDE_FILE_NAME:-"90-temp.conf"}"

log() {
    printf '%s%s%s\n' "${LOG_PREFIX-}" "${LOG_PREFIX:+" "}" "$@"
}

error() {
    log "--ERROR--" "$@"
}

get_remote_ip() {
    set -eu
    if [ -z "${REMOTE_IP:+"unset"}" ]; then
        echo "what is the IP address of the server?
"
        read -r REMOTE_IP
    fi

    log "Remote IP address is ${REMOTE_IP}"
    export REMOTE_IP
}

need_command() {
    set -eu
    if [ "$#" -ne 1 ]; then
        error "need the name of 1 command"
        return 1
    fi

    if ! command -v "$1" > /dev/null 2>&1; then
        error "command '$1' not installed, or not found"
        return 1
    fi
}

# shellcheck disable=SC2120
need_lxc() {
    set -eu
    if [ "$#" -gt 0 ]; then
        error "doesn't take arguments"
        return 1
    fi

    if ! need_command lxc; then
        echo "installation instructions at:
https://linuxcontainers.org/lxd/getting-started-cli/#installation"
        return 1
    fi
}

ensure_remote_reachable() {
    set -eu
    need_lxc

    if [ "$#" -ne 1 ]; then
        error "ensure_remote_reachable: need 1 argument: REMOTE_NAME"
        exit 1
    fi

    if ! lxc list "$1:" > /dev/null 2>&1; then
        error "cannot reach lxd remote server named '$1'"
        return 1
    fi

    return 0
}

truthy() {
    set -eu
    if [ "$#" -lt 1 ]; then
        error "truthy given no parameters"
        exit 1
    fi

    case "${1:-}" in
        "") return 1;;
        0) return 1;;
        [fF][aA][lL][sS][eE]) return 1;;
        [nN][oO]) return 1;;
        *) return 0;;
    esac
}

lxd_container_status() {
    set -eu
    need_lxc
    need_command jq

    if [ "$#" -ne 2 ]; then
        error "lxd_container_status: need 2 arguments: REMOTE_NAME CONTAINER_NAME"
        exit 1
    fi

    CONTAINER_JSON="$(lxc list "$1:" --format json)"

    if ! printf '%s' "${CONTAINER_JSON}" | jq -re "map(.name == \"$2\") | any" > /dev/null 2>&1; then
        error "container '$1:$2' not found"
        exit 1
    fi

    if ! printf '%s' "${CONTAINER_JSON}" | jq -re "map(select(.name == \"$2\")) | .[] | has(\"status_code\")" > /dev/null 2>&1; then
        error "container '$1:$2' doesn't have a status_code???"
        exit 1
    fi

    printf '%s' "${CONTAINER_JSON}" | jq -re "map(select(.name == \"$2\")) | .[].status_code"
    unset -v CONTAINER_JSON
}

check_status_code() {
    set -eu
    if [ "$#" -ne 1 ]; then
        error "check_status_code: need 1 argument: STATUS_CODE"
        exit 1
    fi

    case "$1" in
        "${RUNNING_STATUS}")
            ;;
        "${STOPPED_STATUS}")
            ;;
        *)
            error "unkown status code '$1'"
            exit 1
            ;;
    esac

    return 0
}

wait_lxd_container_status() {
    set -eu
    need_command date

    if [ "$#" -ne 3 ]; then
        error "wait_lxd_container_status: need 3 arguments: REMOTE_NAME CONTAINER_NAME DESIRED_STATUS_CODE"
        exit 1
    fi

    case "$3" in
        "${RUNNING_STATUS}")
            STATUS_NAME="running"
            ;;
        "${STOPPED_STATUS}")
            STATUS_NAME="stopped"
            ;;
        *)
            error "unkown status code '$3'"
            exit 1
            ;;
    esac
    log "Waiting ${CONTAINER_STATUS_TIMEOUT} seconds for container '$1:$2' to be ${STATUS_NAME}"
    # shellcheck disable=SC2004
    TIMEOUT_DATE="$(($(date +%s)+${CONTAINER_STATUS_TIMEOUT}))"
    
    CONTAINER_STATUS="$(lxd_container_status "$1" "$2")"

    while [ "${CONTAINER_STATUS:--1}" -ne "$3" ]; do
        if [ "$(date +%s)" -gt "${TIMEOUT_DATE}" ]; then
            error "Timeout exceeded for container '$1:$2' to become ${STATUS_NAME}"
            exit 1
        else
            sleep 1
        fi
        CONTAINER_STATUS="$(lxd_container_status "$1" "$2")"
    done
    unset -v CONTAINER_STATUS
    unset -v TIMEOUT_DATE

    case "$3" in
        "${RUNNING_STATUS}")
            log "Wait for systemd to indicate system is running..."
            if ! SYSTEMD_STATE="$(lxc "exec" "$1:$2" -- systemctl is-system-running --wait)" \
                || [ "${SYSTEMD_STATE}" != "running" ]
            then
                error "container '$1:$2' in bad state: '${SYSTEMD_STATE}'"
                exit 1
            fi
            unset -v SYSTEMD_STATE

            # https://linuxcontainers.org/lxd/advanced-guide/#cloud-init-status
            log "Wait for cloud-init to finish..."
            lxc "exec" "$1:$2" -- cloud-init status --wait > /dev/null 2>&1
            ;;
        *)
            # Nothing to do
            ;;
    esac

    log "container '$1:$2' now ${STATUS_NAME}"
    unset -v STATUS_NAME

    return 0
}

sync_vars() {
    set -eu
    need_command python3

    # prints out the environment variables set here in a way that can be
    # executed by the shell this function is run in, to modify that shell's
    # environment
    python3 <<EOF
import os
from shlex import quote

variable_names = [
    "TIMEZONE",
    "VALHEIM_START_PORT",
    "VALHEIM_END_PORT",
    "VALHEIM_WORLD_NAME",
    "VALHEIM_WORLD_FILE_NAME",
    "VALHEIM_SERVER_IS_PUBLIC",
    "VALHEIM_PUBLICNESS_VALUE",
    "VALHEIM_PASSWORD",
    "VALHEIM_SHOULD_AUTO_UPDATE",
    "VALHEIM_AUTO_UPDATE_SCHEDULE",
]


def print_env(var: str) -> None:
    """
    prints the environment variable named in var in a way that can be executed
    by the calling shell
    """
    value = os.getenv(var, None)
    print(f"export {var}={quote(value)}", flush=True)


for variable_name in variable_names:
    print_env(variable_name)
EOF
}

### Calculated constants
if truthy "${VALHEIM_SERVER_IS_PUBLIC}"; then
    VALHEIM_PUBLICNESS_VALUE="1"
else
    VALHEIM_PUBLICNESS_VALUE="-1"
fi
export VALHEIM_PUBLICNESS_VALUE
export TEMPORARY_OVERRIDE_FILE="${TRANSIENT_OVERRIDE_PATH}/${TEMPORARY_OVERRIDE_FILE_NAME}"
# shellcheck disable=SC2004
export VALHEIM_END_PORT="$((${VALHEIM_START_PORT}+2))"

### Load overrides
if [ -r "/etc/extra_vars/extra_vars.sh" ]; then
    # shellcheck disable=SC1091
    . /etc/extra_vars/extra_vars.sh
fi
if [ -r "./extra_vars.sh" ]; then
    # shellcheck disable=SC1091
    . ./extra_vars.sh
fi

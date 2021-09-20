#!/bin/sh
set -eu
# shellcheck source=vars.sh
. /usr/local/bin/vars.sh

if [ "$(id -u)" -eq "${STEAM_USER_UID:-""}" ]; then
    journalctl -mfo cat \
        --user-unit=valheim.service \
        --user-unit=valheim-update.service \
        --user-unit=valheim-update.timer
elif [ "$(id -u)" -eq 0 ]; then
    runuser -u "${STEAM_USER_NAME:-"steam"}" -- journalctl -mfo cat \
        --user-unit=valheim.service \
        --user-unit=valheim-update.service \
        --user-unit=valheim-update.timerelse
else
    error "This script can only be run as root or the user named '${STEAM_USER_NAME:-"steam"}'"
    exit 1
fi

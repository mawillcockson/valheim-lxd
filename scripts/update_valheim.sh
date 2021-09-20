#!/bin/sh
set -eu
# shellcheck source=vars.sh
. /usr/local/bin/vars.sh

log "Updating Valheim...
This doesn't show any output while running"

if [ "$(id -u)" -eq "${STEAM_USER_UID:-""}" ]; then
    systemctl --user start valheim-update.service
elif [ "$(id -u)" -eq 0 ]; then
    runuser -u "${STEAM_USER_NAME:-"steam"}" -- systemctl --user start valheim-update.service
else
    error "This script can only be run as root or the user named '${STEAM_USER_NAME:-"steam"}'"
    exit 1
fi

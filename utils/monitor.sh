#!/bin/sh
set -eu
. ./vars.sh

lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh <<EOF
set -eu
. /usr/local/bin/vars.sh

shutdown() {
    set +ue
    kill "\${LOG_WATCH_PID}"
    kill "\${TOP_PID}"
}

sudo -u "${STEAM_USER_NAME}" journalctl -fo cat \
    --user-unit=valheim-update.service \
    --user-unit=valheim-update.timer \
    --user-unit=valheim.service &
LOG_WATCH_PID="\$!"
if [ "\$?" -ne 0 ]; then
    error "error starting log watcher"
    shutdown
    exit 1
fi
# export returns it's own exit code, so do this in a different step
export LOG_WATCH_PID

#top -b &
#TOP_PID="\$!"
#if [ "\$?" -ne 0 ]; then
#    error "could not start top"
#    shutdown
#    exit 1
#fi
#export TOP_PID

trap shutdown INT TERM KILL

wait "\${LOG_WATCH_PID}"
#wait "\${TOP_PID}"
EOF

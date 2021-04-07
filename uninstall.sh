#!/bin/sh
# shellcheck shell=sh
set -eu

. ./vars.sh

need_lxc
need_command jq
need_command date

USAGE="usage: $0 [-a]
delete the container, all snapshots, and the profile

-a
   remove ALL images from remote named '${REMOTE_NAME}',
   remove the remote from the local list of remotes,
   remove alias named 'login'
"

if [ "$#" -gt 1 ]; then
    echo "${USAGE}"
    exit 1
elif [ "$#" -eq 1 ] && [ "$1" != "-a" ]; then
    echo "${USAGE}"
    exit 1
fi

log "Checking if a remote named '${CONTAINER_NAME}' exists..."
if lxc remote list --format json | jq -re "has(\"${REMOTE_NAME}\")" > /dev/null 2>&1; then
    ensure_remote_reachable "${REMOTE_NAME}"
else
    error "No remote named '${REMOTE_NAME}'"
    exit 1
fi

log "Checking for remote profile named '${PROFILE_NAME}'..."
PROFILE_JSON="$(lxc profile list "${REMOTE_NAME}:" --format json )"
PROFILE_EXISTS="$(printf '%s' "${PROFILE_JSON}" | jq -r "map(.name == \"${PROFILE_NAME}\") | any")"
if truthy "${PROFILE_EXISTS}"; then
    log "Remove deletion protection"
    lxc profile "set" "${REMOTE_NAME}:${PROFILE_NAME}" security.protection.delete "false"
fi

log "Removing snapshots for remote container '${CONTAINER_NAME}'..."
for snapshot_name in $(lxc list "${REMOTE_NAME}:" --format json | jq -r ".[] | select(.name == \"${CONTAINER_NAME}\") | .snapshots[]?.name"); do
    lxc delete "${REMOTE_NAME}:${CONTAINER_NAME}/${snapshot_name}"
done

log "Checking for remote container '${CONTAINER_NAME}'..."
if lxc list "${REMOTE_NAME}:" --format json | jq -e "map(.name == \"${CONTAINER_NAME}\") | any" > /dev/null 2>&1; then
    if [ "$(lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}")" -eq "${RUNNING_STATUS}" ]; then
        log "Stop remote container '${CONTAINER_NAME}'"
        lxc "stop" "${REMOTE_NAME}:${CONTAINER_NAME}"
        wait_lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}" "${STOPPED_STATUS}"
    fi
    log "Remove remote container '${CONTAINER_NAME}'"
    lxc delete "${REMOTE_NAME}:${CONTAINER_NAME}"
fi

log "Checking for remote profile '${PROFILE_NAME}'..."
if truthy "${PROFILE_EXISTS}"; then
    log "Remove remote profile named '${PROFILE_NAME}'"
    lxc profile delete "${REMOTE_NAME}:${PROFILE_NAME}"
fi
unset -v PROFILE_EXISTS

log "Checking for remote profile '${ENVIRONMENT_PROFILE_NAME}'..."
if printf '%s' "${PROFILE_JSON}" | jq -re "map(.name == \"${ENVIRONMENT_PROFILE_NAME}\") | any" > /dev/null 2>&1; then
    log "Removing remote profile '${ENVIRONMENT_PROFILE_NAME}'..."
    lxc profile delete "${REMOTE_NAME}:${ENVIRONMENT_PROFILE_NAME}"
fi
unset -v PROFILE_JSON

if [ "$#" -lt 1 ] || [ "$1" != "-a" ]; then
    log "Uninstallation finished"
    exit 0
fi

log "Removing all images on the server..."
for fingerprint in $(lxc image list "${REMOTE_NAME}:" --format json | jq -re '.[].fingerprint'); do
    lxc image delete "${REMOTE_NAME}:${fingerprint}"
done

log "Remove lxd remote named '${REMOTE_NAME}'"
lxc remote remove "${REMOTE_NAME}"

log "Checking for alias 'login'..."
if lxc "alias" list --format json | jq -re 'has("login")'; then
    log "Remove 'login' alias"
    lxc "alias" remove "login"
fi

log "Uninstallation finished"

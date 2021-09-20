#!/bin/sh
# shellcheck shell=sh
# This steals steps from:
# https://developer.valvesoftware.com/wiki/SteamCMD#Package_from_repositories
# https://github.com/CM2Walki/steamcmd/blob/master/buster/Dockerfile
# https://askubuntu.com/a/1017487
# https://github.com/mbround18/valheim-docker
# https://github.com/lloesche/valheim-server-docker
set -eu

. ./vars.sh

need_lxc
need_command jq
need_command basename
need_command date

# NOTE: this assumes that, if the alias already exists, it's the same as the
# one it would have created
log "Checking for alias '${LOGIN_ALIAS_NAME}'..."
if ! lxc alias list --format json | jq -re "has(\"${LOGIN_ALIAS_NAME}\")" > /dev/null 2>&1; then
    log "Adding alias '${LOGIN_ALIAS_NAME}' to lxc
use as:

lxc ${LOGIN_ALIAS_NAME} '${REMOTE_NAME}:${CONTAINER_NAME}' --env USER=${STEAM_USER_NAME}"
    # shellcheck disable=SC2016
    lxc alias add "${LOGIN_ALIAS_NAME}" 'exec @ARGS@ --mode interactive -- /bin/sh -xac $@${USER:-root} - exec /bin/login -p -f '
    # This needs no quoting, since lxc breakes up the parts after -- by spaces,
    # and passes them all as individual parameters to /bin/sh
    # From:
    # https://discuss.linuxcontainers.org/t/useful-lxc-command-aliases/2547/4
fi

log "Checking for remote '${REMOTE_NAME}'..."
if ! lxc remote list --format json | jq -re "has(\"${REMOTE_NAME}\")" > /dev/null 2>&1; then
    if [ -z "${REMOTE_IP:+"unset"}" ]; then
        echo "
This requires a remote computer running the LXD. For more information, see:

https://github.com/mawillcockson/valheim-lxd

About 3.5 GB of hard drive space is needed on the host, and about 3 GB of RAM

On the remote computer, run the following commands to install LXD:
sudo -i
apt install snapd
. /etc/profile.d/apps-bin-path.sh
snap install core
snap install lxd
lxd init

For the last command, answer 'yes' to remote, using the default port of 8443

The IP address of the remote computer is needed. To find it, run any one of the following commands, on the remote computer:

wget -4qO- https://api.ipify.org
curl -sS4  https://api.ipify.org
python3 -c \"import urllib.request as u;print(u.urlopen('https://api.ipify.org').read().decode())\"

IPv6 addresses must be enclosed in square brackets:

[2001:db8::1]

press [Enter] to continue once this is done"
        # shellcheck disable=SC2034
        read -r NONE

        get_remote_ip
    fi

    log "Adding lxd remote as '${REMOTE_NAME}'"
    lxc remote add "${REMOTE_NAME}" "https://${REMOTE_IP}"
fi

ensure_remote_reachable "${REMOTE_NAME}"

log "Checking for profile named '${PROFILE_NAME}' on remote named '${REMOTE_NAME}'..."
if ! lxc profile list "${REMOTE_NAME}:" --format json | jq -re "map(.name == \"${PROFILE_NAME}\") | any" > /dev/null 2>&1; then
    log "Creating profile '${PROFILE_NAME}'"
    # NOTE: used to have a bug where the profile was directed into the "create"
    # command
    # "lxc profile create" ignores stdin, even though it allows it
    lxc profile create "${REMOTE_NAME}:${PROFILE_NAME}"
    lxc profile edit "${REMOTE_NAME}:${PROFILE_NAME}" < ./lxd/default-valheim.profile.yaml

    log "Setting proxy ports..."
    lxc profile device set "${REMOTE_NAME}:${CONTAINER_NAME}" proxy \
        "listen=udp:0.0.0.0:${VALHEIM_START_PORT}-${VALHEIM_END_PORT}" \
        "connect=udp:127.0.0.1:${VALHEIM_START_PORT}-${VALHEIM_END_PORT}"
fi

log "Checking for environment.yaml..."
if [ -r ./environment.yaml ]; then
    log "Validating environment.yaml..."

    log "Checking for old temporary profile named '${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}'..."
    if lxc profile list "${REMOTE_NAME}:" --format json \
        | jq -re "map(.name == \"${TEMPORARY_PROFILE_NAME}\") | any" > /dev/null 2>&1; then
        log "Removing old temporary profile '${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}'..."
        lxc profile delete "${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}"
    fi

    log "Creating temporary profile named '${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}'..."
    lxc profile create "${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}"
    lxc profile edit "${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}" < ./environment.yaml

    log "Checking for required keys..."
    PROFILE_JSON="$(lxc profile list "${REMOTE_NAME}:" --format json)"
    for key in TIMEZONE VALHEIM_PASSWORD VALHEIM_SERVER_IS_PUBLIC VALHEIM_WORLD_FILE_NAME VALHEIM_WORLD_NAME; do
        # Check for required environment variables
        if ! printf '%s' "${PROFILE_JSON}" \
            | jq -re "map(select(.name == \"${TEMPORARY_PROFILE_NAME}\")) \
                      | .[].config | has(\"environment.${key}\")" > /dev/null 2>&1; then
            error "environment.yaml missing key 'environment.${key}'"
            exit 1
        fi
    done
    log "environment.yaml appears to be valid"

    log "Removing temporary profile '${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}'..."
    lxc profile delete "${REMOTE_NAME}:${TEMPORARY_PROFILE_NAME}"

    log "Checking for remote environment profile named '${ENVIRONMENT_PROFILE_NAME}'"
    if ! printf '%s' "${PROFILE_JSON}" \
        | jq -re "map(.name == \"${ENVIRONMENT_PROFILE_NAME}\") | any" > /dev/null 2>&1; then
        log "Creating profile '${REMOTE_NAME}:${ENVIRONMENT_PROFILE_NAME}'..."
        lxc profile create "${REMOTE_NAME}:${ENVIRONMENT_PROFILE_NAME}"
    fi

    unset -v PROFILE_JSON

    log "Uploading environment.yaml to profile '${REMOTE_NAME}:${ENVIRONMENT_PROFILE_NAME}'"
    lxc profile edit "${REMOTE_NAME}:${ENVIRONMENT_PROFILE_NAME}" < ./environment.yaml
else
    log "Checking for remote environment profile named '${ENVIRONMENT_PROFILE_NAME}'"
    if ! lxc profile list "${REMOTE_NAME}:" --format json \
        | jq -re "map(.name == \"${ENVIRONMENT_PROFILE_NAME}\") | any" > /dev/null 2>&1; then
        error "Missing environment.yaml, and no profile on remote" \
               "'${REMOTE_NAME}:' named '${ENVIRONMENT_PROFILE_NAME}'
Please see the README for information on the environment.yaml file"
        exit 1
    fi
fi

log "Checking for container '${REMOTE_NAME}:${CONTAINER_NAME}'..."
if lxc list "${REMOTE_NAME}:" --format json | jq -re "map(.name == \"${CONTAINER_NAME}\") | any" > /dev/null 2>&1; then
    if [ "$(lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}")" -ne "${RUNNING_STATUS}" ]; then
        lxc start "${REMOTE_NAME}:${CONTAINER_NAME}"
    fi
else
# If there isn't an instance with the name ${CONTAINER_NAME}, create it
    log "Installing and starting container '${REMOTE_NAME}:${CONTAINER_NAME}'"
    lxc launch "images:ubuntu/20.04/cloud" "${REMOTE_NAME}:${CONTAINER_NAME}" \
        -p default \
        -p "${PROFILE_NAME}" \
        -p "${ENVIRONMENT_PROFILE_NAME}"
fi

wait_lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}" "${RUNNING_STATUS}"

log "Installing vars.sh"
lxc file push ./vars.sh "${REMOTE_NAME}:${CONTAINER_NAME}/usr/local/bin/vars.sh" --mode 0755 --gid 0 --uid 0

log "Checking for extra_vars.sh..."
if [ -r "./extra_vars.sh" ]; then
    log "Install extra_vars.sh"
    lxc file push ./extra_vars.sh "${REMOTE_NAME}:${CONTAINER_NAME}/etc/extra_vars/extra_vars.sh" \
        --create-dirs \
        --mode 0755 \
        --gid 0 \
        --uid 0
fi

log "Installing packages"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh << EOF
set -eu
. /usr/local/bin/vars.sh

log "Pre-answering steam license agreement"
debconf-set-selections <<XXEOFXX
steam steam/question select I AGREE
steam steam/license note ''
XXEOFXX

log "Installing required packages"
add-apt-repository multiverse
dpkg --add-architecture i386
apt-get update -y
export DEBIAN_FRONTEND=noninteractive
apt-get dist-upgrade -y
apt-get install -y --no-install-recommends --no-install-suggests \
     lib32stdc++6 \
     lib32gcc1 \
     ca-certificates \
     libsdl2-2.0-0 \
     libsdl2-2.0-0:i386 \
     steamcmd \
     python3 \
     nano
EOF

log "Syncing environment variables..."
SYNCED_ENVIRONMENT_VARIABLES="$(lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh -c ". /usr/local/bin/vars.sh; sync_vars")"
export SYNCED_ENVIRONMENT_VARIABLES
eval "${SYNCED_ENVIRONMENT_VARIABLES}"

log "Creating account for '${STEAM_USER_NAME}'"

log "Checking if STEAM_USER_UID and STEAM_USER_GID are set"
if { [ -n "${STEAM_USER_UID:+"set"}" ] && [ -z "${STEAM_USER_GID:+"unset"}" ] ; } \
    || { [ -z "${STEAM_USER_UID:+"unset"}" ] && [ -n "${STEAM_USER_GID:+"set"}" ] ; }
    then
    error "both STEAM_USER_UID and STEAM_USER_GID need to be set, or both need to be left unset"
    exit 1
fi

if [ -n "${STEAM_USER_UID:+"set"}" ] && [ -n "${STEAM_USER_GID:+"set"}" ]; then
    log "using
STEAM_USER_UID -> '${STEAM_USER_UID}'
STEAM_USER_GID -> '${STEAM_USER_GID}'"

    # Group must exist first if useradd is called with --gid argument
    log "Checking for existing group '${STEAM_USER_NAME}'"
    if ! lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- getent group "${STEAM_USER_NAME}" > /dev/null 2>&1; then
        log "Creating group '${STEAM_USER_NAME}'..."
        lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- \
            groupadd -g "${STEAM_USER_GID}" "${STEAM_USER_NAME}"
    fi

    log "Checking for existing user '${STEAM_USER_NAME}'..."
    if ! lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- getent passwd "${STEAM_USER_NAME}" > /dev/null 2>&1; then
        log "Creating user '${STEAM_USER_NAME}'..."
        lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- \
             useradd --uid "${STEAM_USER_UID}" \
                     --gid "${STEAM_USER_GID}" \
                     --create-home --home-dir "${STEAM_USER_HOMEDIR}" \
                     --shell /bin/bash \
                     "${STEAM_USER_NAME}"
    fi
else
    log "Checking for existing group '${STEAM_USER_NAME}'"
    GROUP_EXISTS="$(lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- getent group "${STEAM_USER_NAME}" > /dev/null 2>&1 \
        && echo "yes" || echo "no")"
    USER_EXISTS="$(lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- getent passwd "${STEAM_USER_NAME}" > /dev/null 2>&1 \
        && echo "yes" || echo "no")"
    export GROUP_EXISTS
    export USER_EXISTS

    if truthy "${GROUP_EXISTS}" && ! truthy "${USER_EXISTS}"; then
        error "group '${STEAM_USER_NAME}' created without user"
        exit 1
    elif ! truthy "${GROUP_EXISTS}" && truthy "${USER_EXISTS}"; then
        error "user '${STEAM_USER_NAME}' created without group"
        exit 1
    fi

    if ! truthy "${GROUP_EXISTS}" && ! truthy "${USER_EXISTS}"; then
        log "Creating user '${STEAM_USER_NAME}'..."
        lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- \
             useradd --create-home --home-dir "${STEAM_USER_HOMEDIR}" \
                     --shell /bin/bash \
                     "${STEAM_USER_NAME}"
    fi
fi

log "Setting STEAM_USER_UID and STEAM_USER_GID"
STEAM_USER_UID="$(lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- id -ru "${STEAM_USER_NAME}")"
STEAM_USER_GID="$(lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- id -rg "${STEAM_USER_NAME}")"
log "STEAM_USER_UID -> '${STEAM_USER_UID}'"
log "STEAM_USER_GID -> '${STEAM_USER_GID}'"

log "Ensuring STEAM_USER_UID, STEAM_USER_GID, and XDG_RUNTIME_DIR are set in uploaded vars.sh"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh << EOF
set -eu
. /usr/local/bin/vars.sh

log "Adding STEAM_USER_UID..."
if [ -z "\${STEAM_USER_UID:+"unset"}" ]; then
    printf "### Computed STEAM_USER_UID
export STEAM_USER_UID='%s'
" "${STEAM_USER_UID}" >> /usr/local/bin/vars.sh
fi

log "Adding STEAM_USER_GID..."
if [ -z "\${STEAM_USER_GID:+"unset"}" ]; then
    printf "### Computed STEAM_USER_GID
export STEAM_USER_GID='%s'
" "${STEAM_USER_GID}" >> /usr/local/bin/vars.sh
fi

# systemctl --user complains due to the unit file running outside the context
# of a user's environment:
# https://serverfault.com/a/937012
# Don't want to set it on the local computer, as that might mess with systemctl
# after this script is finished running
log "Adding XDG_RUNTIME_DIR..."
if [ -z "\${XDG_RUNTIME_DIR:+"unset"}" ]; then
    export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-"/run/user/${STEAM_USER_UID}"}"
    printf "### Computed XDG_RUNTIME_DIR
export XDG_RUNTIME_DIR='%s'
" "\${XDG_RUNTIME_DIR}" >> /usr/local/bin/vars.sh
fi
EOF

# NOTE: until lingering is enabled and the systemd user daemon is started, if
# the user is not logged in, the daemon isn't running.
# lxc login '${REMOTE_NAME}:${CONTAINER_NAME}' --env USER='${STEAM_USER_NAME}'
# works because /bin/login starts the systemd user daemon
# exec-ing /bin/sh does not
log "Enable and start systemd user service manager for '${STEAM_USER_NAME}'"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- loginctl --no-ask-password enable-linger "${STEAM_USER_NAME}"

log "Start user systemd manager"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- systemctl --no-ask-password restart "user@${STEAM_USER_UID}.service"

log "Setting passwords for root, ubuntu, and ${STEAM_USER_NAME} users to blank..."
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- chpasswd -c NONE << EOF
root:
ubuntu:
${STEAM_USER_NAME}:
EOF

lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- sudo -u "${STEAM_USER_NAME}" /bin/sh << EOF
. /usr/local/bin/vars.sh
log "Running edited vars.sh..."

log "Checking if variables were set appropriately..."
if [ "x${STEAM_USER_UID}x" != "x\${STEAM_USER_UID}x" ]; then
    error "UIDs do not match:
remote STEAM_USER_UID: '\${STEAM_USER_UID}'
local  STEAM_USER_UID: '${STEAM_USER_UID}'"
    exit 1
elif [ "x${STEAM_USER_GID}x" != "x\${STEAM_USER_GID}x" ]; then
    error "GIDs do no match:
remote STEAM_USER_GID: '\${STEAM_USER_GID}'
local  STEAM_USER_GID: '${STEAM_USER_GID}'"
    exit 1
elif [ -z "\${XDG_RUNTIME_DIR:+"unset"}" ] ||
    ! systemctl --no-ask-password --user --dry-run --quiet exit
    then
    # XDG_RUNTIME_DIR was written to vars.sh, and that was sourced, and
    # XDG_RUNTIME_DIR is not set after sourcing it
    error "setting XDG_RUNTIME_DIR in the container did not work"
    exit 1
fi
EOF

log "Configuring user '${STEAM_USER_NAME}' filesystem"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- sudo -u "${STEAM_USER_NAME}" /bin/sh << EOF
set -eu
. /usr/local/bin/vars.sh

log "Making directories..."
for dir in "${VALHEIM_DIR}" "${VALHEIM_WORLD_DIR}"; do
    mkdir -p "\${dir}"
done

# Appears not to be needed, as long as LD_LIBRARY_PATH is set for the server
# executable environemnt
## SteamCMD installs a 32-bit .so, valheim needs 64-bit
#log "Fix mismatching steamclient.so"
#cp "${VALHEIM_DIR}/linux64/steamclient.so" "${VALHEIM_DIR}/steamclient.so"
EOF

log "Checking for existing worlds files..."
if [ -f "./${VALHEIM_WORLD_FILE_NAME}.fwl" ] && [ ! -f "./${VALHEIM_WORLD_FILE_NAME}.db" ]; then
    error "Missing '${VALHEIM_WORLD_FILE_NAME}.db' file"
    exit 1
elif [ -f "./${VALHEIM_WORLD_FILE_NAME}.db" ] && [ ! -f "./${VALHEIM_WORLD_FILE_NAME}.fwl" ]; then
    error "Missing '${VALHEIM_WORLD_FILE_NAME}.fwl' file"
    exit 1
elif [ -r "./${VALHEIM_WORLD_FILE_NAME}.db" ] && [ -r "./${VALHEIM_WORLD_FILE_NAME}.db" ]; then
    log "Upload '${VALHEIM_WORLD_FILE_NAME}.db'"
    lxc file push "./${VALHEIM_WORLD_FILE_NAME}.db" \
        "${REMOTE_NAME}:${CONTAINER_NAME}${VALHEIM_WORLD_DIR}/" \
        --gid "${STEAM_USER_GID}" \
        --uid "${STEAM_USER_UID}"

    log "Upload '${VALHEIM_WORLD_FILE_NAME}.fwl'"
    lxc file push "./${VALHEIM_WORLD_FILE_NAME}.fwl" \
        "${REMOTE_NAME}:${CONTAINER_NAME}${VALHEIM_WORLD_DIR}/" \
        --gid "${STEAM_USER_GID}" \
        --uid "${STEAM_USER_UID}"
fi

log "Fill out override files..."
# For an explanation of the following:
# https://www.freedesktop.org/software/systemd/man/systemd.unit.html#id-1.14.3
log "Make override folders..."
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- sudo -u "${STEAM_USER_NAME}" /bin/sh <<EOF
set -eu
. /usr/local/bin/vars.sh

for file in valheim.service valheim-update.service valheim-update.timer; do
    mkdir -p "${STEAM_USER_HOMEDIR}/.config/systemd/user/\${file}.d/"
done
EOF

log "Installing systemd files..."
for path in ./systemd-unit-files/*.service ./systemd-unit-files/*.timer; do
    # Ownership is adjusted later
    file="$(basename "${path}")"
    lxc file push "${path}" "${REMOTE_NAME}:${CONTAINER_NAME}${STEAM_USER_HOMEDIR}/.config/systemd/user/${file}" --mode 0644
done

log "Override valheim.service"
# Ownership is adjusted later
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh -c \
    "cat > \"${STEAM_USER_HOMEDIR}/.config/systemd/user/valheim.service.d/${OVERRIDE_FILE_NAME}\"" <<EOF
[Service]
Environment=
Environment=LD_LIBRARY_PATH="${VALHEIM_DIR}/linux64"
Environment=SteamAppId="${VALHEIM_GAME_APPID}"
ExecStart=
ExecStart=${VALHEIM_DIR}/valheim_server.x86_64 \\
    -name "${VALHEIM_WORLD_NAME}" \\
    -port "${VALHEIM_START_PORT}" \\
    -world "${VALHEIM_WORLD_FILE_NAME}" \\
    -password "${VALHEIM_PASSWORD}" \\
    -savedir "${VALHEIM_WORLD_DIR}" \\
    -public "${VALHEIM_PUBLICNESS_VALUE}" \\
    -nographics \\
    -batchmode
EOF

log "Override valheim-update.service"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh -c \
    "cat > \"${STEAM_USER_HOMEDIR}/.config/systemd/user/valheim-update.service.d/${OVERRIDE_FILE_NAME}\"" <<EOF
[Service]
Environment=
Environment=XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
ExecStart=
ExecStart=/usr/games/steamcmd \\
    +login anonymous \\
    +force_install_dir "${VALHEIM_DIR}" \\
    +app_update "${VALHEIM_SERVER_APPID}" \\
    +quit ; \\
    /bin/sh -c '. /usr/local/bin/vars.sh; log "Finished updating valheim"'
EOF

log "Override valheim-update.timer"
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh -c \
    "cat > \"${STEAM_USER_HOMEDIR}/.config/systemd/user/valheim-update.timer.d/${OVERRIDE_FILE_NAME}\"" <<EOF
[Timer]
OnCalendar=
OnCalendar=${VALHEIM_AUTO_UPDATE_SCHEDULE}
EOF

log "Configuring container as root..."
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- /bin/sh <<EOF
set -eu
. /usr/local/bin/vars.sh

log "Update file ownership on user services for '${STEAM_USER_NAME}'..."
chown -R "${STEAM_USER_UID}:${STEAM_USER_GID}" "${STEAM_USER_HOMEDIR}/.config/systemd/user/"

log "Setting timezone to '${TIMEZONE}'
Make sure that the timezone of the container and the host match, so that the
automatic snapshotting done by lxd happens before the server is updated"
timedatectl --no-ask-password set-timezone "${TIMEZONE}"

log "Reloading system systemd..."
systemctl --system --no-ask-password daemon-reload
EOF

log "Finishing configuring container as '${STEAM_USER_NAME}'..."
lxc exec "${REMOTE_NAME}:${CONTAINER_NAME}" -- sudo -u "${STEAM_USER_NAME}" /bin/sh <<EOF
set -eu
. /usr/local/bin/vars.sh

need_command ps

log "Installing Valheim Dedicated Server
This will probably take a while"

log "Installing temporary override..."
mkdir -p "${TRANSIENT_OVERRIDE_PATH}"
echo "[Service]" > "${TEMPORARY_OVERRIDE_FILE}"
echo "ExecStartPost=" >> "${TEMPORARY_OVERRIDE_FILE}"

log "Reloading user systemd manager..."
systemctl --user --no-ask-password daemon-reload

log "Starting installation log watcher..."
journalctl -fo cat --user-unit=valheim-update.service &
LOG_WATCH="\$!"
tail -F ~/.steam/logs/stderr.txt &
STEAM_WATCH="\$!"
sleep 0.5 # wait to see if the watchers stop
if ! { ps --pid "\${LOG_WATCH}" > /dev/null 2>&1 && ps --pid "\${STEAM_WATCH}" > /dev/null 2>&1 ; } ; then
    error "could not start log watchers"
    exit 1
fi

stop_watchers() {
    if [ -n "\${LOG_WATCH:+"set"}" ]; then
        kill "\${LOG_WATCH}" > /dev/null 2>&1 || true
    fi
    if [ -n "\${STEAM_WATCH:+"set"}" ]; then
        kill "\${STEAM_WATCH}" > /dev/null 2>&1 || true
    fi
}

trap stop_watchers EXIT

log "Starting Valheim Dedicated Server installation..."
if ! systemctl --user --wait --no-ask-password start valheim-update.service; then
    error "Error installing Valheim Dedicated Server"
    exit 1
fi

trap - EXIT
stop_watchers

log "Remove temporary override"
rm "${TEMPORARY_OVERRIDE_FILE}"

log "Reloading user service manager..."
systemctl --user --no-ask-password daemon-reload

log "Installing valheim done"

log "Starting and enabling services and timers"
systemctl --user --no-ask-password enable valheim.service
if truthy "\${VALHEIM_SHOULD_AUTO_UPDATE}"; then
    log "Starting auto update service, Valheim Dedicated Server will be started once done"
    systemctl --user --no-ask-password enable valheim-update.timer
    systemctl --user --no-ask-password start valheim-update.timer
else
    log "Starting Valheim Dedicated Server"
    systemctl --user --no-ask-password start valheim.service
fi
EOF

log "Adding scripts..."
for file in update_valheim.sh watch_valheim_logs.sh show_valheim_logs.sh; do
    if ! [ -r "./scripts/${file}" ]; then
        error "Cannot find upload script: './script/${file}'"
        exit 1
    fi
    log "Uploading '${file}'..."
    lxc file push "./scripts/${file}" "${REMOTE_NAME}:${CONTAINER_NAME}/usr/local/bin/${file}" \
        --mode 0755 \
        --uid 0 \
        --gid 0
done

if ! truthy "${VALHEIM_SHOULD_AUTO_UPDATE}"; then
    log "To update the Valheim Dedicated Server manually, run the following command:

lxc exec '${REMOTE_NAME}:${CONTAINER_NAME}' -- update_valheim.sh

This won't show any progress, and will only show whether the update succeeded
or failed.

The logs for this can be viewed with:

lxc exec '${REMOTE_NAME}:${CONTAINER_NAME}' -- show_valheim_logs.sh

Scroll with the arrow keys, and exit by pressing q
"
fi

if lxc list "${REMOTE_NAME}:${CONTAINER_NAME}" --format json \
    | jq -re "[.[].snapshots[].name == \"${FIRST_SNAPSHOT_NAME}\"] | any" > /dev/null 2>&1
    then
    log "Creating a snapshot of '${REMOTE_NAME}:${CONTAINER_NAME}'
To see a list of snapshots, run:

lxc info '${REMOTE_NAME}:${CONTAINER_NAME}'

To rollback to any of them, run:

lxc restore '${REMOTE_NAME}:${CONTAINER_NAME}' '<name of snapshot>'"
    lxc stop "${REMOTE_NAME}:${CONTAINER_NAME}"
    wait_lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}" "${STOPPED_STATUS}"
    lxc snapshot "${REMOTE_NAME}:${CONTAINER_NAME}"
    lxc start "${REMOTE_NAME}:${CONTAINER_NAME}"
    wait_lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}" "${RUNNING_STATUS}"
else
    log "Creating a snapshot of '${REMOTE_NAME}:${CONTAINER_NAME}' named '${FIRST_SNAPSHOT_NAME}'

    To rollback to this snapshot, run:

    lxc restore '${REMOTE_NAME}:${CONTAINER_NAME}' '${FIRST_SNAPSHOT_NAME}'
    "
    lxc stop "${REMOTE_NAME}:${CONTAINER_NAME}"
    wait_lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}" "${STOPPED_STATUS}"
    lxc snapshot "${REMOTE_NAME}:${CONTAINER_NAME}" "${FIRST_SNAPSHOT_NAME}"
    lxc start "${REMOTE_NAME}:${CONTAINER_NAME}"
    wait_lxd_container_status "${REMOTE_NAME}" "${CONTAINER_NAME}" "${RUNNING_STATUS}"
fi

log "Server should be running

To monitor resource usage, run:

lxc exec '${REMOTE_NAME}:${CONTAINER_NAME}' -- top

press q to exit

To monitor the logs for the running valheim server, run:

lxc exec '${REMOTE_NAME}:${CONTAINER_NAME}' -- watch_valheim_logs.sh

To pull the world files, first make sure the container is stopped by running:

lxc stop '${REMOTE_NAME}:${CONTAINER_NAME}'

If the container isn't stopped, the server may still be updating the world
files when they're copied.

Then keep checking the next command until it says the 'STATE' is 'STOPPED':

lxc list '${REMOTE_NAME}:${CONTAINER_NAME}' --columns ns

Then run the following commands to download the world files into the current directory:

lxc file pull '${REMOTE_NAME}:${CONTAINER_NAME}${VALHEIM_WORLD_DIR}/${VALHEIM_WORLD_FILE_NAME}.fwl' ./
lxc file pull '${REMOTE_NAME}:${CONTAINER_NAME}${VALHEIM_WORLD_DIR}/${VALHEIM_WORLD_FILE_NAME}.db' ./

To log in as the steam user named '${STEAM_USER_NAME}', use the installed lxc alias '${LOGIN_ALIAS_NAME}':

lxc ${LOGIN_ALIAS_NAME} '${REMOTE_NAME}:${CONTAINER_NAME}' --env USER=${STEAM_USER_NAME}

To add someone to the admin list, watch the server log for a line like the following, as that person logs into the world:

(Filename: ./Runtime/Export/Debug/Debug.bindings.h Line: 35)
02/23/2021 14:58:04: Got session request from <long string of numbers>

The long string of numbers is that person's steam ID. To find it another way, visit a site like:
https://steamdb.info/calculator/

paste the url to the person's steamcommunity.com profile, and copy the SteamID

Then, edit the adminlist.txt in the worlds folder:

lxc exec '${REMOTE_NAME}:${CONTAINER_NAME}' -- runuser -u '${STEAM_USER_NAME}' -- nano '${VALHEIM_WORLD_DIR}/adminlist.txt'

Add the SteamID on a new line, Ctr-S to save, and Ctrl-X to exit the editor.

For more info, see:

https://github.com/lloesche/valheim-server-docker#admin-commands

Note that in recent version of the game, the game client (not the game server) must have '-console' added to the Steam launch options in order to use the in-game console.
"
log "Installation finished"

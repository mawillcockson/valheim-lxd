# Overview

This repository has 3 shell scripts:

- [`install.sh`](./install.sh "script that runs the installation"): performs installation
- [`uninstall.sh`](./uninstall.sh "script that undoes what install.sh does"): undoes most or all of what `install.sh` does
- [`vars.sh`](./vars.sh "utility library"): utility library of functions and variables

It also has files that hold configuration data:

- `valheim.profile.yaml`: an [instance profile][] for [LXD][]
- `valheim.service`: A [service unit file][] for [systemd][] that runs [a Valheim dedicated server][]
- `valheim-update.timer`: a unit file that describes the schedule on which [`valheim-update.service`][] is run (if any)
- `valheim-update.service`: a unit file that stops `valheim.service`, updates the Valhaiem dedicated server, and restarts `valheim.service`

These scripts are meant to be run on a controller, and configure a remote host. Roughly, the steps `install.sh` performs are:

1. Adds the remote host
1. Uploads the profile
1. Has the remote host create an Ubuntu 20.04 container
1. Installs the configuration files in the container
1. Starts the `systemd` unit files

No configuration of the remote computer is performed, outside of what's needed for [LXD][] to run.

Currently, these scripts are written targetting POSIX-compliant shells like `bash`, `zsh`, `ksh`, etc. Both [`dash`][] and [`posh`][] were used during development, but most shells should work.

Installation and use of the scripts are described in [README.md][].

## Design

[`vars.sh`][] exports variables and creates functions that are used by `install.sh`, `uninstall.sh`, and are used in the container.

Most of the variables are able to be overriden by creating an `extra_vars.sh` file in the same directory as `vars.sh`. The overrides are loaded by `vars.sh` last, and most of the variables are defined so that values already exported by the shell that is executing the scripts, will be used first, with defaults in the case that none are defined. They are written with the expectation that the defaults are used, but most names, and some important values, can be used, if needed.

Currently, `valheim.profile.yaml` is edited to set some environment variables. This is the main file to edit, and allows changing the important parts that need to be different between different servers, (e.g. world name, world password, and other values pertinent to Valheim).

The structure in most parts of `install.sh` is to first test to see if that particular configuration step has already been performed first, and only perform it if appears that it hasn't been performed. There aren't currently any checks that, for instance, an existing container with the same name, is a container that's been exclusively configured by this script.

Likewise, `uninstall.sh` will remove and modify the content that has the same name as what it would be named in the `install.sh` script.

The configuration files are very barebones: no care is taken for security. That the Valheim server is run as an unpriviledged user is mostly a coincidence with how `systemd` allows configuration to be performed.

That said, [LXD][] is configured to run the container as an unpriviledged container, and the Valheim server is run by an unpriviledged user in the container, and no filesystems are shared between the host and the container. Neither does any communication happen between them, other than sockets that [LXD][] proxies from the host to the container.

One of the steps is, however, clearing the password of the root user in the container, though, so `su -c "id"` always succeeds. However, this is not required by any part of the installation process, so it can be removed from `install.sh` is so desired. It was included as a convenience, but is not strictly necessary for operating the container.

The scripts do rely on a remote being defined, but that remote can be "`local`", and so these scripts could feasibly be run on the remote computer directly, with an `extra_vars.sh` that contains:

```sh
export REMOTE_IP="defined to prevent asking for it"
export REMOTE_NAME="local"
```

## Implementation

These are not robust scripts:

- No validation is performed to ensure that the configuration that exists in the container actually matches what would have been applied had there not been anything with that name already
- If stopped mid-run, they do not continue where they left off
- They do not check to ensure the environment they are run is meets their requirements, beyond expecting certain command-line tools to be present: `date`, `jq`, `lxc`. If any of these behave irrgularly, they will not be able to respond to that
- They don't account for the subtle differences between different shell implementations, and instead were developed, and assume behaviour similar to, `dash` in Debian 10

The `lxc` command provided by [LXD][] sits at the core of the functionality required by these scripts. Frequently, the `--format json` option is used in conjunction with `jq -e` to reliably parse the state of `lxc`. The [documentation for LXD's API][] was consulted once during development of these scripts.

### [Notes on shell features used in these scripts](./docs/shell_features.ms)

[This document](./docs/shell_features.md) describes how various features of the POSIX shell work, in the way they're used in the scripts.

## Improvements

Myriad improvements and changes that could be made, in no particular order.

The `systemd` unit files, and their installation process, could be written to take advantage of `systemctl --user import-environment`. This would make the scripts a lot easier to read, rather than having overrides generated dynamically during installation.

The port LXD uses could be configurable.

Ensure that `systemd` logs are being retained.

The `VALHEIM_SHOULD_AUTO_UPDATE` environment variable should be checked when the `valheim-update` unit is run, so that updates can be disabled, after the installation happens, without having to rerun the `install.sh`.

[the specification for that behaviour]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html> "IEEE Std 1003.1-2017: The Shell Command Language"
[this version of the specification]: <https://pubs.opengroup.org/onlinepubs/9699919799.2016edition/xrat/V4_xcu_chap02.html>
[condition`trap`]: <https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#trap> "Specification of the trap shell command"
[`install.sh`]: <./install.sh> 

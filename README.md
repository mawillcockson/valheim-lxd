# valheim-lxd

This is a collection of scripts and configuration files for getting a [Valheim dedicated server][valheim] running on a remote computer.

These are designed to run locally on a controller computer that has a minimal set of requirements, and configure a remote host computer that will run the Valheim server.

These can also be run directly on the remote host.

## Requirements

The local computer has only a few restrictions, and any operating system that can run the LXD Client (`lxc`) works. This includes macOS, Windows, and Linux, though Linux will probably have the easiest time getting setup. I used Debian while developing this.

The requirements for the remote computer are slightly stricter: it must run a Linux distribution supported by LXD server. At the time of this writing, that's:

- Alpine Linux
- Arch Linux
- Fedora
- Gentoo
- Ubuntu
- Debian
- OpenSUSE

[The LXD website][install lxd] has an up-to-date list.

The installation instructions are detailed in the [Installing LXD section](#installing-lxd).

These scripts have two dependencies, in addition to the LXD Client, `lxc`:

- [`jq`][]
- a POSIX shell (`bash`, `zsh`, `ksh`, etc. all work, though [`dash`][dash] and [`posh v0.14.1+`][posh] are recommended)

Unfortunately, PowerShell on Windows does not fulfill the second requirement. The [Windows section](#windows) describes how to set up Windows to run the scripts.

Additionally, the `date` and `basename` utilities are needed, but those commands are rarely missing from a POSIX-compliant shell.

On most Linux distributions, and macOS, these tools are usually already installed.

For example, on Ubuntu and Debian, installing these tools looks something like:

```sh
sudo apt update
sudo apt install snapd jq dash coreutils
. /etc/profile.d/apps-bin-path.sh
sudo snap install core
sudo snap install lxd
```

> _Note: Only the `snapd` package is not installed by default on most systems. The others are given for completeness._

### Installing LXD

[LXD][] provides both `lxd`, which is what runs on the remote computer, and `lxc`, which is what these scripts use to interact with `lxd` on the remote computer. `lxc` can run on a local computer, or on the remote computer. Whichever computer will be running the Valheim server will need `lxd` installed.

[The LXD website has installation instructions for all the supported Linux distributions][install lxd]. On Debian and Ubuntu, it looks like this:

```sh
sudo apt install snapd
sudo snap install core
sudo snap install lxd
```

If `snap` has already been installed and setup, the second command will complain, but the third command can be run without issue. If `lxd` is already installed through `snap`, be sure to refresh it to the latest stable channel:

```sh
sudo snap refresh --channel=latest/stable lxd
```

I developed these scripts with `lxd 4.11`, but most of the features used are part of the core functionality, and are unlikely to change.

> _Note: For greater control over selecting exactly which version of LXD you want to install, and control over when it's updated, [check out this forum post from the LXD maintainers][control lxd version]._

Once LXD is installed, log in as the root user, and run `lxd init`.

On some distributions, `lxd` can only be interracted with from a user that's a member of a group named `lxd`, and the installation process may not create this group, or it skips adding the current user to that group. Fortunately, the root user is permitted access. Additionally, any user who is a part of the `lxd` group can use it to gain root privileges on the host system, so it may be preferable to perform the relatively short and one-time step of configuring `lxd` by logging in as the root user, instead of allowing a different user to interact with `lxd` unrestricted.

Logging in is preferrable over using `sudo`, since the place that `snap` intalls packages to may not be in the `PATH` environment variable. On Debian and Ubuntu, installing `snapd` also installs a script that will gracefully add these to the path. This script is available in `/etc/profile.d/apps-bin-path.sh`, and can be run in the current shell environment with `source` or `.` (for example `source /etc/profile.d/apps-bin-path.sh`).

Additionally, `lxd init` sometimes does not run correctly when it is executed outside a login environment, like with normal use of `sudo`.

When initializing with `lxd init`, you can select options different from the defaults if you have specific needs, but the defaults work fine, except for the question `Would you like the LXD server to be available over the network?`: answer `yes`.

These scripts assume a default port of `8443` for managing the remote host. [The Use Custom Port section describes how to use a different port](#use-custom-port).

To select the defaults, hit <kbd>Enter</kbd> without typing anything else.

Below is how I installed and configured `lxd` on a remote host running Debian:

```text
root@remote:~# apt install snapd
user@remote:~# snap install core
user@remote:~# snap install lxd
root@remote:~# . /etc/profile.d/apps-bin-path.sh
root@remote:~# lxd init
Would you like to use LXD clustering? (yes/no) [default=no]:
Do you want to configure a new storage pool? (yes/no) [default=yes]:
Name of the new storage pool [default=default]:
Name of the storage backend to use (btrfs, dir) [default=btrfs]:
Would you like to create a new btrfs subvolume under /var/snap/lxd/common/lxd? (yes/no) [default=yes]:
Would you like to connect to a MAAS server? (yes/no) [default=no]:
Would you like to create a new local network bridge? (yes/no) [default=yes]:
What should the new bridge be called? [default=lxdbr0]:
What IPv4 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]:
What IPv6 address should be used? (CIDR subnet notation, “auto” or “none”) [default=auto]:
Would you like the LXD server to be available over the network? (yes/no) [default=no]: yes
Address to bind LXD to (not including port) [default=all]:
Port to bind LXD to [default=8443]:
Trust password for new clients:
Again:
Would you like stale cached images to be updated automatically? (yes/no) [default=yes] no
Would you like a YAML "lxd init" preseed to be printed? (yes/no) [default=no]: yes
config:
  core.https_address: '[::]:8443'
  core.trust_password: password
  images.auto_update_interval: "0"
networks:
- config:
    ipv4.address: auto
    ipv6.address: auto
  description: ""
  name: lxdbr0
  type: ""
  project: default
storage_pools:
- config:
    source: /var/snap/lxd/common/lxd/storage-pools/default
  description: ""
  name: default
  driver: btrfs
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
cluster: null
```

Once LXD is setup on the remote host, make sure the remote host has the port `lxd` uses for remote administration (default TCP 8443) open. Additionally, you can open the range of three ports Valheim uses. Unless you decide to choose differently, the default port range for Valheim is UDP ports 2456 through 2458, inclusive. The ports must all be consecutive, so if the first port is changed to 60,000, then the other two would be 60,001 and 60,002.

No other inbound ports are required, just those 4 ports. Feel free to disable all other inbound ports, but note that this caused strange issues under some network setups. If once everything is setup, the server either doesn't show up, or cannot be connected to, you may need to look at the network setup. Specifically, the default firewall installed on the remote host may cause some problems.

The storage pool is created by default on the remote host's filesystem, and is managed by LXD. A storage pool with a freshly installed and configured container takes about 2.93 GB, which includes the Valheim server software, though this will grow a bit as the world in the game is explored. The host will need about 2.5 to 3 GB of memory to support about 2 to 4 people. 2 CPU cores seems to be adequate until a lot of the map has been explored.

You may experience some improvement in performance if you [pin CPUs in LXD](#cpu-pinning), but I haven't noticed a difference.

It's probably also a good idea to configure the host's time and date: the scripts by default configure backups of the entire container, and for the Valheim server software to be updated, both at approximately 5:00 AM.

> _Note: The auto-updating and snapshotting can be disabled. The [Disable Automatic Updates section](#disable-automatic-updates) describes how to do this. It's still a good idea to configure the host's time zone to ensure the logs have the right times_

That will happen whenever the remote host thinks it's 5:00 AM. Check the time with the `date` command on the remote host. If that time is not your local time, the server may reboot while you're logged in. No data would be lost, but it would be annoying.

To ensure that the time on the remote host is in sync with reality, most distributions come with an NTP client already configured and running, and running the command `timedatectl timesync-status` on the remote host will probably show this. If that doesn't work, search for something like "`<name of distribution>` sync time".

In addition, it's probably good to make sure that the remote host's 5:00 AM is your 5:00 AM by configuring the time zone. Usually the command below is used:

```sh
timedatectl set-timezone 'TIMEZONE'
```

Where `TIMEZONE` is a name in TZ Database format. To get a list of these names, try `timedatectl list-timezones`. [There's also a nice table on Wikipedia that shows what these names are in other common formats][wikipedia tz], and what their offset is, so that you can find one that tracks not only your current time, but will continue to track it through things like Daylight Saving Time.

### Setting Up Controller

Next, setup the local computer that will run the scripts. If instead you want to run them directly on the remote host, check out the [Running Locally section](#running-locally), then return here.

On most Linux distributions, [installing `lxd`][install lxd] will also install `lxc`. Additionally, ensure [`jq`][], `date`, and `basename` are all available. Each of the following commands should print out something that looks like what's in the comment below them:

```sh
lxc version
# Client version: 4.11
# Server version: unreachable

/bin/sh -c 'echo works'
# works

jq --version
# jq-1.5-1-a5b5cbe

basename /bin/test
# test

date "+%s"
# 1615302000
```

The LXD Server does not need to be running on the local computer in order to run these scripts, unless they're being run directly on the remote host.

If an error is printed about a missing command, that utility needs to be installed:

- `lxc` is the LXD Client ([installation instructions][install lxd])
- `sh` can be any of `zsh`, `bash`, `ksh`, `ash`, though `dash` and `posh v0.14.1` or higher are recommended
- `jq`: [installation instructions][download jq]
- `basename` and `date` are bundled into GNU CoreUtils (most Linux distribution package repositories include it, but it is named slightly differently between Linux distributions)

If all of those are working, then you're ready to go to the [Use section](#use).

If the controller is running Windows, the following section describes how to run these scripts from Windows.

#### Windows

With [`lxc`][win lxc] and [`jq`][] having downloads for Windows, probably the easiest way to get a shell interpreter and GNU CoreUtils is with the [Git for Windows][] distribution. This has the advantage of including `git`, which makes it very easy to download the scripts and files, by downloading this repository.

Alteratively, [Cygwin][] provides a lot of the same tools.

Lastly, [Windows Subsystem for Linux][wsl] allows running a distribution of Linux on Windows, without having to start a virtual machine manager like VirtualBox of VMWare. If you're going this route, I'd recommend installing [Ubuntu][ms store ubuntu 20.04] through WSL. [Microsoft maintains instructions for this][install wsl]. Once [Ubuntu][ms store ubuntu 20.04] is installed and running, refer to the instructions above and continue as if you're using Linux. If you use WSL, there's no need to install any extra tools like `lxc` or `jq` on Windows directly. These should instead be installed inside the WSL environment.

The following instuctions are for using [Git for Windows][].

As long as [`lxc`][win lxc], [`jq`][download jq], and a POSIX shell are available, the scripts should run fine.

> _Note: I have not tested them on Windows_

After installing [Git for Windows][], Git Bash should either be available as a desktop icon, or in the Start Menu. Run it, and in the console window that pops up, type the following to download this repository.

```sh
git clone --single-branch --depth 1 https://github.com/mawillcockson/valheim-lxd.git ~/valheim-lxd
```

Then, change directories into the directory that was just created, and make sure the tools that the scripts rely on are available inside Git Bash:

```sh
cd ~/valheim-lxd

lxc version
# Client version: 4.11
# Server version: unreachable

/bin/sh -c 'echo works'
# works

jq --version
# jq-1.5-1-a5b5cbe

basename test
# test

date "+%s"
# 1615302000
```

From there, continue with [Use](#Use).

## Use

First, download this repository. This can be done by [downloading a `.zip` file of this repository's current files][repo zip], or can be done with `git`, if that's installed:

```sh
git clone --single-branch --depth 1 https://github.com/mawillcockson/valheim-lxd.git ~/valheim-lxd
```

The above command would put the repository files in a folder `valheim-lxd` in the home directory.

These scripts try to set up each server identically, however some things should be different. The most important ones are the name of the Valheim server (as it appears in-game), and the password. A few other settings should be configured, too.

To provide these, create a file called `environment.yaml` in the same directory as the [`install.sh`][install.sh] script is in. It should be filled out like so:

```yaml
config:
  # Set this to what the remote host was set to in Installing LXD
  # Asia/Jakarta is provided as an example
  environment.TIMEZONE: "Asia/Jakarta"

  # This is the name that will show up in the server browser in-game
  environment.VALHEIM_WORLD_NAME: "A Valheim Server"

  # This is the filename of the world, and cannot contain spaces
  environment.VALHEIM_WORLD_FILE_NAME: "singleword"

  # This is the password that has to be entered when you connect to the server,
  # public or private.
  # Must be at least 5 characters long, or Valheim won't start.
  # The container will still run, but there won't be a Valheim server running.
  environment.VALHEIM_PASSWORD: "oops"

  # If set to "no" the server will not show up in the public server list, and
  # must be added by IP through the Steam interface
  environment.VALHEIM_SERVER_IS_PUBLIC: "yes"
```

The lines starting with `#` are comments, and don't have to be copied. Feel free to add your own notes as comments.

Additionally, most of the values that are used by the scripts, like names, are listed in [`vars.sh`][vars.sh], and can be overridden by creating an `extra_vars.sh` file in the same directory, but the defaults should work fine.

When the Valheim server is started for the first time, it will create a world, matching the parameters in `environment.yaml`, and will use a random seed.

If you want to use a particular seed, you need to be able to play Valheim. Start the game, and create a new world with the same parameters as in `environment.yaml` (the passwords don't need to match), and use the desired seed. Then stop the game, and copy the `.fwl` and `.db` files that were made when the world was created into the same directory as the `environment.yaml` file is in.

Once the required dependencies are installed, and the `environment.yaml` file is in place, run `install.sh`:

```sh
sh ./install.sh
```

A description of the steps performed by `install.sh`:

1. Sets up a connection to the remote computer (provide the password entered from when `lxd init` was run)
1. Downloads an official Ubuntu container image
1. Creates a new container based on that image
1. Updates the packages and installs minimal dependencies
1. Creates an account to run the Valheim server under (default `steam`)
1. Enables `systemd` user service managers
1. Clears the passwords of the `root` and `steam` users (only in the container)
1. Uploads necessary files, including any existing worlds
1. Sets the timezone
1. Installs Valheim (the script may appear to hang during this step, but it is installing Steam and downloading a 1 GB file)
1. Starts the Valheim server (and automatic updates, if those were not disabled)
1. Takes a snapshot (default name `right-after-installation`)

How long this takes largely depends on the internet connection to the remote host. Valheim is about 1 GB itself, so depending on the internet available to the remote host, it can take anywhere from 5 minutes to hours. The script has lots of messages, and hopefully these make it clear what steps are being performed. The one big downside is that, currently, the process for downloading and installing Valheim waits until after it's been downloaded to report any progress, so it may appear to pause for a while.

Once the script completes, check out the [Playing section](#playing) for instructions on how to find the server in the in-game server browser.

### Running Locally

These scripts can be run directly on the remote host. In this scenario, the remote host would double as the controller.

LXD has the concept of "remotes" which are LXD servers that can be connected to with the [LXD Client][], `lxc`.

Fortunately, when LXD is installed on the remote host as in the [Install LXD section](#install-lxd), the LXD server on the remote host is added as a remote named `local`, in the LXD Client configuration that is on the remote host.

When running the scripts on the remote host, use the name `local` as the name of the remote computer. This will cause the scripts to connect to the LXD server running on the remote host.

To use `local` as the remote computer's name in all the scripts, create a file called `extra_vars.sh` in the same directory as the [`vars.sh`][vars.sh] file, and add the following line to it:

```sh
export REMOTE_NAME="local"
```

Anywhere this guide talks about a remote computer, use the name `local` instead.

Once this is done, continue with the [Setting Up Controller section](#setting-up-controller).

### Configure Auto-Update Time

By default, the Valheim server will be stopped, updated, and restarted at 5:00 AM, by the clock of the remote host. Shortly before this, the remote container will have a snapshot taken of the entire container.

To make sure this happens at 5:00 AM your time, check out [Installing LXD](#installing-lxd).

I'm hoping this time works for most people. If it doesn't, the following describes how to change it.

Updating Valheim, and taking a snapshot of the container, are two separate events that run on separate schedules. I've found it best to time the snapshot to happen 5 minutes before Valheim is updated or restarted. This way, the snapshot will contain a known-working version of the Valheim server software.

The snapshot takes seconds to perform, whereas the update could take a long time if a completely new version of the dedicated Valheim server software needs to be downloaded.

The format for specifying when each event happens is different.

For the snapshot, [the format that LXD uses is similar to the format of `cron`][lxd snapshots], though without shortcuts like `@daily`. Websites like [cron.help](https://cron.help/#1_5_*_*_1) can help find the right way to express a particular time.

The schedule for the Valheim game server update check is a [`systemd` `OnCalendar` directive][]. [This document describes the format][oncalendar format]. Briefly, the 4-digit year, 2-digit month, and 2-digit day of the event are given, separated by hyphens, in that order. For our purposes, `*` is useful, as it means "any", so `*-*-*` means "any year, any month, any day". Then, after a leading space, follows the time at which this will happen, in a 24-hour format. The time includes a 2-digit hour, 2-digit minute, and 2-digit second, all separated by colons.

As an example, the default schedule is `*-*-* 05:10:00`, which is equivalent to "every day at 5:10 AM".

It's important to ensure that the schedule for each event causes them to occur with the same frequency. For example, it probably isn't very useful to have the snapshots happen daily, while the check for updates happens every hour (besides, checking for updates causes the Valheim game server to stop, and it takes a while to restart, and the game wouldn't be very playable if you're being kicked out every hour).

However, there's no requirement for this. The daily check for updates is useful if you have auto updates enabled for the game in Steam. With both enabled, the Valheim server version is likely to always be compatible with the client version.

> _Note: either can be selectively disabled. The [Disable Automatic Updates section](#disable-automatic-updates) has info on how to disable each one._

As an example, let's say I wanted to have both the game server update and the container snapshot to happen at 4:30 PM every day.

I would want the update to happen right at 4:30, so I would make the snapshot happen right before that. 5 minutes provides an ample buffer, so 4:25.

For the Valheim game server update check, I would use `*-*-* 04:30:00`, and for the snapshots I would use `25 4 * * *`.

To change the schedule for updating Valheim, create a file called `extra_vars.sh` in the same folder that [`vars.sh`][vars.sh] is in, and add a line like the following:

```sh
export VALHEIM_AUTO_UPDATE_SCHEDULE="*-*-* 04:30:00"
```

For the snapshot schedule, add 1 line in `environment.yaml`:

```yaml
config:
  snapshots.schedule: "25 4 * * *"
```

#### Disable Autotomatic Updates

The automatic updating of Valheim can be disabled, as can the snapshotting, but I recommend keeping both, unless you would like to implement a backup solution for the Valheim world files (note that `lxc file pull` can be used on the backup computer to retrieve the `.fwl` and `.db` game server files remotely; the container should be stopped during a file pull).

To disable the auto-updating, add a line to the `environment.yaml` file:

```yaml
config:
  environment.VALHEIM_SHOULD_AUTO_UPDATE: no
```

This will only take effect when done before running [`install.sh`][install.sh], so make sure this file is in place before running the installation. To disable the automatic updates on a remote host that's already been configured, run the following command:

```sh
lxc '<login-alias>' '<remote>:<container>' --env 'USER=<user>'
```

With the defaults, this would be:

```sh
lxc login 'valheim:valheim' --env 'USER=steam'
```

If [running locally](#running-locally), `<remote>` is `local`.

At the resulting command prompt, run the following command:

```sh
systemctl --user disable --now valheim-update.timer
```

Log out by running the command `exit`.

To disable the automatic snapshotting, add 1 line to the `environment.yaml` file:

```yaml
config:
  snapshots.schedule: "0 0 31 2 0"
```

This will [set the snapshot to happen on February 31st](https://cron.help/#0_0_31_2_0), a time which will (hopefully) never come to pass.

This will also only take effect when done before running [`install.sh`][install.sh].

To apply this setting after, run the following command:

```sh
lxc profile set '<remote>:<profile>' snapshots.schedule "0 0 31 2 0"
```

With the defaults this would be:

```sh
lxc profile set 'valheim:valheim-environment' snapshots.schedule "0 0 31 2 0"
```

If [running locally](#running-locally), `<remote>` is `local`.

> _Note: The [`install.sh`][install.sh] script will still always take a snapshot at the end of the installation._

#### Manual updating and snapshotting

Valheim can be updated at any time, as can a snapshotting the container. Doing either of these things will not affect any of the scheduled events: the automated snapshots and updates will still happen as configured.

The following commands refer to the remote host and the container in the format `<remote host>:<container>`, without the `<` and `>`. By default, the name `valheim` is used for both. If the scripts were run directly on the remote host by following the directions in the [Running Locally section](#running-locally), then replace `<remote host>` with `local`.

Updating the Valheim server (will stop, update, and restart the server):

```sh
lxc exec 'valheim:valheim' -- update_valheim.sh
```

Taking a snapshot of the container:

```sh
lxc snapshot 'valheim:valheim'
```

This will create a new snapshot with the name `snap#`, where `#` is a number, starting from 0.

The following command displays a list of snapshots, as well as information about the container:

```sh
lxc info 'valheim:valheim'
```

#### CPU Pinning

You can enable CPU pinning for the container, though I haven't observed a noticeable difference for Valheim.

In the `environment.yaml` file, add 1 line for `limits.cpu`, with a value that is the range of CPU cores that should be mapped one-to-one into the container. I usually leave one CPU core for the host, and give all the rest to the container, since the Valheim container is the only thing I run on that host.

"CPU" here is the Linux kernel's concept of a CPU. To find out how many are available, on the host computer, run `lscpu --extended=CPU`. On Ubuntu and Debian, this command is available in the `util-linux` package. On my host, this looks like:

```text
root@remote:~# lscpu --extended=CPU
CPU
0
1
2
3
4
5
6
7
```

Generally, this is the number of cores the CPU has (multiplied by 2 if it has [Simultaneous Multithreading][]).

So in my `environment.yaml` file I have:

```yaml
config:
  limits.cpu: 1-7
```

The format for this configuration line is described in [the LXD documentation][lxd cpu limits].

Again, this is probably not going to result in much of a gain in performance, especially for a small number of players.

### Use Custom Port

If the remote computer that's running `lxd` has `lxd` set to listen on a port other than `8443`, and the scripts will be run on a different computer, `lxc` on that different computer has to be configured manually. Create an `extra_vars.sh` file in the same directory as [`vars.sh`][vars.sh] and set the `REMOTE_NAME` and `REMOTE_IP` variables:

```sh
# content of extra_vars.sh
export REMOTE_NAME="valheim"
export REMOTE_IP="192.0.2.2"
```

Where `192.0.2.2` is the IPv4 address of the computer that `lxd` is running on. Then, source this file in the current console, and add the remote, specifying the custom port (`50998` in the example below):

```sh
. ./extra_vars.sh
lxc remote add "${REMOTE_NAME}" "https://${REMOTE_IP}:50998"
```

When run, [`install.sh`][install.sh] will use the already defined remote, as long as the name isn't changed.

## Playing

Once the server is up and running, it should show up in the in-game server browser.

If it doesn't this is likely because the remote host is not directly accessible from the internet.

By default, Valheim uses ports 2456, 2457, and 2458. The [`install.sh`][install.sh] script configures remote host to forward these to the container, but the data needs to be able to reach the remote host in the first place.

In my experience, sometimes the Valheim server will show up in the in-game browser, but I am unable to connect. This seemed to be caused by the default firewall configuration on the remote host. I settled with disabling the firewall, though I don't recommend such a heavy-handed approach for everyone.

[ms store ubuntu 20.04]: <https://www.microsoft.com/store/apps/9n6svws3rx71> "Ubuntu in the Microsoft Store"
[wsl]: <https://aka.ms/wsl> "Main website for the Windows Subsystem for Linux"
[install wsl]: <https://aka.ms/wslinstall> "Microsoft's documentation on installing WSL"
[win lxc]: <https://linuxcontainers.org/lxd/getting-started-cli/#windows-builds> "LXD client for Windows"
[download jq]: <https://stedolan.github.io/jq/download/> "Download page for jq"
[repo zip]: <https://github.com/mawillcockson/valheim-lxd/archive/main.zip> "A zip file of this repository, generated by GitHub"
[install lxd]: <https://linuxcontainers.org/lxd/getting-started-cli/#installation> "Installation instructions for LXD"
[Simultaneous Multithreading]: <https://en.wikipedia.org/wiki/Simultaneous_multithreading> "Wikipedia article on SMT"
[control lxd version]: <https://discuss.linuxcontainers.org/t/managing-the-lxd-snap/8178> "LXD Forum post on controlling the lxd version"
[wikipedia tz]: <https://en.wikipedia.org/wiki/List_of_tz_database_time_zones> "Wikipedia article on Time Zone names"
[valheim]: <https://www.valheimgame.com/> "Main game website"
[lxd client]: <https://linuxcontainers.org/lxd/getting-started-cli/#lxd-client> "Documentation on using lxc, the LXD Client"
[`jq`]: <https://stedolan.github.io/jq/> "Main jq website"
[LXD]: <https://linuxcontainers.org/lxd/#what-is-lxd> "about the Linux Container Daemon"
[cygwin]: <https://cygwin.com> "Main cygwin website"
[Git for Windows]: <https://git-scm.com/download/win> "Download Git for Windows"
[lxd snapshots]: <https://linuxcontainers.org/lxd/docs/master/instances#snapshot-scheduling> "LXD documentation on scheduling snapshots"
[`systemd` `OnCalendar` directive]: <https://www.freedesktop.org/software/systemd/man/systemd.timer.html#OnCalendar=> "systemd's documentation for OnCalendar"
[oncalendar format]: <https://www.freedesktop.org/software/systemd/man/systemd.time.html#Calendar%20Events> "Description of the format used to describe Calendar events in systemd"
[lxd cpu limits]: <https://linuxcontainers.org/lxd/docs/master/instances#cpu-limits> "Documentation on limiting the CPU resource for containers managed through LXD"
[install.sh]: <./install.sh> "script that runs the installation"
[uninstall.sh]: <./uninstall.sh> "script that undoes what install.sh does"
[vars.sh]: <./vars.sh> "utility library"
[dash]: <https://tracker.debian.org/pkg/dash> "Debian Almquist Shell"
[posh]: <https://tracker.debian.org/pkg/posh> "Policy-compliant, Ordinary SHell, a stripped-down version of pdksh that aims for compliance with Debian's policy, and a few extra features"

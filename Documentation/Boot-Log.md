# Reading the boot log

Every line below was seen on the way to a clean 4.14 boot, except the two that say so.
Find the line, apply the fix, boot again. Patch numbers are those of the 4.14 series. The 4.19 series has no patch 2, so from
patch 3 on subtract one. The 4.9 series folds patches 4 and 5 into its patch 4, so from
patch 6 on subtract one.

**`Failed to spawn executor: Function not implemented` on every unit.** The kernel lacks
`waitid(P_PIDFD)`. Patch 1. If the probe also says `pidfd_open no`, the kernel lacks the
whole pidfd series and needs [`pidfd-backport-4.9/`](../pidfd-backport-4.9/README.md) or
[`pidfd-backport-4.14/`](../pidfd-backport-4.14/README.md) first.

**PID 1 fails before any unit starts, `strace` shows `statx` returning ENOSYS.** A 4.9
kernel without statx. Patch 4 of the 4.9 series. Not seen in a log yet, the 4.9 series has
not been booted; this is what the source says will happen.

**`Detected cgroup v1 hierarchy ... refusing execution`.** The guest sees a cgroup v1 mount
under `/sys/fs/cgroup`. The runtime has to mount cgroup2 there; Droidspaces does.
`--force-cgroupv1` cannot help systemd 258 or newer.

**`Failed to set up credentials: Function not implemented`, exit status 243/CREDENTIALS,
on journald and most other services.** systemd 259 and newer use the kernel 5.2 mount API
for service credentials. Nothing to patch in the kernel: use Droidspaces newer than 7.1.0,
which carries the fix. The [internals page](Internals.md#the-new-mount-api) explains why.

**`Failed to set up mount namespacing: /proc: Invalid argument`, exit status 226/NAMESPACE,
on userdbd.** Same cause and same fix as the credentials line.

**`dev-mqueue.mount: Mount process exited, code=exited, status=32`.** The environment
variable `LIBMOUNT_FORCE_MOUNT2=always` did not reach the mount process. Droidspaces passes
it on the init command line; another runtime has to do the same.

**networkd restarts five times and eth0 has only an IPv6 address.** Look for `Could not set
up manager: Invalid argument` in its log. The kernel lacks the nexthop netlink group.
Patch 10.

**`ld.lld: error: undefined symbol: __compiletime_assert_NNN` referenced by nlmsgtab.c.**
A kernel build error, not a boot error. `RTM_MAX` was raised without the matching SELinux
rows. Patch 10 carries them; if you ported the change by hand, add the rows.

**`Failed to determine whether /proc is a mount point` and PID 1 exits.** systemd 260 or
newer on a kernel without the statx mount id. Patches 4 and 5. On 4.9 the series' own
statx patch carries both.

**`run0`, `systemd-run -t` or `machinectl shell` cannot open a terminal.** The kernel lacks
`TIOCGPTPEER`. 4.14 and 4.19 have it; on 4.9 it is patch 14 of the series. Also not seen
in a log yet, for the same reason.

**`Failed to close all file descriptors: Function not implemented`.** systemd 260 or newer
on a kernel without `close_range`. Patches 8 and 9.

**`Failed to connect stdout to the journal socket` everywhere.** journald itself failed.
Find its own line and fix that first.

**The resolved start job hangs for 90 seconds.** userdbd is down and user lookups time out.
Fix userdbd's failure first.

**`Failed to enable/disable controllers on cgroup ..., ignoring`, once per unit.** The host
keeps the cpu, memory or pids controller on cgroup v1, so the guest cannot have it. Harmless.
Resource limits for that controller do nothing inside the guest.

**`bpf-firewall: ... Operation not permitted`, `Failed to read pids.max ... No data
available`, `Unable to determine whether tmpfs supports 'usrquota'`.** Noise. systemd
continues.

**`Tainted: old-kernel` in `systemctl status`.** Expected. The kernel is below systemd's
baseline and systemd says so. Nothing else should be listed after it.

## When the console does not say why

Run `systemctl status <unit>` inside the container, then `journalctl -u <unit> -b
--no-pager`. If journald itself is down, the console is all you have, and
`systemd.log_level=debug` on the init command line makes it talk.

A clean boot looks like this: `systemctl --failed` lists zero units, `systemctl status`
says `running` with `Tainted: old-kernel` and nothing else, and eth0 has an IPv4 address
from networkd.

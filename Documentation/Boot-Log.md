# Reading the boot log

Each line below was seen on the way to a clean boot. Match the line, apply the fix, boot
again. Patch numbers are those of the 4.14 series; the 4.19 series has the same changes one
number lower from patch 3 on, because it has no parent_tidptr patch.

| Log line | Missing piece | Fix |
|---|---|---|
| `Failed to spawn executor: Function not implemented` on every unit | waitid P_PIDFD | patch 1 |
| `Failed to spawn executor: Function not implemented` on every unit, and the probe says `pidfd_open no` | the whole pidfd series | [`pidfd-backport-4.14/`](../pidfd-backport-4.14/README.md), then the series |
| `Detected cgroup v1 hierarchy ... refusing execution` | guest sees a v1 mount under /sys/fs/cgroup | runtime must mount cgroup2 there; `--force-cgroupv1` cannot help systemd 258+ |
| `Failed to set up credentials: Function not implemented`, status 243/CREDENTIALS | new mount API | Droidspaces newer than 7.1.0, which carries the [seccomp shim](Requirements.md#what-droidspaces-does) |
| `Failed to set up mount namespacing: /proc: Invalid argument`, status 226/NAMESPACE | textual hidepid= (5.8) behind the mount API fallback | same shim; it makes systemd keep the existing /proc |
| `dev-mqueue.mount: Mount process exited, code=exited, status=32` | libmount got EPERM from the shim and treats only ENOSYS as a reason to fall back to `mount(2)` | `LIBMOUNT_FORCE_MOUNT2=always` must reach the mount process; Droidspaces passes it on the init command line |
| networkd restarts five times, eth0 has only an IPv6 address, `Could not set up manager: Invalid argument` | RTNLGRP_NEXTHOP join | patch 10 |
| `ld.lld: error: undefined symbol: __compiletime_assert_NNN` referenced by nlmsgtab.c | RTM_MAX raised without SELinux rows | patch 10's nlmsgtab part |
| `Failed to determine whether /proc is a mount point`, PID 1 exits (260+) | STATX_MNT_ID, STATX_ATTR_MOUNT_ROOT | patches 4, 5 |
| `Failed to close all file descriptors: Function not implemented` (260+) | close_range | patches 8, 9 |
| `Failed to connect stdout to the journal socket` everywhere | journald itself failed, look at its own line | |
| resolved start job hangs 90 s | userdbd down, user lookup times out | fix userdbd's failure first |
| `bpf-firewall: ... Operation not permitted`, `Failed to read pids.max ... No data available`, `Unable to determine whether tmpfs supports 'usrquota'` | nothing | noise, systemd continues |
| `Failed to enable/disable controllers on cgroup ..., ignoring` once per unit | cgroup2 cpu, memory or pids controller held by the host on v1 | nothing, limits for that controller do nothing inside the guest |
| `Tainted: old-kernel` in `systemctl status` | the kernel is below systemd's baseline | nothing, expected |

When a service fails and the console does not say why: `systemctl status <unit>` inside the
container, then `journalctl -u <unit> -b --no-pager`. If journald itself is down, the console
is all you have, and `systemd.log_level=debug` on the init command line makes it talk.

A clean boot looks like this: `systemctl --failed` lists zero units, `systemctl status`
says `running` with `Tainted: old-kernel` and nothing else, and `ip addr` shows an IPv4
lease on eth0 from networkd.

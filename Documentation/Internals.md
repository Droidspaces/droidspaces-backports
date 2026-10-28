# Why systemd needs these patches

Reference material. None of it is needed to apply the patches. It records what was read out
of the systemd source at tags v257.9, v258, v259 and v260 so that the choices in this
repository can be checked, and it names the systemd commit that removed each fallback so
you can diff it yourself. Kernel versions are the mainline release that introduced a
feature. Mainline kernel hashes are in the series READMEs.

## How the baseline moved

systemd publishes a kernel baseline and removes fallbacks for anything older. The baseline
is not a check at startup, it is a promise about which fallbacks still exist in the code.

- **257**, released 2024-12, minimum kernel 3.15. Still boots on 4.x. The fallbacks for
  pre-pidfd kernels and cgroup v1 are present.
- **258**, released 2025-09-17, minimum kernel 5.4. Removed the pidfd fallbacks, cgroup v1,
  the `SO_BINDTODEVICE` fallback, the nexthop fallback in networkd, the `TIOCGPTPEER` and
  ambient capability fallbacks, and the statx fallback.
- **259**, released 2025-12-17, minimum kernel 5.4. Service credentials are now built with
  the kernel 5.2 mount API.
- **260**, released 2026-03-17, minimum kernel 5.10. Removed the fallbacks for
  `close_range`, `STATX_MNT_ID`, `STATX_ATTR_MOUNT_ROOT`, `AT_EMPTY_PATH` on utimensat and
  faccessat, `memory_recursiveprot` and `MS_NOSYMFOLLOW`.
- **261 and 262**, minimum kernel 5.10. No new kernel requirement. 262 passes a textual
  `hidepid=` unconditionally for `ProtectProc=`.

A **hard** gap stops PID 1 or every service. A **soft** gap costs one feature and a log
line. Most of systemd's README list is soft. The notes below are written for 4.14; 4.19
differs only in already having the cgroup v2 cpu controller and the cgroup freezer.

## What 4.14 already has

systemd 260 still lists these and 4.14 ships them: timerfd `CLOCK_BOOTTIME` (3.15),
`memfd_create` and `getrandom` (3.17), ambient capabilities (4.3), the pids controller in
cgroup v2 (4.5), cgroup namespaces (4.6), statx (4.11, without the mount id field that
comes later), the nsfs `NS_GET_NSTYPE` ioctl (4.11), `TIOCGPTPEER` (4.13), the cgroup2
`nsdelegate` mount option (4.13) and cgroup2 threaded mode (4.14). 4.9 lacks statx, the
nsfs ioctl, `TIOCGPTPEER`, `SO_PEERGROUPS` and `nsdelegate`; the
[4.9 series](../kernel-4.9-series/README.md) adds all but the last.

## Hard requirements for systemd 258 and 259

Without these, PID 1 either refuses to start or cannot start a single service.

**A cgroup2 filesystem at `/sys/fs/cgroup` with no v1 hierarchy under it** (kernel 4.5).
PID 1 calls `cg_has_legacy()` before anything else and aborts with "Detected cgroup v1
hierarchy at /sys/fs/cgroup/, which is no longer supported ... refusing execution" if the
path is a tmpfs holding v1 mounts. `systemd.unified_cgroup_hierarchy=0` and
`--force-cgroupv1` no longer help. Fallback removed in c35a58576 "cgroup-setup: drop cgroup
v1 support", 8a05dbb31 and 4ee64e436. Controllers are not required: whatever is missing from
`cgroup.controllers` is simply not enabled, with one "Failed to enable/disable controllers
on cgroup ..., ignoring" warning per unit. Droidspaces mounts a fresh cgroup2 for the guest,
so this is only work for a native boot.

**`pidfd_send_signal`** (kernel 5.1, syscall 424). `pidref_kill()` uses it whenever a pidfd
is held, which is always once `pidfd_open` is in use, and sd-event child sources signal
through it. Fallback removed in 6e14c46ba "tree-wide: drop support for kernels without
pidfd_open() and pidfd_send_signal()". Without it, ENOSYS on every kill of a service.

**`pidfd_open` and pollable pidfds** (kernel 5.3, syscall 434). `pidref_set_pid()` returns
the error instead of falling back to a bare PID, and every spawn goes through it.
`sd_event_add_child()` returns the error too, so every systemd daemon that watches children
fails, not only PID 1. Fallback removed in 6e14c46ba and 0df46f890. Without it, "Failed to
spawn executor: Function not implemented" for every unit, and journald, udevd and logind
cannot watch children.

**`CLONE_PIDFD`** (kernel 5.2). glibc 2.39 and newer implement `pidfd_spawn()` with it, and
systemd built against such a glibc uses `pidfd_spawn()` for every service. glibc gates the
whole thing on one probe: `waitid(P_PIDFD, INT_MAX, ...)` must return EBADF rather than
EINVAL (`__clone_pidfd_supported()` in `sysdeps/unix/sysv/linux/clone-pidfd-support.c`),
otherwise `pidfd_spawn()` returns ENOSYS. It tries clone3 first and on ENOSYS falls back to
legacy `clone()` with `CLONE_PIDFD`, taking the fd back through the parent_tid slot. So
clone3 is not needed, but `CLONE_PIDFD` and `waitid(P_PIDFD)` are. v257.9 fell back to
plain `posix_spawn()` here; v258 returns the error, since the `clone_support` state machine
in `posix_spawn_wrapper` was removed in 6e14c46ba. Arch, Fedora and openSUSE Tumbleweed all
ship glibc 2.39 or newer.

**`waitid(P_PIDFD)`** (kernel 5.4, idtype 3). `pidref_wait()` and sd-event reap children by
pidfd, and glibc's probe above depends on its exact behaviour. Fallback removed in
0df46f890 "pidref: drop support for kernels lacking waitid(P_PIDFD, …)". Without it,
EINVAL when reaping, so services that exit are never reaped and PID 1 hangs on them. This is
the one piece of the pidfd series that no Android 4.14 or 4.19 kernel has, and it is patch 1
of both series.

**pidfd fdinfo** (kernel 5.3). `pidfd_get_pid()` reads the `Pid:` line of
`/proc/self/fdinfo/<fd>` to map a received pidfd back to a PID, for sd_notify and logind
sessions. Not fatal for boot. Comes with the pidfd backport.

The pidfd pieces are one kernel series in `kernel/pid.c`, `kernel/fork.c`,
`kernel/signal.c`, `kernel/exit.c`, `fs/proc/base.c` and the arch syscall tables. Google's
Android R backport carries all of it except `P_PIDFD`.

## Soft requirements for systemd 258 and 259

These produce warnings or disable a feature. None stops boot, but two of them break
networking inside a container, which looks like a failed boot.

**`SO_BINDTOIFINDEX`** (kernel 5.1). `socket_bind_to_ifindex()` in resolved, the networkd
DHCP client, ICMPv6 and local-addresses. Fallback removed in ddbbc98bd "drop
SO_BINDTODEVICE fallback". Without it resolved cannot bind per-interface sockets and the
DHCP client cannot bind, so DNS and DHCP inside the guest break. Patched in both series.

**Nexthop netlink types and multicast group** (kernel 5.3). See
[the nexthop section](#why-networkd-dies-on-a-kernel-with-31-multicast-groups). Patched in
both series.

**The new mount API** (kernel 5.2). On 258 the `mount_option_supported()` probes return an
error, callers treat it as "option not supported" and continue; fallback removed in
c2198d0c3 "assume fsopen() works in mount_option_supported()". From 259 it is fatal for
every service with credentials. See [the mount API section](#the-new-mount-api).

The rest only cost a feature. The cgroup freezer (5.2, fallback removed in 3c86a935a)
breaks `systemctl freeze`. The cgroup v2 cpu controller and per-cgroup `cpu.stat` (4.15,
29da53dde) mean CPU accounting reads zero and `CPUWeight=` does nothing; the same goes for
memory, pids and io whenever the host holds them on v1. The cgroup-bpf device hook (4.15)
and socket address hooks (4.17) turn `DeviceAllow=`, `SocketBindAllow=` and
`RestrictNetworkInterfaces=` silently off. Bounded BPF loops (5.3) are needed by the bpf
firewall, which otherwise fails the verifier and switches off. PSI (4.20) is needed by
systemd-oomd, which is not started in a container. `FRA_PROTOCOL` (4.17) degrades
networkd's rule bookkeeping. `/sys/power/resume_offset` (4.17) is hibernation only.
`CLONE_INTO_CGROUP` (5.7) keeps its fallback and only makes spawning slower. Keyring
namespacing (5.3) and signed dm-verity images (5.4) are listed in systemd's README and do
nothing on a container kernel.

## What systemd 260 adds

On top of everything above. A stock 5.4 kernel is missing exactly these.

**`close_range`** (kernel 5.9, syscall 436). `close_all_fds()` runs in the child of every
`safe_fork()` with `FORK_CLOSE_ALL_FDS`, which is nearly every fork in systemd, and the
child exits if it fails. systemd passes flags 0, so `CLOSE_RANGE_UNSHARE` and
`CLOSE_RANGE_CLOEXEC` are not needed. Fallback removed in c471cca09 "fd-util: close_range()
is available since kernel 5.9". Without it every forked helper dies with "Failed to close
all file descriptors: Function not implemented".

**`STATX_MNT_ID` and `STATX_ATTR_MOUNT_ROOT`** (kernel 5.8; systemd's README dates reliable
support to 5.10). `path_get_mnt_id_at()` and `fd_is_mount_point()` return `EUNATCH` when
the mask or the attribute is not honoured. `mount_setup()` calls `path_is_mount_point_full()`
for every API filesystem, and the entries for `/proc`, `/sys`, `/dev`, `/run` and cgroup2
are fatal. Fallback removed in 7ecfa87c5 "STATX_MNT_ID is supported since kernel 5.10" and
a98a6eb95. Without them PID 1 dies in mount setup with "Failed to determine whether /proc
is a mount point".

**`faccessat2` and `AT_EMPTY_PATH` on utimensat** (kernel 5.8, syscall 439). `access_fd()`
runs on every `chase()` with access checks, and glibc routes any `faccessat()` call with
flags through faccessat2 and answers EINVAL when the kernel lacks it. `futimens_opath()`
lost its `/proc/self/fd` fallback. Fallback removed in 52bf232e8 "drop fallback for kernels
without AT_EMPTY_PATH support (< 5.8)". Without them tmpfiles, journal, udev, the tar
importer and credential handling fail with EINVAL.

**`memory_recursiveprot`** (kernel 5.7). PID 1 mounts cgroup2 with
`nsdelegate,memory_recursiveprot` unconditionally and the entry is fatal, but it is skipped
when something already mounted cgroup2. Fallback removed in 80c5b63db. Not patched here,
because Droidspaces mounts cgroup2 before systemd gets to it. A native boot would need it.

The remaining 260 items are soft and not patched. `GRND_INSECURE` (5.6) falls back to
`/dev/urandom` and Android 4.14 and 4.19 trees have it anyway. `MS_NOSYMFOLLOW` (5.10) costs
a warning per credentials mount and breaks nspawn and `RootImage=`. Per-instance procfs
options (5.8) are probed and treated as unsupported, except that 262 passes
`hidepid=invisible` unconditionally, see the mount API section. `LOOP_CONFIGURE` (5.8)
breaks repart, dissect and `RootImage=`. `epoll_pwait2` (5.11), `cgroup.kill` (5.14),
`mount_setattr` (5.12) and `quotactl_fd` (5.14) all keep their fallbacks.

## The new mount API

Kernels below 5.2 have no `fsopen()`, `fsconfig()`, `fsmount()`, `move_mount()`,
`open_tree()` or `fspick()`. With every patch above applied, systemd 259 and 262 both boot
on 4.14, reach their default target and spawn services, and two failures remain.

From systemd 259, `exec-credential.c` builds every service's credentials directory with
the new mount API. It falls back to a plain directory only on EPERM or EACCES, never on
ENOSYS, so on an old kernel journald, sysctl, tmpfiles, sysusers, udev, resolved, networkd
and getty all fail with "Failed to set up credentials: Function not implemented", exit
status 243/CREDENTIALS. Everything else failing or hanging follows from journald being down.

From systemd 262, `ProtectProc=invisible` makes systemd pass `hidepid=invisible`
unconditionally. 4.14 procfs parses `hidepid=%u` with `match_int`; textual values arrived
in 5.8. The code tries `fsopen()` first, gets ENOSYS, and the classic-mount fallback is what
gets the EINVAL: "Failed to set up mount namespacing: /proc: Invalid argument", exit status
226/NAMESPACE, on userdbd.

### What Droidspaces does about it

Every place systemd 259 to 262 calls the new mount API during service start handles EPERM
gracefully, verified in the source: credentials fall back to a plain directory
(`exec-credential.c`, `ERRNO_IS_NEG_PRIVILEGE(mfd)`), the private `/proc`, `/sys` and
cgroup2 code reuses the existing mount when it lacks privilege (`namespace.c`,
`mount_private_apivfs()`), the mount option probes treat any error as "unknown", and the
`open_tree()` fast path in `xopenat_full()` falls back to `openat()` on EPERM explicitly.

So Droidspaces newer than 7.1.0 installs one more seccomp filter on a systemd PID 1 when
the kernel answers ENOSYS to `fsopen()`: syscalls 428 to 433 return EPERM. `mount_setattr`
(442) is left alone, systemd handles its ENOSYS correctly already.

util-linux wants the opposite. libmount also uses the new mount API and falls back to
`mount(2)` only on ENOSYS; it reports EPERM as a real error, so under the filter
`dev-mqueue.mount` and `sys-fs-fuse-connections.mount` fail with exit status 32. Hence the
filter is installed only on the systemd PID 1, not on processes entered with `run` or
`exec`, and systemd gets `systemd.setenv=LIBMOUNT_FORCE_MOUNT2=always` on its command line
while login shells get the same variable through `/run/droidspaces.env`. libmount reads it
and uses `mount(2)` directly.

What this costs: credentials in a plain directory instead of a private tmpfs, and
`ProtectProc=` is a no-op. Both are what systemd itself chooses for unprivileged user
managers. The fix covers every pre-5.2 kernel at once, not only patched 4.14 trees. Another
container runtime would need the same two things: EPERM for syscalls 428 to 433 on PID 1's
seccomp filter, and `LIBMOUNT_FORCE_MOUNT2=always` for everything that will run `mount`.
systemd has no switch for this.

### Why the mount API is not backported instead

Measured on mainline between v5.0 and v5.2, the core of the series without any filesystem
conversions is about 35 commits: 1686 new lines in `fs/fs_context.c`, `fs/fsopen.c` and
`fs/fs_parser.c`, 1334 changed lines across `fs/namespace.c`, `fs/super.c` and the core
headers, 417 lines of new headers, and 2267 changed lines in the LSM hooks, SELinux and
Smack, partly from the unrelated LSM stacking rework of the same window. Converting the
filesystems systemd mounts, procfs, sysfs and cgroup, adds about 1100 lines and 70 commits
in total.

On top of that, `fs/namespace.c` differs from the exynos9820 4.14 copy by 847 lines before
the series even starts, `fs/super.c` by 405 and `include/linux/fs.h` by 507, because 4.15
to 5.0 renamed the superblock flags to `SB_*`, reworked `mount_ns()` and changed the
security hooks the series then builds on. SELinux must grow the new `sb_eat_lsm_opts` and
`sb_kern_mount` hooks, which on a Samsung kernel with Knox patches in
`security/selinux/hooks.c` is where the real conflicts are.

Feasible for a kernel developer who owns the tree, in the order of two to four weeks
including testing, with real regression risk in `fs/namespace.c` and SELinux. Not a patch
set that can be handed over. The seccomp filter gets the same user-visible result with no
kernel change.

## Why networkd dies on a kernel with 31 multicast groups

In `manager_connect_rtnl()` networkd subscribes to `RTM_NEWNEXTHOP`, which joins multicast
group `RTNLGRP_NEXTHOP`, number 32. A 4.14 or 4.19 kernel has 31 groups, so
`NETLINK_ADD_MEMBERSHIP` returns EINVAL and networkd exits with "Could not set up manager"
before enumerating anything. systemd 258 removed the nexthop fallback in 034b69d8b "network:
assume nexthop is supported". Nothing in userspace can avoid this.

The last patch of each series is the fix, about 25 lines and original rather than a
backport. It adds the 5.3 uapi message types and the group, an `RTM_GETNEXTHOP` handler
that returns an empty dump, and the three rows in `security/selinux/nlmsgtab.c` that keep
the table's `BUILD_BUG_ON(RTM_MAX != ...)` true. The real nexthop code is 2000 lines and
systemd only needs it for `[NextHop]` sections.

## Things that are not the problem

- `clone3` is never called by systemd directly. glibc's posix_spawn uses it when
  `POSIX_SPAWN_SETCGROUP` is set, and systemd keeps an ENOSYS fallback for that through
  v260. glibc falls back to `clone()` with `CLONE_PIDFD` when clone3 returns ENOSYS, and
  Droidspaces blocks clone3 anyway when sandboxing is off.
- `openat2` is never called. Path resolution is systemd's own `chase()` in userspace.
- `pidfs` (6.9), `SO_PEERPIDFD` (6.5), `STATX_MNT_ID_UNIQUE` (6.8) and `MOVE_MOUNT_BENEATH`
  (6.5) are all probed and optional.
- Droidspaces' seccomp filter is a denylist with an allow-everything tail, so the new
  syscall numbers pass through.
- The glibc version only changes which path needs the pidfd series. With glibc 2.39 or
  newer every service spawn goes through `pidfd_spawn()`, which needs `CLONE_PIDFD`. With an
  older glibc it is `posix_spawn()` then `pidfd_open()`. Both tested guests ship a current
  glibc; an older one is covered by the same patches.

## What Google's common kernels have

Probed on `aosp-mirror/kernel_common`. The one table in these docs, because five branches
against seventeen features does not read as prose. Vendor trees derived from these branches
matched the corresponding Google branch line for line in every probe.

| Feature | Kernel | 4.9-q (4.9.337) | 4.14-stable (4.14.336) | 4.19-stable (4.19.325) | android12-5.4-lts (5.4.301) | android13-5.10-lts |
|---|---|---|---|---|---|---|
| statx | 4.11 | no | yes | yes | yes | yes |
| NS_GET_NSTYPE ioctl | 4.11 | no | yes | yes | yes | yes |
| TIOCGPTPEER | 4.13 | no | yes | yes | yes | yes |
| SO_PEERGROUPS | 4.13 | no | yes | yes | yes | yes |
| cgroup2 nsdelegate | 4.13 | no | yes | yes | yes | yes |
| cgroup2 cpu controller | 4.15 | no | no | yes | yes | yes |
| pidfd_send_signal, CLONE_PIDFD, pidfd_open, pidfd poll | 5.1 to 5.3 | yes (Android backport) | yes (Android backport) | yes (Android backport) | yes | yes |
| waitid P_PIDFD | 5.4 | no | no | no | yes | yes |
| SO_BINDTOIFINDEX | 5.1 | no | no | no | yes | yes |
| New mount API (fsopen and friends) | 5.2 | no | no | no | yes | yes |
| cgroup2 freezer | 5.2 | no | no | yes | yes | yes |
| Nexthop netlink types and group | 5.3 | no | no | no | yes | yes |
| memory_recursiveprot | 5.7 | no | no | no | no | yes |
| STATX_MNT_ID, STATX_ATTR_MOUNT_ROOT | 5.8 | no | no | no | no | yes |
| utimensat AT_EMPTY_PATH, faccessat2 | 5.8 | no | no | no | no | yes |
| Textual hidepid= | 5.8 | no | no | no | no | yes |
| close_range | 5.9 | no | no | no | no | yes |
| MS_NOSYMFOLLOW | 5.10 | no | no | no | no | yes |

Of the frozen OEM trees that were probed, Samsung's stock exynos9820 at 4.14.113 lacks the
whole pidfd backport, PSI, the cgroup2 cpu controller and freezer and `GRND_INSECURE`. The
SCV41 at 4.14.190 has pidfd and PSI but not the rest. The Galaxy A13 at 4.19.198 has all of
those. None of the three has anything the two series add.

## How this was checked

```
git clone --depth 1 https://github.com/systemd/systemd
git fetch --depth 1 origin tag v257.9 tag v258 tag v259 tag v260
git fetch --shallow-exclude=v257.9 origin tag v258     # history for blame
git fetch --shallow-exclude=v258 origin tag v260
git show v258:README | sed -n 30,70p                   # requirement tables
git log v257.9..v258 --grep='drop support' --grep='baseline' --grep='assume' -i -- src
git log v259..v260   --grep='drop' --grep='baseline' --grep='since kernel' -i -- src
git diff v257.9 v258 -- src | grep '^-.*ERRNO_IS_NOT_SUPPORTED'
```

Key files to read when verifying a claim: `src/basic/pidref.c`, `src/basic/process-util.c`
(`posix_spawn_wrapper`, `pidref_safe_fork_full`), `src/libsystemd/sd-event/sd-event.c`
(`sd_event_add_child`), `src/core/main.c` (`cg_has_legacy`), `src/shared/mount-setup.c`
(the fatal mount table), `src/basic/fd-util.c` (`close_all_fds`),
`src/basic/mountpoint-util.c` and `src/basic/stat-util.c` (mount id handling),
`src/core/exec-credential.c` and `src/core/namespace.c` (mount API callers).

systemd's baseline will move again. 260 raised it to 5.10 and the README already lists 5.12
to 5.14 features as recommended. Each bump can remove another fallback this repository
relies on, so read the README and NEWS of the systemd release you target before starting,
and grep its source for `ERRNO_IS_NOT_SUPPORTED` around the syscalls your kernel lacks.

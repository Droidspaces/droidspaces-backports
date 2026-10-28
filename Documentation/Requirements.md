# What systemd needs from the kernel

Everything on this page was read out of the systemd source at tags v257.9, v258, v259 and
v260, not from release notes alone. Each row names the systemd commit that removed the
fallback, so you can diff it yourself. Kernel versions are the mainline release that
introduced the feature. Kernel commit hashes live on the [porting page](Porting.md).

## systemd baselines

systemd publishes a kernel baseline and removes fallbacks for anything older. The baseline
is not a check at startup, it is a promise about which fallbacks still exist in the code.

| systemd | Released | Minimum kernel | What was removed or added |
|---|---|---|---|
| 257.x | 2024-12, 257.9 on 2025-09-03 | 3.15 | Still boots on 4.x. Fallbacks for pre-pidfd kernels and cgroup v1 are present. |
| 258 | 2025-09-17 | 5.4 | pidfd fallbacks, cgroup v1, SO_BINDTODEVICE fallback, nexthop fallback in networkd, TIOCGPTPEER and ambient capability fallbacks, statx fallback. |
| 259 | 2025-12-17 | 5.4 | Service credentials are now built with the new mount API (fsopen, fsmount, move_mount). |
| 260 | 2026-03-17 | 5.10 | close_range, STATX_MNT_ID, STATX_ATTR_MOUNT_ROOT, AT_EMPTY_PATH for utimensat and faccessat, memory_recursiveprot, MS_NOSYMFOLLOW fallbacks. |
| 261, 262 | 2026 | 5.10 | No new kernel requirement. 262 passes textual `hidepid=` unconditionally. |

Two kinds of gap. A **hard** gap stops PID 1 or every service. A **soft** gap costs one
feature and a log line. Most of systemd's README list is soft. The hard ones are what the
patches in this repository fix.

The notes below are written for 4.14. They apply to 4.19 with one difference: 4.19 already
has the cgroup v2 cpu controller and the cgroup freezer, PSI is 4.20 so still missing, and
everything from 5.1 upward is still missing.

## What 4.14 already has

No work needed for these. systemd 260 still lists them, and 4.14 ships them:

| Feature | Kernel | Used for |
|---|---|---|
| timerfd CLOCK_BOOTTIME | 3.15 | sd-event timers |
| memfd_create, getrandom | 3.17 | everywhere |
| ambient capabilities | 4.3 | AmbientCapabilities=, nspawn |
| pids controller in cgroup v2 | 4.5 | TasksMax= |
| cgroup namespaces | 4.6 | PrivateUsers=, nspawn |
| statx | 4.11 | file metadata (the mount id field comes later, see systemd 260 below) |
| nsfs NS_GET_NSTYPE | 4.11 | namespace type detection |
| TIOCGPTPEER | 4.13 | pty handling (fallback removed in 258, commit 1d522f1a8) |
| cgroup2 nsdelegate mount option | 4.13 | PID 1 mounts cgroup2 with it |
| cgroup2 threaded mode | 4.14 | cgroup.type, cgroup.threads |

## Hard requirements for systemd 258 and 259

Without these PID 1 either refuses to start or cannot start a single service. Order is
roughly the order you will hit them.

| # | Kernel feature | Kernel | Syscall or ABI | How systemd uses it | Fallback removed in | Symptom when missing |
|---|---|---|---|---|---|---|
| 1 | cgroup2 filesystem at /sys/fs/cgroup, no v1 hierarchy under it | 4.5 | cgroup2 fs mounted on /sys/fs/cgroup | PID 1 calls `cg_has_legacy()` before anything else and aborts if /sys/fs/cgroup is a tmpfs holding v1 mounts. The cgroup2 mount is `MNT_FATAL`. Controllers are not required: whatever is missing from `cgroup.controllers` is just not enabled. | c35a58576 "cgroup-setup: drop cgroup v1 support", 8a05dbb31, 4ee64e436 | "Detected cgroup v1 hierarchy at /sys/fs/cgroup/, which is no longer supported ... refusing execution". `systemd.unified_cgroup_hierarchy=0` and `--force-cgroupv1` no longer help. **Already satisfied in a Droidspaces container:** the runtime mounts a fresh cgroup2 there, so this row is only work for a native boot. |
| 2 | pidfd_send_signal | 5.1 | `pidfd_send_signal(2)`, syscall 424 | `pidref_kill()` uses it whenever a pidfd is held, which after item 3 is always. sd-event child sources signal through it. | 6e14c46ba "tree-wide: drop support for kernels without pidfd_open() and pidfd_send_signal()" | ENOSYS on every kill of a service. |
| 3 | pidfd_open and pollable pidfds | 5.3 | `pidfd_open(2)`, syscall 434, plus `poll()` on the fd returning POLLIN on exit | `pidref_set_pid()` returns the error instead of falling back to a bare PID. Every spawn goes through it (`posix_spawn_wrapper` without pidfd_spawn, `pidref_safe_fork_full`). `sd_event_add_child()` returns the error too, so every systemd daemon that watches children fails, not only PID 1. | 6e14c46ba, plus 0df46f890 | "Failed to spawn executor: Function not implemented" for every unit. journald, udevd, logind fail to watch children. This is the ENOSYS flood. |
| 4 | CLONE_PIDFD | 5.2 | `clone()`/`clone3()` flag 0x1000 | glibc 2.39+ implements `pidfd_spawn()` with it, and systemd built against such a glibc uses `pidfd_spawn()` for every service. glibc gates the whole thing on one probe, `waitid(P_PIDFD, INT_MAX, ...)` returning EBADF rather than EINVAL (`__clone_pidfd_supported()` in `sysdeps/unix/sysv/linux/clone-pidfd-support.c`), and returns ENOSYS otherwise. It tries clone3 first and on ENOSYS falls back to legacy `clone()` with CLONE_PIDFD, taking the fd back through the parent_tid slot. So clone3 is not needed, but items 4 and 5 are. v257.9 fell back to plain `posix_spawn()` here; v258 returns the error. | 6e14c46ba (the `clone_support` state machine in `posix_spawn_wrapper` was removed) | Same symptom as item 3, even with pidfd_open present, when the distribution's glibc is 2.39 or newer. Arch, Fedora and openSUSE Tumbleweed all ship glibc 2.39+. |
| 5 | waitid(P_PIDFD) | 5.4 | `waitid(2)` idtype 3 | `pidref_wait()` and sd-event reap children by pidfd. glibc's `pidfd_spawn` probe (item 4) depends on this exact behaviour: EBADF for a bad fd, not EINVAL. | 0df46f890 "pidref: drop support for kernels lacking waitid(P_PIDFD, …)" | EINVAL when reaping. Services that exit are never reaped, so PID 1 hangs on them. |
| 6 | pidfd fdinfo and `/proc/<pid>` consistency | 5.3 | `/proc/self/fdinfo/<fd>` carrying `Pid:` | `pidfd_get_pid()` reads it to map a received pidfd back to a PID (sd_notify with pidfd, logind sessions). | part of the pidfd series | Not fatal for boot, but notify handling and logind break. Comes with the pidfd_open backport. |

Items 2 to 6 are one kernel series, living in `kernel/pid.c`, `kernel/fork.c`,
`kernel/signal.c`, `kernel/exit.c`, `fs/proc/base.c` and the arch syscall tables. Every
Android 4.14 kernel derived from Google's common tree after mid 2019, and every Android 4.19
kernel, already carries Google's Android R backport of items 2, 3, 4 and 6. Item 5 is the
only one none of them has, and it is patch 1 of both series. Trees frozen before the
backport landed need [`pidfd-backport-4.14/`](../pidfd-backport-4.14/README.md) first.

The cgroup v2 cpu controller (4.15) is not a blocker. systemd 258 boots fine with an empty
`cgroup.controllers`, as Droidspaces containers on Android show: the host keeps cpu, memory
and pids on v1 hierarchies, the guest's cgroup2 has none of them, and PID 1 only warns.

## Soft requirements for systemd 258 and 259

These produce warnings or disable a feature. None stops boot. Listed because a flood of
them is easy to misread as the real failure, and because some break networking inside a
container, which looks like a failed boot.

| Kernel feature | Kernel | Where systemd assumes it | Fallback removed in | What you lose on 4.14 |
|---|---|---|---|---|
| SO_BINDTOIFINDEX | 5.1 | `socket_bind_to_ifindex()` in resolved, networkd DHCP, ICMPv6, local-addresses | ddbbc98bd "drop SO_BINDTODEVICE fallback" | **resolved cannot bind per-interface sockets, the DHCP client cannot bind. DNS and DHCP inside the guest break.** Small, and patched in both series. |
| nexthop netlink types and multicast group | 5.3 | networkd `manager_connect_rtnl()` | 034b69d8b "network: assume nexthop is supported" | **networkd exits before enumerating anything, so no DHCP.** See [nexthop](#nexthop-why-networkd-dies-on-a-kernel-with-31-multicast-groups) below. Patched in both series. |
| cgroup freezer (`cgroup.freeze`) | 5.2 | `unit_cgroup_freezer_action()` | 3c86a935a "drop cg_freezer_supported(), assume supported" | `systemctl freeze`, sleep inhibitor freezing fail. Boot unaffected. Present on 4.19. |
| New mount API: fsopen, fsconfig, fsmount, move_mount, open_tree, fspick | 5.2 | `mount_option_supported()` probing (hidepid=, subset=, memory_recursiveprot), ExtensionDirectories= overlay, bpffs for BPF tokens, and from 259 service credentials | c2198d0c3 "assume fsopen() works in mount_option_supported()" | On 258 the probes return an error, callers treat it as "option not supported" and continue. From 259 it is fatal for every service with credentials. See [the new mount API](#the-new-mount-api) below. |
| FRA_PROTOCOL for fib rules | 4.17 | networkd routing policy rules | README requirement | networkd rule bookkeeping degraded. |
| cgroup v2 cpu controller and per-cgroup `cpu.stat` | 4.15 | 258 "always enable CPU accounting" reads `cpu.stat` per unit; CPUWeight=, CPUQuota= need the controller | 29da53dde | One "Failed to enable/disable controllers on cgroup ..., ignoring" warning per unit, CPU accounting reads zero, CPU limits do nothing. Boot unaffected. Same for memory, pids and io when the host holds them on v1. Present on 4.19. |
| cgroup-bpf device hook | 4.15 | DeviceAllow=, DevicePolicy= | probed via `bpf_program_supported()` | Device access control silently off. |
| cgroup-bpf socket address hooks | 4.17 | SocketBindAllow=, RestrictNetworkInterfaces= | probed | Silently off. |
| Bounded loops in BPF | 5.3 | bpf-firewall, restrict-ifaces programs | README requirement | Programs fail the verifier, feature off. |
| PSI | 4.20 | systemd-oomd | README requirement | oomd refuses to start. Not started in a container anyway. |
| /sys/power/resume_offset | 4.17 | hibernation | de69879b6 | Hibernate to swapfile unsupported. |
| Keyring namespacing | 5.3 | README lists it; `keyctl(KEYCTL_JOIN_SESSION_KEYRING)` ENOSYS is still handled | n/a | Nothing, as long as CONFIG_KEYS is on. |
| CLONE_INTO_CGROUP | 5.7 | `posix_spawn_wrapper` | fallback kept | Slower spawn, process moved to cgroup after fork. |
| Signed dm-verity images | 5.4 | RootImage=, DDIs | README requirement | Verity signature checking only. |

## What systemd 260 adds

Needed for 260 and later, on top of everything above. A stock 5.4 LTS kernel is missing
exactly these.

| # | Kernel feature | Kernel | Syscall or ABI | How systemd uses it | Fallback removed in | Symptom when missing |
|---|---|---|---|---|---|---|
| 7 | close_range | 5.9 | `close_range(2)`, syscall 436 | `close_all_fds()` runs in the child of every `safe_fork()` with FORK_CLOSE_ALL_FDS, which is nearly every fork in systemd. The child `_exit(EXIT_FAILURE)`s if it fails. systemd passes flags 0, so `CLOSE_RANGE_UNSHARE` and `CLOSE_RANGE_CLOEXEC` are not needed. | c471cca09 "fd-util: close_range() is available since kernel 5.9" | Every forked helper dies with "Failed to close all file descriptors: Function not implemented". |
| 8 | STATX_MNT_ID and STATX_ATTR_MOUNT_ROOT | 5.8 (systemd's README dates reliable support to 5.10) | `statx(2)` mask 0x1000, `stx_mnt_id`, and the `stx_attributes` bit | `path_get_mnt_id_at()` and `fd_is_mount_point()` return `EUNATCH` when the mask or attribute is not honoured. `mount_setup()` calls `path_is_mount_point_full()` for every API filesystem and the entries for /proc, /sys, /dev, /run, cgroup2 are `MNT_FATAL`. | 7ecfa87c5 "STATX_MNT_ID is supported since kernel 5.10", a98a6eb95 | PID 1 dies in mount setup: "Failed to determine whether /proc is a mount point". |
| 9 | faccessat2, and AT_EMPTY_PATH on utimensat | 5.8 | `faccessat2(2)` syscall 439, `utimensat(fd, "", ..., AT_EMPTY_PATH)` | `access_fd()` runs on every `chase()` with access checks. glibc routes any `faccessat()` call with flags through faccessat2 and answers EINVAL when the kernel lacks it. `futimens_opath()` lost its /proc/self/fd fallback. | 52bf232e8 "drop fallback for kernels without AT_EMPTY_PATH support (< 5.8)" | tmpfiles, journal, udev, the tar importer and credential handling fail with EINVAL. |
| 10 | cgroup2 `memory_recursiveprot` mount option | 5.7 | mount option | PID 1 mounts cgroup2 with `nsdelegate,memory_recursiveprot` unconditionally. The entry is `MNT_FATAL`. If something already mounted cgroup2 (a container runtime), the entry is skipped. | 80c5b63db "mount-setup: memory_recursiveprot is supported since kernel v5.7" | Bare-metal or VM boot: "Failed to mount cgroup2 ... Invalid argument" and PID 1 exits. Container with pre-mounted cgroup2: no effect. **Not patched here, Droidspaces mounts cgroup2 for the guest.** |
| 11 | getrandom GRND_INSECURE | 5.6 | flag 0x4 | `random_bytes()` | ec21e5c58 | Soft: EINVAL, then falls back to /dev/urandom. Android 4.14 and 4.19 trees already have it. |
| 12 | MS_NOSYMFOLLOW | 5.10 | mount flag 0x100 | credentials mounts in `import-creds.c`, both calls `(void)` their result; nspawn and dissect-image use it too | 6753bd8a2 | Soft for PID 1: a warning per credentials mount. nspawn and RootImage= mounts fail. Not patched here. |
| 13 | procfs per-instance hidepid= and subset= | 5.8 | mount options as strings | ProtectProc=, ProcSubset= | README | Probed through fsopen, treated as unsupported. 262 passes `hidepid=invisible` unconditionally for `ProtectProc=invisible` units, see [the new mount API](#the-new-mount-api). |
| 14 | LOOP_CONFIGURE | 5.8 | ioctl | loop device setup for images | README | repart, dissect, RootImage= fail. Boot unaffected. |
| 15 | epoll_pwait2 | 5.11 | syscall 441 | sd-event | fallback kept (`epoll_pwait2_absent`) | Nothing. |
| 16 | idmapped mounts, mount_setattr | 5.12 | syscall 442 | DynamicUser= with PrivateUsers=, nspawn --private-users | optional in README | Feature off. systemd handles its ENOSYS correctly. |
| 17 | cgroup.kill | 5.14 | file | `cg_kill_kernel_sigkill()` with fallback to walking the cgroup | fallback kept | Nothing. |
| 18 | quotactl_fd | 5.14 | syscall 443 | tmpfs quotas, homed | optional | Feature off. |

Items 7, 8 and 9 are patches 4 to 9 of the 4.14 series and 3 to 8 of the 4.19 series.
Items 10 to 18 are deliberately not patched: either systemd keeps a fallback, or Droidspaces
makes the feature irrelevant, or it only affects a feature nobody runs in a container.

## The new mount API

Kernels below 5.2 have no `fsopen()`, `fsconfig()`, `fsmount()`, `move_mount()`,
`open_tree()` or `fspick()`. With the patches above applied, systemd 259 and 262 both boot
on 4.14, reach their default target and spawn services, and these two failures remain:

| Log line | Cause | systemd since |
|---|---|---|
| `Failed to set up credentials: Function not implemented`, exit status 243/CREDENTIALS, on journald, sysctl, tmpfiles, sysusers, udev, resolved, networkd, getty | `exec-credential.c` builds the credentials directory with `fsopen()`, `fsconfig()`, `fsmount()` and `move_mount()`. It falls back to a plain directory only on EPERM or EACCES, never on ENOSYS. | v259 |
| `Failed to set up mount namespacing: /proc: Invalid argument`, exit status 226/NAMESPACE, on userdbd | `ProtectProc=invisible` makes systemd pass `hidepid=invisible` unconditionally. 4.14 procfs parses `hidepid=%u` with `match_int`, textual values arrived in 5.8. The code first tries `fsopen()`, gets ENOSYS, and the classic-mount fallback is what gets the EINVAL. | v262 |

Everything downstream (dbus-broker, getty, resolved failing or hanging) follows from
journald and userdbd being down.

### What Droidspaces does

Every place systemd 259 to 262 calls the new mount API during service start handles EPERM
gracefully, verified in the source: credentials fall back to a plain directory
(`exec-credential.c`, `ERRNO_IS_NEG_PRIVILEGE(mfd)`), the private `/proc`, `/sys` and
cgroup2 code reuses the existing mount when it lacks privilege (`namespace.c`,
`mount_private_apivfs()`), mount option probes treat any error as "unknown", and the
`open_tree()` fast path in `xopenat_full()` falls back to `openat()` on EPERM explicitly.

So Droidspaces newer than 7.1.0 installs one more seccomp filter on a systemd PID 1 when
the kernel answers ENOSYS to `fsopen()`: syscalls 428 to 433 (`open_tree`, `move_mount`,
`fsopen`, `fsconfig`, `fsmount`, `fspick`) return EPERM. `mount_setattr` (442) is left
alone. `droidspaces check` reports the probe as the `New mount API` row.

util-linux wants the opposite. libmount also uses the new mount API and falls back to
`mount(2)` only on ENOSYS; it reports EPERM as a real error, so under the filter
`dev-mqueue.mount` and `sys-fs-fuse-connections.mount` fail with exit status 32. Hence the
filter is installed only on the systemd PID 1, not on processes entered with `run` or
`exec`, and systemd gets `systemd.setenv=LIBMOUNT_FORCE_MOUNT2=always` on its command line
while login shells get the same variable through `/run/droidspaces.env`. libmount reads it
and uses `mount(2)` directly.

What this costs: credentials in a plain directory instead of a private tmpfs, and
`ProtectProc=` is a no-op. Both are what systemd itself chooses for unprivileged user
managers. The fix covers every pre-5.2 kernel at once, not only patched 4.14 trees.

If you run a different container runtime, you need an equivalent: EPERM for 428 to 433 on
PID 1's seccomp filter, plus `LIBMOUNT_FORCE_MOUNT2=always` for everything that will run
`mount`. There is no userspace-only alternative; systemd has no switch for this.

### Why the mount API is not backported instead

Measured on mainline between v5.0 and v5.2, the core of the series without any filesystem
conversions:

| Files | Lines |
|---|---|
| `fs/fs_context.c`, `fs/fsopen.c`, `fs/fs_parser.c` (new) | 1686 added |
| `fs/namespace.c`, `fs/super.c`, `fs/internal.h`, `include/linux/fs.h`, `include/linux/mount.h` | 1334 changed |
| `include/linux/fs_context.h`, `include/linux/fs_parser.h`, `include/uapi/linux/mount.h` (new) | 417 added |
| LSM hooks: `lsm_hooks.h`, `security.h`, `security/security.c`, SELinux, Smack | 2267 changed, partly the unrelated LSM stacking rework of the same window |
| Converted filesystems systemd mounts: procfs, kernfs/sysfs, cgroup | 1118 added, 700 removed |

About 35 commits for the core, 70 with the conversions and fixes. On top of that,
`fs/namespace.c` differs from the exynos9820 4.14 copy by 847 lines before the series even
starts, `fs/super.c` by 405 and `include/linux/fs.h` by 507, because 4.15 to 5.0 renamed
the superblock flags to `SB_*`, reworked `mount_ns()`, and changed the security hooks the
series then builds on. The legacy `fs_context` shim means unconverted filesystems keep
working through `fsopen()`, so tmpfs, ramfs and bpffs would not need converting, but procfs,
sysfs and cgroup would still have to move to `->init_fs_context`, and SELinux must grow the
new `sb_eat_lsm_opts`/`sb_kern_mount` hooks, which on a Samsung kernel with Knox patches in
`security/selinux/hooks.c` is where the real conflicts are.

Verdict: feasible for a kernel developer who owns the tree, in the order of two to four
weeks including the filesystem conversions and testing, with real regression risk in
`fs/namespace.c` and SELinux. Not a patch set that can be handed over. The seccomp filter
gets the same user-visible result with no kernel change.

## Nexthop: why networkd dies on a kernel with 31 multicast groups

In `manager_connect_rtnl()` networkd subscribes to `RTM_NEWNEXTHOP`, which joins multicast
group `RTNLGRP_NEXTHOP` (32). A 4.14 or 4.19 kernel has 31 groups, so
`NETLINK_ADD_MEMBERSHIP` returns EINVAL and networkd exits with "Could not set up manager"
before enumerating anything. systemd 258 removed the nexthop fallback (commit 034b69d8b).
Nothing in userspace can avoid this. On the console it looks like networkd restarting five
times and eth0 having only an IPv6 address.

The last patch of each series is the fix: about 25 lines, original rather than a backport.
It adds the 5.3 uapi message types and group, an `RTM_GETNEXTHOP` handler that returns an
empty dump, and the three rows in `security/selinux/nlmsgtab.c`. Without those rows the
SELinux table's `BUILD_BUG_ON(RTM_MAX != ...)` fails, which under LTO shows up as an
undefined `__compiletime_assert_NNN` in `selinux_nlmsg_lookup` at link time. The real
nexthop code is 2000 lines and systemd only needs it for `[NextHop]` sections.

## Things that are not the problem

- `clone3` is never called by systemd directly. glibc's posix_spawn uses it when
  `POSIX_SPAWN_SETCGROUP` is set, and systemd keeps an ENOSYS fallback for that through
  v260 (the comment in `posix_spawn_wrapper` names 5.4 as a kernel that needs it). glibc
  falls back to `clone()` with CLONE_PIDFD when clone3 returns ENOSYS, and Droidspaces
  blocks clone3 anyway when sandboxing is off.
- `openat2` is never called. Path resolution is systemd's own `chase()` in userspace.
- `pidfs` (6.9), `SO_PEERPIDFD` (6.5), `STATX_MNT_ID_UNIQUE` (6.8), `MOVE_MOUNT_BENEATH`
  (6.5) are all probed and optional.
- Droidspaces' seccomp filter is a denylist with an allow-everything tail, so the new
  syscall numbers pass through.

## Userspace knobs that change the picture

- **glibc version.** With glibc 2.39 or newer, systemd is built with `HAVE_PIDFD_SPAWN` and
  every service spawn goes through `pidfd_spawn()`, which needs CLONE_PIDFD (item 4). With an
  older glibc it uses `posix_spawn()` then `pidfd_open()` (item 3). Both paths need the
  pidfd series. There is no build option to avoid it. Both tested guests ship a current
  glibc with `pidfd_spawn`.
- **Container runtime pre-mounting cgroup2** skips the fatal cgroup2 mount entry in PID 1,
  which hides item 10 and the `nsdelegate` requirement. It does not hide item 1: a v1
  hierarchy anywhere under /sys/fs/cgroup still aborts PID 1.
- **Pinning systemd** is the zero-kernel-work option: 257.x boots on 4.x, 258 and 259 boot
  on 5.4, 260 needs 5.10.

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

Key files to read when verifying a row: `src/basic/pidref.c`, `src/basic/process-util.c`
(`posix_spawn_wrapper`, `pidref_safe_fork_full`), `src/libsystemd/sd-event/sd-event.c`
(`sd_event_add_child`), `src/core/main.c` (`cg_has_legacy` check), `src/shared/mount-setup.c`
(the `MNT_FATAL` table), `src/basic/fd-util.c` (`close_all_fds`),
`src/basic/mountpoint-util.c` and `src/basic/stat-util.c` (mount id handling),
`src/core/exec-credential.c` and `src/core/namespace.c` (new mount API callers).

systemd's own baseline will move again. 260 raised it to 5.10 and the README already lists
5.12 to 5.14 features (idmapped mounts, `cgroup.kill`, `quotactl_fd`) as recommended. Each
bump can remove another fallback this page relies on, so read the README and NEWS of the
systemd release you target before starting, and grep its source for
`ERRNO_IS_NOT_SUPPORTED` around the syscalls your kernel lacks.

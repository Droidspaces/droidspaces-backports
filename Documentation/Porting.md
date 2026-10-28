# Porting to your own tree

Read this when your kernel is not one of the trees the series were applied to, or when it
is 4.9 or 5.4, which have no ready series. Everything here was worked out on a Samsung
exynos9820 4.14 tree and checked against Google's common kernel branches and seven vendor
trees. Where something is a guess it says so.

## Find out what your tree already has

Android common kernels carry backports that mainline stable does not, and vendor kernels
stop at whatever stable point the SoC vendor froze on. The series number alone tells you
little. Run the probe before planning anything:

```
tools/probe-kernel.sh <git dir> <rev>
```

It prints yes or no for every kernel feature systemd 258 to 262 cares about, and works on a
blobless clone because each probe fetches only the one file it reads. On the device,
`droidspaces check` shows the runtime view, including the `New mount API` row that the
seccomp shim keys off.

## What Google's common kernels have

Probed on `aosp-mirror/kernel_common`. Columns are the branch names.

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

Vendor trees derived from these branches, such as the exynos9820 one this was developed on,
matched the corresponding Google branch line for line in every probe.

## Frozen OEM kernels

Three real trees, probed the same way:

| Feature | Samsung stock exynos9820, 4.14.113 (Android 9) | Samsung SCV41, 4.14.190 (Android 10/11) | Samsung A13 exynos850, 4.19.198 (Android 11) |
|---|---|---|---|
| pidfd_send_signal, CLONE_PIDFD, pidfd_open, pidfd poll | **no** | yes | yes |
| PSI | no | yes | yes |
| cgroup2 cpu controller, freezer | no | no | yes |
| GRND_INSECURE | no | no | yes |
| everything the two series add (P_PIDFD, SO_BINDTOIFINDEX, statx bits, faccessat2, close_range, nexthop) | no | no | no |

The pidfd row is the one that matters. Google merged its Android R pidfd backport into
android-4.14 in mid 2019 (thirteen `BACKPORT:`/`UPSTREAM:` commits in the
android-4.14-stable history); any 4.14 vendor tree frozen before that has none of it, and
systemd 258 cannot start a single service without `pidfd_open()`. For those trees
[`pidfd-backport-4.14/`](../pidfd-backport-4.14/README.md) carries Google's twelve commits
re-applied to the 4.14.113 Samsung tree. Every 4.19 Android kernel already has the
backport, 4.19 shipped after it landed.

The missing cgroup2 cpu controller and freezer on the 4.14 trees do not matter for a
container guest: Droidspaces mounts cgroup2 and systemd takes whatever controllers exist.
Missing PSI only costs `systemd-oomd`, which is not started in a container.

After the pidfd backport all three trees take their series unchanged:

| Tree | Prerequisite | Series | Result |
|---|---|---|---|
| stock exynos9820 4.14.113 | `pidfd-backport-4.14/` (12 patches) | `kernel-4.14-series/` | all ten apply unchanged |
| SCV41 4.14.190 | none | `kernel-4.14-series/` | all ten apply unchanged |
| A13 exynos850 4.19.198 | none | `kernel-4.19-series/` | all ten apply unchanged |

None of the three was compiled or booted; the series themselves were compiled on Google's
4.14 and 4.19 trees and the extremerom 4.14 tree, and booted on the latter.

## What each kernel series needs

### 5.10 and newer

Nothing. systemd 262 boots unmodified.

### 5.4

Runs systemd 258 and 259 as is. For 260 and newer it needs the three 5.8 and 5.9 pieces:
statx mount id and mount root, utimensat and faccessat2 with AT_EMPTY_PATH, close_range.
The new mount API and nexthops are present, so neither the seccomp shim nor the nexthop
stub is involved. The patch files in this repository are written against 4.14 and 4.19
context and do not apply unchanged to 5.4 (syscall table tails, `fs/file.c` and `fs/open.c`
moved on), so cherry-pick the mainline commits from the table below instead.
`memory_recursiveprot` is only needed for a native boot; Droidspaces mounts cgroup2 before
systemd gets to it.

### 4.19

Has the pidfd backport, statx, TIOCGPTPEER, the cgroup2 cpu controller and freezer. Needs
exactly what 4.14 needs: P_PIDFD, SO_BINDTOIFINDEX, the nexthop stub, and the 5.8 and 5.9
pieces for 260 and newer. The seccomp shim in Droidspaces covers the missing mount API. The
parent_tidptr fix (4.14's patch 2) is not needed, the 4.19 backport never had the check.

[`kernel-4.19-series/`](../kernel-4.19-series/README.md) was ported against Google's
`android-4.19-stable` and compile-tested there. It was also applied to four vendor trees;
three take patches 1 to 9 unchanged, and Samsung's universal9830 already carries some of
the syscalls and needs four table lines by hand. Not boot-tested on a device; the gaps are
the same set 4.14 had and that set is boot-tested.

### 4.14

[`kernel-4.14-series/`](../kernel-4.14-series/README.md), in order. Boot-tested with
systemd 259 and 262 on exynos9820 4.14.356. If the probe says `pidfd_open no` (Android 9
era trees, roughly anything below 4.14.150), apply `pidfd-backport-4.14/` first.

### 4.9

Everything 4.14 needs, plus the 4.11 to 4.13 pieces the Google matrix shows missing. In
order of how hard systemd fails without them:

| Missing | Kernel | Mainline commit | Severity |
|---|---|---|---|
| statx | 4.11 | a528d35e8bfc "statx: Add a system call to make enhanced file info available", plus fdfe4a393e9 (generic wire-up), a1016e94cce (ARM), 3209f68b3ca, 47071aee6a1, 1e2f82d1e9d (follow-up fixes) | **Hard.** systemd 258 removed its statx fallback; stat-util uses statx everywhere. 72 files in the core commit, most of them filesystem `getattr` signature changes. |
| NS_GET_NSTYPE | 4.11 | e5ff5ce6e20e "nsfs: Add an ioctl() to return the namespace type" | Soft at boot. Needed for `NetworkNamespacePath=`, `PrivateUsers=` checks and by nsresourced. About 40 lines. |
| TIOCGPTPEER | 4.13 | 54ebbfb16034 "tty: add TIOCGPTPEER ioctl", with c6325179238 and 311fc65c9fb fixes | Soft at boot. Breaks `run0`, `systemd-run -t`, `machinectl shell` and nspawn consoles. |
| SO_PEERGROUPS | 4.13 | 28b5ba2aa0f5 "net: introduce SO_PEERGROUPS getsockopt" | Soft. `getpeergroups()` returns the error; bus and varlink peer credentials lose group information. |
| cgroup2 nsdelegate | 4.13 | 5136f6365ce3 "cgroup: implement nsdelegate mount option" | Not needed with Droidspaces, which mounts cgroup2 without options and systemd then skips its own fatal mount. Needed for a native boot. |
| cgroup2 cpu controller, cgroup.threads, freezer | 4.14 to 5.2 | | Soft, same as on 4.14. |

The 4.14 patch files will not apply to 4.9 unchanged either; `arch/arm/tools/syscall.tbl`
does not exist yet (syscalls live in `arch/arm/kernel/calls.S`), and the pidfd backport
sits at different line numbers. Treat 4.9 as a port of the mainline commits with 4.14 as
the worked example, and budget for statx being the real job. Nothing on 4.9 has been booted.

### Below 4.9

Do not. statx, cgroup namespaces (4.6), ambient capabilities (4.3) and the cgroup2 pids
controller (4.5) pile up, and the pidfd backport does not exist for them.

## The patches and where they come from

Every kernel change is a mainline cherry-pick except the nexthop stub. Take them from the
mainline tag that introduced them, not from a later LTS: the 5.1 to 5.9 commits were
written against code that still looks like 4.x. By 5.15 the same functions had absorbed
clone3, `struct kernel_clone_args`, CLONE_INTO_CGROUP, `pidfd_getfd()`,
`access_override_creds()` and `close_fd_get_file()`, which you would have to strip out
again. Keep the `(cherry picked from commit ...)` trailer so the provenance stays visible.

| Change | Mainline | Kernel | Needed on | Fixes this symptom |
|---|---|---|---|---|
| pidfd: add P_PIDFD to waitid() | 3695eae5fe | 5.4 | 4.9, 4.14, 4.19 | "Failed to spawn executor: Function not implemented" on every unit. glibc's `pidfd_spawn` probes with `waitid(P_PIDFD, INT_MAX)` and wants EBADF. |
| fork: don't check parent_tidptr with CLONE_PIDFD | 9014143bab | 5.3 | 4.9, 4.14 (4.19 never had the check) | EINVAL from clone for callers that do not zero the pidfd slot. glibc zeroes it, so this is hygiene. |
| net: introduce SO_BINDTOIFINDEX sockopt | f5dd3d0c96 | 5.1 | 4.9, 4.14, 4.19 | resolved cannot bind per-interface sockets, the DHCP client cannot bind. |
| statx: add mount ID | fa2fcf4f1d | 5.8 | 4.9 to 5.4, systemd 260+ | PID 1 dies in mount setup: "Failed to determine whether /proc is a mount point". |
| statx: add mount_root | 80340fe360 | 5.8 | same | Same path, EUNATCH on the missing attribute. |
| utimensat: AT_EMPTY_PATH support | 44a3b87444 | 5.8 | same | udev and the tar importer get EINVAL from `futimens_opath()`. |
| vfs: add faccessat2 syscall | c8ffd8bcdd | 5.8 | same | `access_fd()` gets EINVAL from glibc on every chase() with access checks. |
| open: add close_range() | 278a5fbaed | 5.9 | same | Every forked child dies: "Failed to close all file descriptors: Function not implemented". |
| arch: wire-up close_range() | 9b4feb630e | 5.9 | same | Syscall 436 in the tables. |
| rtnetlink: accept nexthop message types and multicast group | original, about 25 lines | 5.3 equivalent | 4.9, 4.14, 4.19 | networkd exits with "Could not set up manager: Invalid argument" before enumerating anything. No DHCP in the container. See [the nexthop section of the requirements page](Requirements.md#nexthop-why-networkd-dies-on-a-kernel-with-31-multicast-groups). |

Not needed on any version: `clone3`. glibc falls back to `clone()` with CLONE_PIDFD when
clone3 returns ENOSYS, and Droidspaces blocks clone3 anyway when sandboxing is off.

## Porting procedure

```bash
# a blobless mainline clone gives you commit messages and diffs without the full tree
git clone --filter=blob:none --no-checkout https://github.com/torvalds/linux mainline
git -C mainline fetch --depth 1 origin tag v5.4 tag v5.8 tag v5.9
# cherry-pick with provenance, from your kernel tree
git fetch ../mainline
git cherry-pick -x 3695eae5fe 9014143bab f5dd3d0c96
```

### Where the conflicts land

From doing this on 4.14 and from the apply checks on 4.9, 4.19 and 5.4. The series in this
repository already have their hunks shaped the way described here, which is why one patch
file fits every 4.14 or 4.19 tree seen so far. Reproduce the idea if you port to another
series.

- **kernel/fork.c, kernel/exit.c, kernel/signal.c.** The Android pidfd backport differs
  from mainline in small ways: `pidfd_to_pid()` in signal.c also accepts a `/proc/<pid>` fd,
  and on 4.14 the parent_tidptr zero check is still there. Keep the backport's shape, add
  `pidfd_pid()` and `P_PIDFD` into it.
- **net/core/sock.c.** Vendor trees edit `sock_setbindtodevice()`: Samsung relaxes the
  `CAP_NET_RAW` check for a not yet bound socket, Google's 4.19.325 has the relaxed
  `sk->sk_bound_dev_if &&` form and 4.19.198 does not, and 4.x has no `sk_prot->rehash()`
  call there. Give `SO_BINDTOIFINDEX` its own locked helper with the mainline capability
  check and leave `SO_BINDTODEVICE` untouched.
- **include/uapi/asm-generic/socket.h.** Put `SO_BINDTOIFINDEX 62` between `SO_PEERGROUPS`
  and `SO_ZEROCOPY`, the three lines every tree shares, with nothing after `SO_ZEROCOPY` in
  the context: Samsung appends KNOX options there in two different styles, Google has
  `SO_TXTIME` there on 4.19. The per-arch copies (alpha, mips, parisc, sparc, xtensa, and on
  4.14 still frv, m32r, mn10300) need the arch-specific values from the mainline commit.
- **Syscall tables.** Add numbers 436 and 439 to `include/uapi/asm-generic/unistd.h`,
  `arch/arm64/include/asm/unistd32.h` (compat, for 32-bit userspace on a 64-bit phone),
  `arch/arm/tools/syscall.tbl` and the x86 tables, and raise `__NR_syscalls` and
  `__NR_compat_syscalls` to 440. 437 and 438 stay unused, the tables are sparse already.
  The rows go right after `pidfd_open` (434). These one-line hunks are the ones most likely
  to reject on a vendor tree that already backported other syscalls (Samsung's Android 13
  and 14 kernels have 435, 436 and 441): add the lines by hand and leave the counts alone
  if they are already 440 or more. Keep the x86 rows in a patch of their own, vendor x86
  tables differ and nobody builds them.
- **fs/open.c.** 4.x has the credential override inline in `sys_faccessat()` (4.14) or
  `do_faccessat()` (4.19). Do not rewrite or re-indent that block: vendors differ in it
  (`non_rcu` arrived in 4.14.139 and 4.19.69, Qualcomm adds `struct vfsmount *mnt` and
  `inode_permission2()` lines for sdcardfs, KernelSU hooks sit above or inside the
  function). Add the flags argument and two wrappers, the flag checks, and
  `if (flags & AT_EACCESS) goto retry;` so the override is skipped and `old_cred` stays
  NULL, then make `out:` conditional on `old_cred`. Write the hunk that changes the function
  head with no leading context, so an `extern` a KernelSU integration puts right above the
  function does not matter.
- **fs/stat.c and uapi/linux/stat.h.** Add only `#include "mount.h"`, anchored on
  `#include <asm/unistd.h>` and the blank line after it. Mainline also adds `internal.h`,
  which some trees already include, and KernelSU trees put an `#include <ksu_hook.h>` right
  there. Append `STATX_ATTR_MOUNT_ROOT` before the closing `#endif` rather than next to
  `STATX_ATTR_VERITY`, which 4.14.113 does not have.
- **include/uapi/linux/fcntl.h.** `AT_REMOVEDIR` has a two-line comment; put the `AT_EACCESS`
  block after it, before `AT_SYMLINK_FOLLOW`, not inside the comment. Getting this wrong
  fails every file that includes fcntl.h.
- **fs/file.c.** 4.14's `__close_fd()` still clears the close-on-exec bit itself; keep that
  line in `pick_file()`. 4.19's no longer does, so there `pick_file()` is the mainline one.
  Mainline's hunk context carries `__close_fd_get_file()` from the io_uring work, which
  neither has.
- **security/selinux/nlmsgtab.c.** Any change to `RTM_MAX` needs matching rows and a moved
  assertion. On 4.14 the assertion moves from `RTM_NEWCACHEREPORT + 3` to
  `RTM_NEWNEXTHOP + 3`, on 4.19 from `RTM_NEWCHAIN + 3` (RTM_NEWCHAIN is 100 to 102, new in
  4.19, so `RTM_NEWNEXTHOP` lands at 104).

### Compile the touched objects first

It saves a link cycle. `sys32.o` is the arm64 compat table; if a syscall number is wrong it
fails here.

```bash
make O=out ARCH=arm64 CC=clang ... kernel/exit.o kernel/fork.o kernel/signal.o kernel/pid.o \
  net/core/sock.o net/core/rtnetlink.o fs/stat.o fs/open.o fs/file.o fs/utimes.o \
  security/selinux/nlmsgtab.o arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

## Not worth doing

- **The new mount API itself.** About 35 core commits and 4600 lines across
  `fs/namespace.c`, `fs/super.c`, the LSM hooks and SELinux, on top of 1700 lines of 4.14
  to 5.0 drift in those same files. Two to four weeks for someone who owns the tree, with
  real regression risk, for a result the seccomp shim already gives. The numbers are on
  [the requirements page](Requirements.md#why-the-mount-api-is-not-backported-instead).
- **Real nexthop objects.** 2000 lines, and systemd only uses them when configured.
- **Per-instance procfs options** for textual hidepid=. Built on fs_context, see above.
- **The cgroup2 cpu controller on 4.14.** Only matters if you want CPU limits inside the
  guest and the host does not hold `cpu` on v1 anyway.

## Caveats

- Only the exynos9820 4.14 tree was booted. Google's 4.14 and 4.19 got apply and compile
  checks with their own series. Seven vendor trees (two more 4.14, four 4.19) got apply
  checks only, see the series READMEs. 4.9 and 5.4 got the feature probe and an apply check
  that showed the 4.14 patch files need re-porting there, nothing more.
- Both tested guests ship a current glibc with `pidfd_spawn`. An older glibc without it
  takes the `posix_spawn` plus `pidfd_open` path, which the same patches cover.
- A full `Image` link was done by the kernel's owner, not here. The compile checks on
  Google's trees cover the touched objects.

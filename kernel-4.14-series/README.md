# systemd 258 to 262 on Android 4.14: the kernel patches

Ten patches. Together they are everything a 4.14 Android kernel that carries the Android R
pidfd backport is missing to run systemd 258 through 262 as a Droidspaces guest. One file
per change, every hunk written so that vendor additions in the same functions do not get in
the way.

Run `tools/probe-kernel.sh <your tree> HEAD` first. If it prints `pidfd_open no`, apply
[`pidfd-backport-4.14/`](../pidfd-backport-4.14/README.md) before this series. If it prints
`yes` for something below, skip that patch. Why systemd needs each one is on the
[requirements page](../Documentation/Requirements.md); mainline hashes and the reasoning
behind the hunk shapes are on the [porting page](../Documentation/Porting.md).

| # | Patch | Mainline | Skip if the probe says | Fixes |
|---|---|---|---|---|
| 1 | `0001-pidfd-add-P_PIDFD-to-waitid.patch` | 3695eae5fe (v5.4) | `waitid_P_PIDFD yes` | Every service spawn fails with ENOSYS. **Required.** |
| 2 | `0002-fork-don-t-check-parent_tidptr-with-CLONE_PIDFD.patch` | 9014143bab (v5.3) | the hunk is already gone | EINVAL from clone for callers that do not zero the pidfd slot. Hygiene. |
| 3 | `0003-net-introduce-SO_BINDTOIFINDEX-sockopt.patch` | f5dd3d0c96 (v5.1) | `SO_BINDTOIFINDEX yes` | resolved and the DHCP client cannot bind. **Required for networkd or resolved.** |
| 4 | `0004-statx-add-mount-ID.patch` | fa2fcf4f1d (v5.8) | `STATX_MNT_ID yes` | PID 1 dies in mount setup. **Required for 260+.** |
| 5 | `0005-statx-add-mount_root.patch` | 80340fe360 (v5.8) | `STATX_ATTR_MOUNT_ROOT yes` | Same path. **Required for 260+.** |
| 6 | `0006-utimensat-AT_EMPTY_PATH-support.patch` | 44a3b87444 (v5.8) | `utimensat_AT_EMPTY_PATH yes` | udev and the tar importer get EINVAL. **Required for 260+.** |
| 7 | `0007-vfs-add-faccessat2-syscall.patch` | c8ffd8bcdd (v5.8) | `faccessat2 yes` | `access_fd()` gets EINVAL on every `chase()`. **Required for 260+.** |
| 8 | `0008-open-add-close_range.patch` | 278a5fbaed (v5.9) | `close_range yes` | Every forked child exits. **Required for 260+.** |
| 9 | `0009-arch-wire-up-close_range.patch` | 9b4feb630e (v5.9) | `close_range yes` | Syscall 436 in the arm, arm64 compat, asm-generic and x86 tables. **Required with 8.** |
| 10 | `0010-rtnetlink-accept-nexthop-message-types-and-multicast.patch` | none, original stub | `nexthop_RTNLGRP yes` | networkd exits before enumerating anything. **Required for DHCP in the container.** |

## Apply

```
git am 00*.patch
```

Build at least these objects before the full image; `sys32.o` is the arm64 compat table and
fails first if a syscall number is wrong:

```
make O=out ARCH=arm64 ... kernel/exit.o kernel/fork.o kernel/signal.o net/core/sock.o \
  fs/stat.o fs/open.o fs/file.o fs/utimes.o net/core/rtnetlink.o security/selinux/nlmsgtab.o \
  arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

If the syscall table one-liners of patches 7 or 9 reject because your tree already has
syscalls after 434, add the rows by hand and leave `__NR_syscalls` and
`__NR_compat_syscalls` alone if they are already 440 or more.

## Where it was applied

All ten, in order, with `git am` or `git apply`, no hand edits:

| Tree | Kernel | pidfd backport | Result |
|---|---|---|---|
| `Kernels-by-ravindu644/samsung_kernel_exynos9820_extremerom` main | 4.14.356 | yes | All ten. Compiled, booted: Fedora 44 (systemd 259.10) and Arch Linux ARM (systemd 262) reach their default target with zero failed units and a DHCP lease, with Droidspaces newer than 7.1.0. |
| `aosp-mirror/kernel_common` `deprecated/android-4.14-stable` | 4.14.336 | yes | All ten. Compiled earlier with the previous layout of the same changes. |
| `Kernels-by-ravindu644/samsung_kernel_SCV41_droidspaces` | 4.14.190 | yes | All ten. |
| `Kernels-by-ravindu644/samsung_kernel_exynos9820_stockrom` `pure-stock` | 4.14.113 | **no**, see `pidfd-backport-4.14/` | All ten, after the pidfd backport. |

The stock tree is the interesting one: Samsung's Android 9 kernel, frozen at 4.14.113, no
pidfd, 398 compat syscalls, no `non_rcu` credential change (4.14.139), its own KernelSU hook
shape. It is the case the hunks were shaped for.

## Deviations from mainline

- Patch 1: `kernel/signal.c` keeps the Android `pidfd_to_pid()` helper, which also accepts a
  `/proc/<pid>` fd, and tries `pidfd_pid()` first.
- Patch 3: `SO_BINDTOIFINDEX` gets its own `sock_setbindtoifindex_locked()` with the
  mainline capability check; the existing `SO_BINDTODEVICE` path, which vendors edit, is
  untouched. The define sits between `SO_PEERGROUPS` and `SO_ZEROCOPY`. Per-arch socket.h
  copies get the mainline values (alpha, frv, ia64, m32r, mips, mn10300, parisc, s390,
  sparc, xtensa).
- Patch 4: only `#include "mount.h"` is added to `fs/stat.c`, not `internal.h`.
- Patch 5: `STATX_ATTR_MOUNT_ROOT` is appended before the closing `#endif`, because 4.14.113
  has no `STATX_ATTR_VERITY` to anchor on.
- Patch 7: `sys_faccessat()` becomes `do_faccessat(dfd, name, mode, flags)` with two
  wrappers. The credential override block is not touched: `AT_EACCESS` skips it with
  `goto retry` and `old_cred` stays NULL, which the `out:` label checks. `AT_EACCESS` is
  added to `fcntl.h` with the upstream comment, before `AT_SYMLINK_FOLLOW`. Only the arm,
  arm64 and x86 tables are wired, like the pidfd backport; 437 and 438 stay unused.
- Patch 8: 4.14's `__close_fd()` still clears the close-on-exec bit itself, so `pick_file()`
  keeps that line. No `CLOSE_RANGE_UNSHARE` or `CLOSE_RANGE_CLOEXEC`; systemd passes 0.
- Patch 10: the SELinux assertion moves from `RTM_NEWCACHEREPORT + 3` to
  `RTM_NEWNEXTHOP + 3`. On an LTO build a wrong value shows up at link time as an undefined
  `__compiletime_assert_NNN`.

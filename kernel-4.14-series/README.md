# The 4.14 series

Ten patches. Together they are everything a 4.14 Android kernel with the Android R pidfd
backport is missing to run systemd 258 through 262 as a Droidspaces guest. Every hunk is
written so that vendor additions in the same functions do not get in the way.

Run `tools/probe-kernel.sh <your tree>` first. If it prints `pidfd_open no`, apply
[`pidfd-backport-4.14/`](../pidfd-backport-4.14/README.md) before this series. If it prints
`yes` for a feature below, skip that patch.

## The patches

Each entry names the mainline commit the patch was taken from, the probe line that says you
already have it, and what goes wrong without it. The full story behind each one is on the
[internals page](../Documentation/Internals.md).

1. `0001-pidfd-add-P_PIDFD-to-waitid.patch`, mainline 3695eae5fe (v5.4). Skip if
   `waitid_P_PIDFD yes`. Without it every service spawn fails with "Function not
   implemented". Required.
2. `0002-fork-don-t-check-parent_tidptr-with-CLONE_PIDFD.patch`, mainline 9014143bab
   (v5.3). Skip if the hunk is already gone. Removes a check the Android backport kept that
   mainline dropped. Hygiene, glibc is not affected either way.
3. `0003-net-introduce-SO_BINDTOIFINDEX-sockopt.patch`, mainline f5dd3d0c96 (v5.1). Skip if
   `SO_BINDTOIFINDEX yes`. Without it resolved and the DHCP client cannot bind, so no DNS
   and no address inside the container. Required for networking.
4. `0004-statx-add-mount-ID.patch`, mainline fa2fcf4f1d (v5.8). Skip if `STATX_MNT_ID yes`.
   Without it systemd 260 and newer die in mount setup before starting anything.
5. `0005-statx-add-mount_root.patch`, mainline 80340fe360 (v5.8). Skip if
   `STATX_ATTR_MOUNT_ROOT yes`. Same failure as patch 4.
6. `0006-utimensat-AT_EMPTY_PATH-support.patch`, mainline 44a3b87444 (v5.8). Skip if
   `utimensat_AT_EMPTY_PATH yes`. Without it udev and the tar importer fail on 260 and newer.
7. `0007-vfs-add-faccessat2-syscall.patch`, mainline c8ffd8bcdd (v5.8). Skip if
   `faccessat2 yes`. Without it most path lookups in systemd 260 and newer fail.
8. `0008-open-add-close_range.patch`, mainline 278a5fbaed (v5.9). Skip if `close_range yes`.
   Without it every process systemd 260 and newer forks exits immediately.
9. `0009-arch-wire-up-close_range.patch`, mainline 9b4feb630e (v5.9). Goes with patch 8.
   Adds syscall 436 to the arm, arm64 compat, asm-generic and x86 tables.
10. `0010-rtnetlink-accept-nexthop-message-types-and-multicast.patch`, original, not a
    backport. Skip if `nexthop_RTNLGRP yes`. Without it networkd exits on startup, so no
    DHCP in the container. Required for networking.

Patches 4 to 9 only matter for systemd 260 and newer. Fedora 44 ships 259, so it boots with
patches 1, 2, 3 and 10 alone; Arch ships 262 and needs all ten.

## Apply

```
git am 00*.patch
```

Build these objects before the full image. `sys32.o` is the arm64 compat syscall table and
is the first thing to fail if a syscall number is wrong:

```
make O=out ARCH=arm64 ... kernel/exit.o kernel/fork.o kernel/signal.o net/core/sock.o \
  fs/stat.o fs/open.o fs/file.o fs/utimes.o net/core/rtnetlink.o security/selinux/nlmsgtab.o \
  arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

If a one-line syscall table hunk in patch 7 or 9 rejects, your tree already has other
syscalls after 434. Add the row by hand and leave `__NR_syscalls` and
`__NR_compat_syscalls` alone if they are already 440 or more.

## Where it was applied

All ten, in order, with `git am`, no hand edits:

- `Kernels-by-ravindu644/samsung_kernel_exynos9820_extremerom`, 4.14.356. Compiled and
  booted with Fedora 44 and Arch Linux ARM, the screenshots in the main README.
- `aosp-mirror/kernel_common`, branch `deprecated/android-4.14-stable`, 4.14.336. Touched
  objects compiled.
- `Kernels-by-ravindu644/samsung_kernel_SCV41_droidspaces`, 4.14.190. Applied.
- `Kernels-by-ravindu644/samsung_kernel_exynos9820_stockrom`, branch `pure-stock`,
  4.14.113. Applied after the pidfd backport. This is Samsung's Android 9 kernel with no
  pidfd, 398 compat syscalls, none of the later credential changes and its own KernelSU hook
  shape. It is the tree the hunks were shaped for.

## Deviations from mainline

- Patch 1 keeps the Android `pidfd_to_pid()` helper in `kernel/signal.c`, which also accepts
  a `/proc/<pid>` fd, and tries the new `pidfd_pid()` first.
- Patch 3 gives `SO_BINDTOIFINDEX` its own `sock_setbindtoifindex_locked()` and leaves the
  `SO_BINDTODEVICE` path, which vendors edit, untouched. The define sits between
  `SO_PEERGROUPS` and `SO_ZEROCOPY`. The per-arch `socket.h` copies get the mainline values.
- Patch 4 adds only `#include "mount.h"` to `fs/stat.c`, not `internal.h`.
- Patch 5 appends `STATX_ATTR_MOUNT_ROOT` before the closing `#endif`, because 4.14.113 has
  no `STATX_ATTR_VERITY` to anchor on.
- Patch 7 turns `sys_faccessat()` into `do_faccessat(dfd, name, mode, flags)` with two
  wrappers and does not touch the credential override block: `AT_EACCESS` jumps past it
  with `goto retry`. Only the arm, arm64 and x86 tables are wired; 437 and 438 stay unused.
- Patch 8 keeps the line in `pick_file()` that clears the close-on-exec bit, which 4.14's
  `__close_fd()` still does itself. No `CLOSE_RANGE_UNSHARE` or `CLOSE_RANGE_CLOEXEC`,
  systemd passes 0.
- Patch 10 moves the SELinux `BUILD_BUG_ON` from `RTM_NEWCACHEREPORT + 3` to
  `RTM_NEWNEXTHOP + 3`. On an LTO build a wrong value shows up at link time as an undefined
  `__compiletime_assert_NNN`.

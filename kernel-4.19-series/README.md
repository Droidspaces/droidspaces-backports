# The 4.19 series

Ten patches against Google's `android-4.19-stable` (4.19.325). Together they are everything
a 4.19 Android kernel is missing to run systemd 258 through 262 as a Droidspaces guest.
Every Android 4.19 kernel already has the Android R pidfd backport, so unlike 4.14 there is
no prerequisite series. The changes are the same as the 4.14 series, ported fresh against
4.19 context.

Run `tools/probe-kernel.sh <your tree>` first. Vendor 4.19 kernels differ in what they
already have. If the probe prints `yes` for a feature below, skip that patch.

## The patches

Each entry names the mainline commit the patch was taken from, the probe line that says you
already have it, and what goes wrong without it. The full story behind each one is on the
[internals page](../Documentation/Internals.md).

1. `0001-pidfd-add-P_PIDFD-to-waitid.patch`, mainline 3695eae5fe (v5.4). Skip if
   `waitid_P_PIDFD yes`. Without it every service spawn fails with "Function not
   implemented". Required.
2. `0002-net-introduce-SO_BINDTOIFINDEX-sockopt.patch`, mainline f5dd3d0c96 (v5.1). Skip if
   `SO_BINDTOIFINDEX yes`. Without it resolved and the DHCP client cannot bind, so no DNS
   and no address inside the container. Required for networking.
3. `0003-statx-add-mount-ID.patch`, mainline fa2fcf4f1d (v5.8). Skip if `STATX_MNT_ID yes`.
   Without it systemd 260 and newer die in mount setup before starting anything.
4. `0004-statx-add-mount_root.patch`, mainline 80340fe360 (v5.8). Skip if
   `STATX_ATTR_MOUNT_ROOT yes`. Same failure as patch 3.
5. `0005-utimensat-AT_EMPTY_PATH-support.patch`, mainline 44a3b87444 (v5.8). Skip if
   `utimensat_AT_EMPTY_PATH yes`. Without it udev and the tar importer fail on 260 and newer.
6. `0006-vfs-add-faccessat2-syscall.patch`, mainline c8ffd8bcdd (v5.8). Skip if
   `faccessat2 yes`. Without it most path lookups in systemd 260 and newer fail.
7. `0007-open-add-close_range.patch`, mainline 278a5fbaed (v5.9). Skip if `close_range yes`.
   Without it every process systemd 260 and newer forks exits immediately.
8. `0008-arch-wire-up-close_range.patch`, mainline 9b4feb630e (v5.9). Goes with patch 7.
   Adds syscall 436 to the arm, arm64 compat and asm-generic tables.
9. `0009-rtnetlink-accept-nexthop-message-types-and-multicast.patch`, original, not a
   backport. Skip if `nexthop_RTNLGRP yes`. Without it networkd exits on startup, so no
   DHCP in the container. Required for networking.
10. `0010-x86-wire-up-close_range-and-faccessat2.patch`, the x86 table rows for 436 and
    439, split off because vendor x86 tables vary and no phone builds them. Only for x86.

Patches 3 to 8 only matter for systemd 260 and newer. The 4.14 series has one more patch,
the `parent_tidptr` fix; the 4.19 backport never had that check, so it is not needed here.

## Apply

```
git am 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch
git am 0006-*.patch 0007-*.patch 0008-*.patch 0009-*.patch
git am 0010-*.patch        # x86 builds only
```

Build these objects before the full image. `sys32.o` is the arm64 compat syscall table and
is the first thing to fail if a syscall number is wrong:

```
make O=out ARCH=arm64 CC=clang ... fs/stat.o fs/open.o fs/file.o fs/utimes.o \
  net/core/sock.o net/core/rtnetlink.o kernel/exit.o kernel/fork.o kernel/signal.o \
  security/selinux/nlmsgtab.o arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

## When the table hunks of patch 6 reject

A tree that already added syscalls after `pidfd_open` (Samsung's Android 13 and 14 kernels
do) rejects the four one-line table hunks because the line after 434 is no longer blank.
Add these four lines by hand, keeping the numbers ascending:

- `arch/arm/tools/syscall.tbl`: `439	common	faccessat2			sys_faccessat2`
- `arch/arm64/include/asm/unistd32.h`: `#define __NR_faccessat2 439` and
  `__SYSCALL(__NR_faccessat2, sys_faccessat2)`
- `include/uapi/asm-generic/unistd.h`: the same two lines
- `arch/arm64/include/asm/unistd.h` and `__NR_syscalls` in asm-generic: leave them if they
  are already 440 or more, otherwise set both to 440

The code hunks of patch 6 are what matter and they applied on every tree tried.

## Where it was applied

- `aosp-mirror/kernel_common`, branch `deprecated/android-4.19-stable`, 4.19.325. All ten.
  Compiled with Ubuntu clang 18.1.3 and `gki_defconfig` (LTO, CFI and shadow call stack
  off, since Ubuntu's clang lacks the CFI ignore list). No errors, no warnings in the changed
  files. The patch files reproduce the compiled tree byte for byte.
- `ravindu644/android_kernel_sm_a135f` (Galaxy A13, Exynos 850), 4.19.198. All ten. This
  tree still has the strict `CAP_NET_RAW` check in `sock_setbindtodevice()` and a KernelSU
  include in `fs/stat.c`; both broke an earlier version of patches 2 and 3.
- `LineageOS/android_kernel_oneplus_sm8250`, 4.19.324. Patches 1 to 9. Patch 10 rejects
  because the tree spells its x86_64 table rows without the `__x64_sys_` prefix.
- `LineageOS/android_kernel_google_redbull` (Pixel 4a 5G and 5), 4.19.325. Same as sm8250.
- `LineageOS/android_kernel_samsung_universal9830` (Galaxy S20), 4.19.325. Already has
  SO_BINDTOIFINDEX, clone3, close_range and epoll_pwait2, so patches 2, 7 and 8 are skipped.
  Patches 1, 3, 4, 5 and 9 apply unchanged. Patch 6 applies except its four table lines, see
  above.

Not boot-tested on a device. The 4.14 series with the same changes was, and 4.19 lacks the
same set of features.

## Deviations from mainline

- Patch 1 keeps the Android `pidfd_to_pid()` helper in `kernel/signal.c`, which also accepts
  a `/proc/<pid>` fd, and tries the new `pidfd_pid()` first. `pidfd_pid()` lands in
  `kernel/fork.c` next to the MEMCG `delayed_free_task()` helpers that 4.19 has and mainline
  did not.
- Patch 2 gives `SO_BINDTOIFINDEX` its own `sock_setbindtoifindex_locked()` and leaves the
  `SO_BINDTODEVICE` path untouched. Google's 4.19.325 and Samsung's 4.19.198 differ in that
  function, so a patch that edits it fits only one of them. The define sits between
  `SO_PEERGROUPS` and `SO_ZEROCOPY`.
- Patch 3 adds only `#include "mount.h"` to `fs/stat.c`, not `internal.h`.
- Patch 4 appends `STATX_ATTR_MOUNT_ROOT` before the closing `#endif`, so it does not depend
  on `STATX_ATTR_VERITY` being there.
- Patch 6 gives `do_faccessat()` the flags argument and two wrappers and does not touch the
  credential override block: `AT_EACCESS` jumps past it with `goto retry`. The duplicate
  `do_faccessat()` declaration in `fs/internal.h` goes, as mainline did.
- Patch 7 leaves out `__close_fd_get_file()`, which mainline's context carried from the
  io_uring work and 4.19 does not have. 4.19's `__close_fd()` no longer clears the
  close-on-exec bit itself, so `pick_file()` is the mainline one. No `CLOSE_RANGE_UNSHARE`
  or `CLOSE_RANGE_CLOEXEC`, systemd passes 0.
- Patches 8 and 10 wire only arm, arm64 and x86, like the Android pidfd backport.
  `__NR_syscalls` and `__NR_compat_syscalls` go from 435 to 440; 437 and 438 stay unused.
- Patch 9 puts `RTM_NEWNEXTHOP` at 104, after `RTM_GETCHAIN` (100 to 102, new in 4.19), and
  moves the SELinux `BUILD_BUG_ON` from `RTM_NEWCHAIN + 3` to `RTM_NEWNEXTHOP + 3`. On an
  LTO build a wrong value shows up at link time as an undefined `__compiletime_assert_NNN`.

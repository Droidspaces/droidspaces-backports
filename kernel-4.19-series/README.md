# systemd 258 to 262 on Android 4.19: the kernel patches

Ten patches against Google's `android-4.19-stable` (4.19.325). Together they are everything
a 4.19 Android kernel is missing to run systemd 258 through 262 as a Droidspaces guest.
Every Android 4.19 kernel has the Android R pidfd backport (4.19 shipped with Android 10,
after it landed), so unlike 4.14 there is no prerequisite series. The 4.14 series needed the
same changes from the same mainline commits; only the contexts differ, so this is a fresh
port, not the 4.14 files re-applied.

Run `tools/probe-kernel.sh <your tree> HEAD` first. Vendor 4.19 kernels differ in what they
already have. Every patch here is independent except 7 and 8, and 6 before 10. Why systemd
needs each one is on the [requirements page](../Documentation/Requirements.md); mainline
hashes and the reasoning behind the hunk shapes are on the
[porting page](../Documentation/Porting.md).

| # | Patch | Mainline | Skip if the probe says | Fixes |
|---|---|---|---|---|
| 1 | `0001-pidfd-add-P_PIDFD-to-waitid.patch` | 3695eae5fe (v5.4) | `waitid_P_PIDFD yes` | Every service spawn fails with ENOSYS. **Required.** |
| 2 | `0002-net-introduce-SO_BINDTOIFINDEX-sockopt.patch` | f5dd3d0c96 (v5.1) | `SO_BINDTOIFINDEX yes` | resolved and the DHCP client cannot bind. **Required for networkd or resolved.** |
| 3 | `0003-statx-add-mount-ID.patch` | fa2fcf4f1d (v5.8) | `STATX_MNT_ID yes` | PID 1 dies in mount setup. **Required for 260+.** |
| 4 | `0004-statx-add-mount_root.patch` | 80340fe360 (v5.8) | `STATX_ATTR_MOUNT_ROOT yes` | Same path. **Required for 260+.** |
| 5 | `0005-utimensat-AT_EMPTY_PATH-support.patch` | 44a3b87444 (v5.8) | `utimensat_AT_EMPTY_PATH yes` | udev and the tar importer get EINVAL. **Required for 260+.** |
| 6 | `0006-vfs-add-faccessat2-syscall.patch` | c8ffd8bcdd (v5.8) | `faccessat2 yes` | `access_fd()` gets EINVAL on every `chase()`. **Required for 260+.** |
| 7 | `0007-open-add-close_range.patch` | 278a5fbaed (v5.9) | `close_range yes` | Every forked child exits. **Required for 260+.** |
| 8 | `0008-arch-wire-up-close_range.patch` | 9b4feb630e (v5.9) | `close_range yes` | Syscall 436 in the arm, arm64 compat and asm-generic tables. **Required with 7.** |
| 9 | `0009-rtnetlink-accept-nexthop-message-types-and-multicast.patch` | none, original stub | `nexthop_RTNLGRP yes` | networkd exits before enumerating anything. **Required for DHCP in the container.** |
| 10 | `0010-x86-wire-up-close_range-and-faccessat2.patch` | rows from 9b4feb630e and c8ffd8bcdd | always, unless you build for x86 | The x86 table rows for 436 and 439. Split off because vendor x86 tables vary and no phone builds them. **Optional.** |

Not in this series: the 4.14 patch 2 ("fork: don't check parent_tidptr with CLONE_PIDFD",
9014143bab). The 4.19 Android backport never had that check, `git cherry-pick` of it is empty.

## Apply

```
git am 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch
git am 0006-*.patch 0007-*.patch 0008-*.patch 0009-*.patch
git am 0010-*.patch        # x86 builds only
```

Then build at least these objects before the full image; `sys32.o` is the arm64 compat
table and fails first if a syscall number is wrong:

```
make O=out ARCH=arm64 CC=clang ... fs/stat.o fs/open.o fs/file.o fs/utimes.o \
  net/core/sock.o net/core/rtnetlink.o kernel/exit.o kernel/fork.o kernel/signal.o \
  security/selinux/nlmsgtab.o arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

## When the table hunks of patch 6 reject

A tree that already added syscalls after `pidfd_open` (Samsung's Android 13 and 14 kernels
do) rejects the four one-line table hunks because the line after 434 is no longer blank.
The fix is four lines by hand, keep the numbers ascending:

- `arch/arm/tools/syscall.tbl`: `439	common	faccessat2			sys_faccessat2`
- `arch/arm64/include/asm/unistd32.h`: `#define __NR_faccessat2 439` and
  `__SYSCALL(__NR_faccessat2, sys_faccessat2)`
- `include/uapi/asm-generic/unistd.h`: the same two lines
- `arch/arm64/include/asm/unistd.h` and the `__NR_syscalls` in asm-generic: leave them if
  they are already 440 or more, otherwise set both to 440

The code hunks of patch 6 (`fs/open.c`, `fs/internal.h`, `include/linux/syscalls.h`,
`include/uapi/linux/fcntl.h`) are what matter and they applied on all four vendor trees.

## What was checked

- Base: `aosp-mirror/kernel_common` branch `deprecated/android-4.19-stable`, 4.19.325. The
  probe showed the same gaps as 4.14: no P_PIDFD, SO_BINDTOIFINDEX, STATX_MNT_ID,
  STATX_ATTR_MOUNT_ROOT, utimensat AT_EMPTY_PATH, faccessat2, close_range, nexthop;
  pidfd_open, CLONE_PIDFD, pidfd polling, statx, PSI, cgroup2 cpu controller and freezer all
  present.
- Compile test on that tree with all ten patches: the thirteen objects above plus
  `kernel/pid.o`, Ubuntu clang 18.1.3, `ARCH=arm64 CC=clang`, `gki_defconfig` with
  `LTO_CLANG`, `CFI_CLANG` and `SHADOW_CALL_STACK` switched off (Ubuntu's clang lacks the
  CFI ignore list). No errors, no warnings in the changed files. Both arm64 syscall tables
  reference `sys_close_range` and `sys_faccessat2`. The ten patch files, applied with
  `git am` to the base, reproduce the compiled tree byte for byte.
- Applied in order on four vendor 4.19 trees (blobless clones, touched files only):

  | Tree | Kernel | Result |
  |---|---|---|
  | `ravindu644/android_kernel_sm_a135f` (Galaxy A13, Exynos 850, Android 11 era) | 4.19.198 | All ten unchanged. This tree still has the strict `CAP_NET_RAW` check in `sock_setbindtodevice()` and a KernelSU include in `fs/stat.c`; both broke the first version of patches 2 and 3. |
  | `LineageOS/android_kernel_oneplus_sm8250` (Qualcomm) lineage-21 | 4.19.324 | 1 to 9 unchanged. 10 rejects: the tree's x86_64 table spells its pidfd_open row without the `__x64_sys_` prefix. |
  | `LineageOS/android_kernel_google_redbull` (Pixel 4a 5G / 5) lineage-22.2 | 4.19.325 | Same as sm8250. |
  | `LineageOS/android_kernel_samsung_universal9830` (Galaxy S20) lineage-24.0 | 4.19.325 | Already has SO_BINDTOIFINDEX (the 5.x `sock_bindtoindex()` form), clone3 (435), close_range with flags (436) and epoll_pwait2 (441), `__NR_compat_syscalls` at 442. So 2, 7 and 8 are skipped. 1, 3, 4, 5 and 9 apply unchanged. 6 applies except its four table one-liners, see above. |

  Qualcomm's `do_faccessat()` has a `struct vfsmount *mnt` and `inode_permission2()` for
  sdcardfs. Patch 6 does not touch those lines, which is why it applies there.
- Not boot-tested. The exynos9820 4.14 series with the same changes was, with systemd 259
  and 262 reaching their default target with zero failed units; 4.19's gaps are the same set.

## Deviations from mainline

- Patch 1: `kernel/signal.c` keeps the Android `pidfd_to_pid()` helper that also accepts a
  `/proc/<pid>` fd and tries `pidfd_pid()` first. `kernel/fork.c` gained `pidfd_pid()` next
  to the MEMCG `delayed_free_task()` helpers that 4.19 has and mainline did not.
- Patch 2: `SO_BINDTOIFINDEX` gets its own `sock_setbindtoifindex_locked()` with the
  mainline capability check; the existing `SO_BINDTODEVICE` path is not touched. Google's
  4.19.325 has the relaxed `sk->sk_bound_dev_if &&` check there and 4.19.198 does not, so a
  patch that edits that function fits only one of them. The define sits between
  `SO_PEERGROUPS` and `SO_ZEROCOPY`.
- Patch 3: only `#include "mount.h"` is added to `fs/stat.c`, not `internal.h`.
- Patch 4: `STATX_ATTR_MOUNT_ROOT` is appended before the closing `#endif`, so it does not
  depend on `STATX_ATTR_VERITY` being there.
- Patch 6: `do_faccessat()` gains the flags argument and two wrappers. The credential
  override block is not touched: `AT_EACCESS` skips it with `goto retry` and `old_cred`
  stays NULL, which the `out:` label checks. The duplicate `do_faccessat()` declaration in
  `fs/internal.h` goes, mainline did the same. `AT_EACCESS` is added to `fcntl.h` with the
  upstream comment, before `AT_SYMLINK_FOLLOW`.
- Patch 7: mainline's hunk context carried `__close_fd_get_file()` from the io_uring work,
  which 4.19 does not have; it is left out. 4.19's `__close_fd()` no longer clears the
  close-on-exec bit itself, so unlike 4.14 `pick_file()` is the mainline one. No
  `CLOSE_RANGE_UNSHARE` or `CLOSE_RANGE_CLOEXEC`; systemd passes 0.
- Patches 8 and 10: only arm, arm64 and x86 are wired, like the Android pidfd backport.
  `__NR_syscalls` and `__NR_compat_syscalls` go from 435 to 440; 437 and 438 stay unused.
- Patch 9: `RTM_NEWNEXTHOP = 104` lands after `RTM_GETCHAIN` (100 to 102, new in 4.19), and
  the SELinux assertion moves from `RTM_NEWCHAIN + 3` to `RTM_NEWNEXTHOP + 3`. Compiled
  without LTO, so the `BUILD_BUG_ON` is checked at compile time here; on an LTO build it
  shows up at link time as an undefined `__compiletime_assert_NNN` if it is wrong.

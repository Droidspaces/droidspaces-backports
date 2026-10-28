# Porting to your own tree

Read this when a patch rejects on your tree, or when your kernel is 4.9 or 5.4, which have
no ready series. Everything here comes from applying the series to Google's common kernels
and seven vendor trees, and from booting one of them.

## Start with the probe

Android kernels carry backports that mainline stable does not, and vendor kernels stop at
whatever stable point the SoC vendor froze on. The version number alone tells you little.

```
tools/probe-kernel.sh <kernel dir>
```

Each `no` is a patch you need, each `yes` a patch you skip. The pidfd lines matter most on
4.14: Google merged its pidfd backport into android-4.14 in mid 2019, and a vendor tree
frozen before that has none of it. Samsung's Android 9 exynos9820 kernel at 4.14.113 is
one such tree, its Android 10 sibling at 4.14.190 is not. Every Android 4.19 kernel has
the backport, because 4.19 shipped after it landed.

## What each kernel version needs

**5.10 and newer.** Nothing. systemd 262 boots unmodified.

**5.4.** Runs systemd 258 and 259 as is. For 260 and newer it needs the three 5.8 and 5.9
pieces: the statx mount id and mount root, `AT_EMPTY_PATH` for utimensat and faccessat2,
and `close_range`. The mount API and nexthops are present, so neither the Droidspaces fix
nor the nexthop patch is involved. The patch files here are written against 4.14 and 4.19
context and do not apply to 5.4; cherry-pick the mainline commits named in the
[4.19 series README](../kernel-4.19-series/README.md) instead.

**4.19.** The [4.19 series](../kernel-4.19-series/README.md), as is. Compile-tested on
Google's tree and applied to four vendor trees, not booted.

**4.14.** The [4.14 series](../kernel-4.14-series/README.md), after the
[pidfd backport](../pidfd-backport-4.14/README.md) if the probe says `pidfd_open no`.
Booted with systemd 259 and 262.

**4.9.** Everything 4.14 needs, plus the 4.11 to 4.13 features that 4.9 lacks:

- statx (4.11, mainline a528d35e8bfc plus the wire-up and fix commits that follow it).
  Hard: systemd 258 removed its statx fallback and uses statx everywhere. The core commit
  touches 72 files, most of them filesystem `getattr` signature changes. This is the real job.
- `NS_GET_NSTYPE` (4.11, e5ff5ce6e20e). About 40 lines. Soft at boot; needed for
  `NetworkNamespacePath=`, `PrivateUsers=` and nsresourced.
- `TIOCGPTPEER` (4.13, 54ebbfb16034 with two fixes). Soft at boot; breaks `run0`,
  `systemd-run -t`, `machinectl shell` and nspawn consoles.
- `SO_PEERGROUPS` (4.13, 28b5ba2aa0f5). Soft; bus and varlink peer credentials lose group
  information.
- cgroup2 `nsdelegate` (4.13, 5136f6365ce3). Not needed under Droidspaces, which mounts
  cgroup2 itself.

The 4.14 patch files do not apply to 4.9 either: `arch/arm/tools/syscall.tbl` does not
exist yet, and the pidfd backport sits at different line numbers. Treat 4.9 as a port of
the mainline commits with 4.14 as the worked example. Nothing on 4.9 has been booted.

**Below 4.9.** Do not. statx, cgroup namespaces, ambient capabilities and the cgroup2 pids
controller pile up, and the pidfd backport does not exist for them.

## Cherry-pick from the right place

Take each change from the mainline tag that introduced it, not from a later LTS. The 5.1 to
5.9 commits were written against code that still looks like 4.x. By 5.15 the same functions
had absorbed clone3, `struct kernel_clone_args`, `CLONE_INTO_CGROUP`, `pidfd_getfd()`,
`access_override_creds()` and `close_fd_get_file()`, all of which you would have to strip
out again. Use `cherry-pick -x` so the provenance stays in the commit message.

```bash
git clone --filter=blob:none --no-checkout https://github.com/torvalds/linux mainline
git -C mainline fetch --depth 1 origin tag v5.4 tag v5.8 tag v5.9
# from your kernel tree
git fetch ../mainline
git cherry-pick -x 3695eae5fe 9014143bab f5dd3d0c96
```

Compile the touched objects before a full build. `sys32.o` is the arm64 compat syscall
table and is the first thing to fail if a syscall number is wrong.

```bash
make O=out ARCH=arm64 CC=clang ... kernel/exit.o kernel/fork.o kernel/signal.o kernel/pid.o \
  net/core/sock.o net/core/rtnetlink.o fs/stat.o fs/open.o fs/file.o fs/utimes.o \
  security/selinux/nlmsgtab.o arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

## Where the conflicts land

The series in this repository already have their hunks shaped as described here, which is
why one patch file fits every 4.14 or 4.19 tree tried so far. If you port by hand, or to
another series, these are the places vendors differ.

- **`kernel/fork.c`, `kernel/exit.c`, `kernel/signal.c`.** The Android pidfd backport is not
  quite mainline: `pidfd_to_pid()` in signal.c also accepts a `/proc/<pid>` fd, and 4.14
  still checks that the parent_tidptr slot is zero. Keep the backport's shape and add
  `pidfd_pid()` and `P_PIDFD` into it.
- **`net/core/sock.c`.** Vendors edit `sock_setbindtodevice()`, and Google's own 4.19
  changed its capability check between stable points. Give `SO_BINDTOIFINDEX` its own
  helper and leave that function alone.
- **`include/uapi/asm-generic/socket.h`.** Put `SO_BINDTOIFINDEX 62` between
  `SO_PEERGROUPS` and `SO_ZEROCOPY`, with nothing after `SO_ZEROCOPY` in the context.
  Samsung appends KNOX options there, Google has `SO_TXTIME` there on 4.19. The per-arch
  copies need the arch-specific values from the mainline commit.
- **Syscall tables.** Add 436 and 439 to `include/uapi/asm-generic/unistd.h`,
  `arch/arm64/include/asm/unistd32.h`, `arch/arm/tools/syscall.tbl` and the x86 tables,
  right after `pidfd_open` (434), and raise `__NR_syscalls` and `__NR_compat_syscalls` to
  440. 437 and 438 stay unused. These one-liners are what rejects on a tree that already
  backported other syscalls, such as Samsung's Android 13 and 14 kernels. Add the rows by
  hand and leave the counts alone if they are already 440 or more. Keep the x86 rows in a
  patch of their own; vendor x86 tables differ and nobody builds them.
- **`fs/open.c`.** The credential override block inside `faccessat` differs between
  vendors: the `non_rcu` change arrived in 4.14.139 and 4.19.69, Qualcomm adds sdcardfs
  lines, KernelSU hooks sit above or inside the function. Do not touch that block. Add the
  flags argument, the flag checks, and `if (flags & AT_EACCESS) goto retry;` so the override
  is skipped with `old_cred` left NULL, then make the `out:` label conditional on
  `old_cred`. Write the hunk that changes the function head with no leading context.
- **`fs/stat.c` and `include/uapi/linux/stat.h`.** Add only `#include "mount.h"`, anchored
  on `#include <asm/unistd.h>` and the blank line after it; KernelSU trees have an include
  right there and some trees already include `internal.h`. Append `STATX_ATTR_MOUNT_ROOT`
  before the closing `#endif`, not next to `STATX_ATTR_VERITY`, which older trees lack.
- **`include/uapi/linux/fcntl.h`.** `AT_REMOVEDIR` has a two-line comment. Put the
  `AT_EACCESS` block after it, before `AT_SYMLINK_FOLLOW`, not inside the comment. Getting
  this wrong fails every file that includes fcntl.h.
- **`fs/file.c`.** 4.14's `__close_fd()` still clears the close-on-exec bit itself, so keep
  that line in `pick_file()`. 4.19's does not. Neither has `__close_fd_get_file()`, which
  mainline's hunk context carries from the io_uring work.
- **`security/selinux/nlmsgtab.c`.** Any change to `RTM_MAX` needs matching rows and a moved
  `BUILD_BUG_ON`, or the build fails at link time under LTO with an undefined
  `__compiletime_assert_NNN`.

## Trees these patches were applied to

Only the first was booted. The rest were apply checks on blobless clones, and the two
Google trees also had their touched objects compiled.

- Samsung exynos9820, `Kernels-by-ravindu644/samsung_kernel_exynos9820_extremerom`,
  4.14.356. Booted with Fedora 44 and Arch Linux ARM.
- Google `android-4.14-stable`, 4.14.336.
- Samsung SCV41, `Kernels-by-ravindu644/samsung_kernel_SCV41_droidspaces`, 4.14.190.
- Samsung exynos9820 stock, `Kernels-by-ravindu644/samsung_kernel_exynos9820_stockrom`,
  4.14.113, after the pidfd backport.
- Google `android-4.19-stable`, 4.19.325.
- Samsung Galaxy A13, `ravindu644/android_kernel_sm_a135f`, 4.19.198.
- OnePlus sm8250, `LineageOS/android_kernel_oneplus_sm8250`, 4.19.324.
- Google Pixel 4a 5G and 5, `LineageOS/android_kernel_google_redbull`, 4.19.325.
- Samsung Galaxy S20, `LineageOS/android_kernel_samsung_universal9830`, 4.19.325, with
  four syscall table lines by hand.

The series READMEs say per tree which patches applied and what, if anything, was skipped.
4.9 and 5.4 only had the probe run and an apply check that showed the patch files need
re-porting there.

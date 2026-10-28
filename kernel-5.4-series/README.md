# The 5.4 series

Seven patches against Google's `android12-5.4` (5.4.302). A 5.4 Android kernel already has
everything systemd 258 and 259 need: the whole pidfd API including `waitid(P_PIDFD)`,
`SO_BINDTOIFINDEX`, nexthops, the new mount API, the cgroup v2 freezer, statx,
`TIOCGPTPEER` and `SO_PEERGROUPS`. Fedora 44 with systemd 259 boots on an unpatched 5.4.
What it lacks is the 5.8 and 5.9 VFS work that systemd 260 made mandatory, so this series
is the 260 half of the 4.14 and 4.19 series on its own: six mainline cherry-picks and the
x86 table rows.

Without it a systemd 260 or newer guest stops in its first second. PID 1 logs "Failed to
determine whether /proc is a mount point: Protocol driver not attached", then "Failed to
mount API filesystems", and Droidspaces reports the container as exited.

Run `tools/probe-kernel.sh <your tree>` first. If it prints `yes` for a feature below,
skip that patch.

## The patches

Each entry names the mainline commit the patch was taken from, the probe line that says you
already have it, and what goes wrong without it. The full story behind each one is on the
[internals page](../Documentation/Internals.md#what-systemd-260-adds).

1. `0001-statx-add-mount-ID.patch`, mainline fa2fcf4f1d (v5.8). Skip if `STATX_MNT_ID yes`.
   Without it mount tracking and `chase()` fail. Required.
2. `0002-statx-add-mount_root.patch`, mainline 80340fe360 (v5.8). Skip if
   `STATX_ATTR_MOUNT_ROOT yes`. Without it PID 1 dies in mount setup, the log lines above.
   Required.
3. `0003-utimensat-AT_EMPTY_PATH-support.patch`, mainline 44a3b87444 (v5.8). Skip if
   `utimensat_AT_EMPTY_PATH yes`. Without it udev and the tar importer fail. Required.
4. `0004-vfs-add-faccessat2-syscall.patch`, mainline c8ffd8bcdd (v5.8). Skip if
   `faccessat2 yes`. Without it most path lookups fail. Required.
5. `0005-open-add-close_range.patch`, mainline 278a5fbaed (v5.9). Skip if `close_range yes`.
   Without it every process systemd forks exits immediately. Required.
6. `0006-arch-wire-up-close_range.patch`, mainline 9b4feb630e (v5.9). Goes with patch 5.
   Adds syscall 436 to the arm, arm64 compat and asm-generic tables.
7. `0007-x86-wire-up-close_range-and-faccessat2.patch`, the x86 table rows for 436 and 439.
   Only for x86 builds such as Cuttlefish. Vendor x86 tables differ, so this is the hunk
   most likely to need a hand edit.

Every patch is independent except that 6 needs 5 and anchors on the row 4 adds, so 4 goes
before 6.

Not needed on 5.4, so not here: the pidfd, `SO_BINDTOIFINDEX` and nexthop patches of the
other series, and the `frozen 0` patch of the 4.9 series, because 5.4 has the real freezer.
`memory_recursiveprot` (5.7) is also absent but only matters for a native boot; Droidspaces
mounts cgroup2 before systemd gets to it, and systemd skips a mount point that is already
mounted.

## Apply

```
git am 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch 0006-*.patch
git am 0007-*.patch        # x86 builds only
```

A Samsung Android 13 or 14 tree that already has `close_range` (the probe says
`close_range yes`; the Galaxy A52s 5G is one, with the 5.11 form and `epoll_pwait2` at 441)
takes patches 1 to 4 and leaves 5 and 6 out. If such a tree also builds x86, take only the
two `faccessat2` lines of patch 7, its `close_range` rows would duplicate the ones there.

Build these objects before the full image. `sys32.o` is the arm64 compat syscall table and
is the first thing to fail if a syscall number is wrong:

```
make O=out ARCH=arm64 CC=clang LD=ld.lld ... fs/stat.o fs/open.o fs/file.o fs/utimes.o \
  arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

## Where it was applied

- `kernel/common`, branch `android12-5.4`, 5.4.302. All seven. Compiled with Ubuntu clang
  18.1.3 and `gki_defconfig` (LTO, CFI and shadow call stack off, since Ubuntu's clang
  lacks the CFI ignore list). No errors, no warnings. Both arm64 tables reference
  `sys_close_range` and `sys_faccessat2`. The patch files reproduce the compiled tree byte
  for byte.
- `chararomandroid/android_kernel_oneplus_sm4350` (OnePlus Nord N200, Snapdragon 480),
  branch lineage-22.2, 5.4.300. All seven unchanged. The six objects compiled with
  `vendor/holi-qgki_defconfig`, same clang and options.
- `bone-machine/android_kernel_samsung_sm7325_a52s_5g` (Galaxy A52s 5G), 5.4.289. Already
  has `close_range` (436, 5.11 form) and `epoll_pwait2` (441), so 5 and 6 are skipped. 1 to
  4 unchanged, with `git am` warning that Samsung's files are mode 100755. 7 applies but
  duplicates the x86 436 rows, see above. The six objects compiled with
  `vendor/a52sxq_kor_single_defconfig`, same clang and options.

Not boot-tested on a device. The same six mainline changes booted systemd 259 and 262 on
the Galaxy S10 as part of the 4.14 series and on the Galaxy A01 as part of the 4.9 series,
and 5.4 lacks nothing else those kernels needed.

## Deviations from mainline

- Patch 4 turns `do_faccessat()` into `do_faccessat(dfd, name, mode, flags)` with two
  wrappers and does not touch the credential override block: `AT_EACCESS` jumps past it
  with `goto retry`, whatever vendor or KernelSU lines sit in the function. The duplicate
  declaration in `fs/internal.h` goes, as mainline did. Same shape as the 4.x series.
- Patch 5: 5.4 has `__close_fd_get_file()` right after `__close_fd()`, where mainline 5.9
  had `do_close_on_exec()`, so the hunk that splits `pick_file()` out of `__close_fd()` and
  adds `__close_range()` is anchored on that. The code is mainline's. No
  `CLOSE_RANGE_UNSHARE` or `CLOSE_RANGE_CLOEXEC`, systemd passes 0.
- Patches 4, 6 and 7 leave `__NR_syscalls` and `__NR_compat_syscalls` alone. Every Android
  5.4 tree already carries `process_madvise` at 440 with both counts at 441, Google
  backported it for the GKI, so the mainline hunks that bump the counts are dropped and 436
  and 439 fill the gap. The rows go before the `clone3` rows, not after them, because that
  is the one spot every 5.4 tree spells the same way: Google's tables jump from 435 to 440,
  LineageOS trees keep the mainline "reserved for" comments in between, and Samsung's have
  their own 436. The table generators sort by number and the `__SYSCALL()` lines in
  `unistd32.h` and `asm-generic/unistd.h` are array designators, so the order in the file
  does not matter, and the "reserved for" comments a LineageOS tree keeps after the new
  rows are harmless.

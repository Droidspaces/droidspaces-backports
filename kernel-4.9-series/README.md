# The 4.9 series

Fifteen patches against Google's `android-4.9-q` (4.9.337). Patches 1 to 9 are everything
a 4.9 Android kernel with the Android R pidfd backport is missing to boot systemd 258
through 262 as a Droidspaces guest. Patch 10 is the x86 and 32-bit ARM table wiring.
Patches 11 to 14 are 4.11 to 4.13 features systemd wants but does not need to boot. Patch
15 is seven lines without which every stop of a login session hangs until its timeout.

4.9 differs from 4.14 and 4.19 in one big way: it has no `statx()` at all, and systemd 258
removed its statx fallback. Patch 4 is that syscall, written for this series rather than
cherry-picked, see below.

Run `tools/probe-kernel.sh <your tree>` first. If it prints `pidfd_open no`, apply
[`pidfd-backport-4.9/`](../pidfd-backport-4.9/README.md) before this series. Google's
`android-4.9-o` and `android-4.9-p` branches and every Android 8 or 9 vendor kernel need
it; Android 10 era trees do not. If the probe prints `yes` for a feature below, skip that
patch.

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
4. `0004-statx-add-a-reduced-statx-syscall-with-mount-ID-and-.patch`, original, on top of
   mainline a528d35e8b (v4.11), fa2fcf4f1d and 80340fe360 (v5.8). Skip if `statx yes` and
   `STATX_MNT_ID yes`. Without it nothing in systemd 258 works, every `statx()` returns
   ENOSYS. Required.
5. `0005-utimensat-AT_EMPTY_PATH-support.patch`, mainline 44a3b87444 (v5.8). Skip if
   `utimensat_AT_EMPTY_PATH yes`. Without it udev and the tar importer fail on 260 and newer.
6. `0006-vfs-add-faccessat2-syscall.patch`, mainline c8ffd8bcdd (v5.8). Skip if
   `faccessat2 yes`. Without it most path lookups in systemd 260 and newer fail.
7. `0007-open-add-close_range.patch`, mainline 278a5fbaed (v5.9). Skip if `close_range yes`.
   Without it every process systemd 260 and newer forks exits immediately.
8. `0008-arch-wire-up-close_range.patch`, mainline 9b4feb630e (v5.9). Goes with patch 7.
   Adds syscall 436 to the asm-generic and arm64 compat tables.
9. `0009-rtnetlink-accept-nexthop-message-types-and-multicast.patch`, original, not a
   backport. Skip if `nexthop_RTNLGRP yes`. Without it networkd exits on startup, so no
   DHCP in the container. Required for networking.
10. `0010-x86-arm-wire-up-statx-close_range-and-faccessat2.patch`, the x86 and
    `arch/arm/kernel/calls.S` rows for statx, 436 and 439. Only for x86 and 32-bit ARM
    builds. Skip it on an arm64 phone tree; some do not even carry these files.
11. `0011-net-introduce-SO_PEERGROUPS-getsockopt.patch`, mainline 28b5ba2aa0 (v4.13). Skip
    if `SO_PEERGROUPS yes`. Without it sd-bus and varlink log an error on every connection
    and fall back to the peer's primary group. Soft.
12. `0012-nsfs-Add-an-ioctl-to-return-the-namespace-type.patch`, mainline e5ff5ce6e2
    (v4.11). Skip if `NS_GET_NSTYPE yes`. Without it `NetworkNamespacePath=`,
    `PrivateUsers=` and nsresourced do not work. Soft.
13. `0013-nsfs-Add-an-ioctl-to-return-owner-UID-of-a-userns.patch`, mainline d95fa3c76a
    (v4.11). Goes with patch 12, completes the v4.11 nsfs ioctl set. Soft.
14. `0014-tty-add-TIOCGPTPEER-ioctl.patch`, mainline 54ebbfb160, c632517923 and 311fc65c9f
    (v4.13) squashed. Skip if `TIOCGPTPEER yes`. Without it `run0`, `systemd-run -t`,
    `machinectl shell` and nspawn consoles fail to open their pty. Soft, not needed to boot.
15. `0015-cgroup-report-frozen-0-in-cgroup.events-on-kernels-w.patch`, original, seven
    lines. Skip if `cgroup_events_frozen yes`, which no 4.9 kernel says. Without it every
    scope unit and `user@.service` hang in stop until their timeout, and a container
    shutdown with a login open ends in SIGKILL. Prints `frozen 0` in `cgroup.events` the way
    kernel 5.2 does. Required for clean stops. The [internals
    page](../Documentation/Internals.md#why-stops-hang-without-the-frozen-key) has the why.

Patches 5 to 8 only matter for systemd 260 and newer. Ordering: 8 needs 7, 6 goes before 8
because it raises the table sizes to 440, 13 after 12, and 11 after 3 because both add a
line at the same spot in `asm-generic/socket.h`. 15 is independent of the rest.

## Apply

```
git am 0001-*.patch 0002-*.patch 0003-*.patch 0004-*.patch 0005-*.patch
git am 0006-*.patch 0007-*.patch 0008-*.patch 0009-*.patch 0015-*.patch
git am 0011-*.patch 0012-*.patch 0013-*.patch 0014-*.patch    # soft, recommended
git am 0010-*.patch        # x86 and 32-bit ARM builds only
```

Build these objects before the full image. `sys32.o` is the arm64 compat syscall table and
is the first thing to fail if a syscall number is wrong:

```
make O=out ARCH=arm64 CC=clang ... fs/stat.o fs/open.o fs/file.o fs/utimes.o fs/nsfs.o \
  fs/devpts/inode.o drivers/tty/pty.o drivers/tty/tty_io.o net/core/sock.o \
  net/core/rtnetlink.o kernel/exit.o kernel/fork.o kernel/signal.o kernel/cgroup.o \
  security/selinux/nlmsgtab.o arch/arm64/kernel/sys.o arch/arm64/kernel/sys32.o
```

## The statx patch

Mainline's statx commit changes the `getattr()` signature of every filesystem, 72 files,
and vendor trees carry filesystems of their own (sdcardfs, esdfs, Samsung's changes) that
would all need the same edit. systemd needs none of that. Patch 4 implements `statx()` in
`fs/stat.c` on top of the `vfs_getattr()` 4.9 already has, about 130 lines, nothing outside
that file except the uapi header and the table rows.

- `STATX_BASIC_STATS`, `STATX_MNT_ID`, `STATX_ATTR_MOUNT_ROOT` and `STATX_ATTR_AUTOMOUNT`
  are reported. atime is dropped from the mask on `MS_NOATIME` filesystems, as mainline does.
- `STATX_BTIME` and the per-filesystem attribute bits (`STATX_ATTR_IMMUTABLE` and friends)
  are reported as unsupported by leaving their mask bits clear. That is what mainline
  reports for a filesystem that does not implement them, and systemd checks the mask before
  using any of them.
- `struct statx`, the `STATX_*` and `STATX_ATTR_*` constants and the `AT_STATX_*` flags are
  v5.8's, so a userspace built against current headers sees the same ABI. `STATX_ATTR_DAX`
  carries the v5.9 value, because v5.8's collided with `STATX_ATTR_MOUNT_ROOT`.
- Wired as 291 in the asm-generic table and 397 in the arm64 compat table. 4.9's `calls.S`
  already reserved 397 for statx.

If your tree already has a real statx and the probe says `statx yes`, skip patch 4 and take
patches 4 and 5 of the [4.14 series](../kernel-4.14-series/README.md), the mount id and
mount root additions, instead.

This is new code, not a cherry-pick. Fedora 44 and Arch Linux ARM have booted on it on the
Galaxy A01 and nothing around file metadata has misbehaved so far. If something does,
`strace -e statx` is the first thing to look at.

## Where it was applied

- `aosp-mirror/kernel_common`, branch `deprecated/android-4.9-q`, 4.9.337. All fifteen.
  Before the series the probe showed pidfd, PSI and `GRND_INSECURE` present and everything
  else absent; after it only the cgroup2 items are still missing, and those are soft. The
  sixteen objects above compiled with Ubuntu clang 18.1.3 and `cuttlefish_defconfig`, no
  errors, no warnings. The patch files reproduce the compiled tree byte for byte.
- `Kernels-by-ravindu644/samsung_kernel_a015f` (Galaxy A01, SDM439), 4.9.227. Patches 1 to
  9 and 11 to 15 unchanged. Patch 10 rejects: the tree has no `arch/arm/kernel/calls.S` and
  its 32-bit ARM headers are Samsung's own, and the tree only builds arm64, so it is not
  needed. Compiled and booted with Fedora 44 (systemd 259) and Arch Linux ARM (systemd
  262), the screenshots in the main README: zero failed units, a DHCP lease from networkd,
  resolved answering, console login working. The only kernel-related log lines are the
  expected ones, the BPF device controller and bpf-firewall failing to attach with E2BIG and
  the baseline warning. The first boot showed the stop hang that patch 15 fixes; with it,
  stopping the container with a root login open stops the session scope and
  `user@0.service` at once and Arch runs its shutdown sequence through to "Powering off".
  This tree has KernelSU hooks in `fs/open.c` and `fs/stat.c` and KNOX socket options after
  `SO_COOKIE`, which is what the hunks were shaped around.
- `aosp-mirror/kernel_common`, branch `deprecated/android-4.9-p-release`, 4.9.118, Android
  9, no pidfd. All fifteen unchanged after the pidfd backport. The objects above plus
  `kernel/pid.o` and `fs/proc/base.o` compiled with `defconfig`.
- `aosp-mirror/kernel_common`, branch `deprecated/android-4.9-p`, 4.9.299, no pidfd. All
  fifteen unchanged after the pidfd backport. Applied only.

## Deviations from mainline

- Patch 1: 4.9 has no `kernel_waitid()`, so the `P_PIDFD` case goes into
  `SYSCALL_DEFINE5(waitid)` itself. `kernel/signal.c` keeps the Android `pidfd_to_pid()`
  helper, which also accepts a `/proc/<pid>` fd, and tries the new `pidfd_pid()` first.
- Patch 3 gives `SO_BINDTOIFINDEX` its own `sock_setbindtoifindex_locked()` and leaves
  `sock_setbindtodevice()` untouched. In the per-arch headers the define goes after
  `SO_COOKIE` (57), the last option 4.9 has. In asm-generic it goes before `SO_CNX_ADVICE`
  so the hunk does not depend on what a vendor appends after `SO_COOKIE`; Samsung adds KNOX
  options there. Patch 11 places `SO_PEERGROUPS` the same way. The avr32, powerpc, frv,
  m32r and mn10300 headers, which 4.9 still has, are included.
- Patch 6 turns `sys_faccessat()` into `do_faccessat(dfd, name, mode, flags)` with two
  wrappers and does not touch the credential override block: `AT_EACCESS` jumps past it
  with `goto retry` and `old_cred` stays NULL. That keeps the patch independent of the
  `non_rcu` block, which arrived in 4.9.190 and which Google's 4.9.337 does not carry but
  Samsung's 4.9.227 does, and of any KernelSU hook above it. Same shape as the 4.14 and
  4.19 series.
- Patch 7 keeps the line in `pick_file()` that clears the close-on-exec bit, which 4.9's
  `__close_fd()` still does itself. No `CLOSE_RANGE_UNSHARE` or `CLOSE_RANGE_CLOEXEC`,
  systemd passes 0.
- Patches 6 and 8 take `__NR_syscalls` and `__NR_compat_syscalls` from 435 to 440; 437 and
  438 stay unused. Only the asm-generic and arm64 compat tables, like the pidfd backport.
  x86 and `calls.S` are patch 10.
- Patch 9: 4.9's group enum ends at `RTNLGRP_NSID` (28), so `RTNLGRP_MPLS_NETCONF`,
  `RTNLGRP_IPV4_MROUTE_R` and `RTNLGRP_IPV6_MROUTE_R` are added as names only, so that
  `RTNLGRP_NEXTHOP` gets its real number, 32. `RTM_NEWNEXTHOP` is 104, after `RTM_GETSTATS`
  (94), with 96 to 103 left undefined. The SELinux `BUILD_BUG_ON` moves from
  `RTM_NEWSTATS + 3` to `RTM_NEWNEXTHOP + 3`. 4.9's `rtnl_register()` takes a `calcit`
  function pointer where 4.14's takes flags.
- Patch 14 squashes the three mainline TIOCGPTPEER commits into their v4.13 end state, so
  the `struct path` caching of the first one, which the third one reverted, never appears.
  4.9's `tty_ioctl()` switch has no `default:` case, so the new case goes after
  `TIOCSSERIAL`. The define sits after `TIOCVHANGUP` rather than after `TIOCGEXCL` because
  Samsung appends `TIOCPMGET` and friends after `TIOCGEXCL`.

Left out on purpose: `MS_NOSYMFOLLOW`, `memory_recursiveprot`, `GRND_INSECURE` (systemd
retries without the flag; Google's 4.9.337 has it, Samsung's 4.9.227 does not), `STATX_BTIME`,
and the cgroup2 cpu controller, `cgroup.threads`, freezer and `nsdelegate`, which are all
soft on a Droidspaces guest. Patch 15 reports the one line of the freezer's interface that
systemd cannot do without and leaves `cgroup.freeze` absent, so `systemctl freeze` still
says the freezer is unsupported instead of pretending. The new mount API is handled by Droidspaces, see the
[internals page](../Documentation/Internals.md#the-new-mount-api).

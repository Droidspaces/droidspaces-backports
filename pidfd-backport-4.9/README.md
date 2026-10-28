# pidfd backport for 4.9 kernels that never got it

Thirteen patches, Google's own Android R backport of the pidfd work, taken from the
`android-4.9-q` history. Google's `android-4.9-o` and `android-4.9-p` branches and every
Android 8 or 9 vendor 4.9 kernel lack them, and without them nothing in
[`kernel-4.9-series/`](../kernel-4.9-series/README.md) helps: systemd 258 needs
`pidfd_open()`, `CLONE_PIDFD` and pidfd polling before anything else comes into play.
Android 10 era trees, Google's `android-4.9-q` and Samsung's 4.9.2xx kernels, already have
all of this.

Run `tools/probe-kernel.sh <your tree>` first. If it prints `pidfd_open yes`, you do not
need this directory.

## The patches

Google's commit hash first, then the upstream commit it came from in brackets where the
subject was changed.

1. `BACKPORT: signal: add pidfd_send_signal() syscall`, cf9f829523c (3eb39f47934f, 5.1)
2. `UPSTREAM: signal: don't silently convert SI_USER signals to non-current pidfd`, f511d49e01d (5.1)
3. `UPSTREAM: signal: use fdget() since we don't allow O_PATH`, 68defbc4c84 (5.1)
4. `BACKPORT: clone: add CLONE_PIDFD`, 0e020c19bbb (b3e583825266, 5.2)
5. `BACKPORT: signal: support CLONE_PIDFD with pidfd_send_signal`, b3ae59851fb (5.2)
6. `BACKPORT: fork: do not release lock that wasn't taken`, 3941f126e3e (5.2)
7. `UPSTREAM: signal: improve comments`, ac937bb3fbd (5.2)
8. `UPSTREAM: pidfd: add polling support`, af1070fbf2c (b53b0b9d9a61, 5.3)
9. `BACKPORT: pid: add pidfd_open()`, 304e7f38acb (32fcb426ec00, 5.3)
10. `BACKPORT: arch: wire-up pidfd_open()`, fe84579bf46 (5.3)
11. `UPSTREAM: pidfd: fix a poll race when setting exit_state`, 42cafda2961 (b191d6491be6, 5.3)
12. `BACKPORT: arch: add pidfd and io_uring syscalls everywhere`, a3660e0f1ae (5.1)
13. `ANDROID: arch: fix backported syscall numbers`, ed3eafebbda, no upstream. Fills
    `arch/arm/kernel/calls.S` rows 397 to 433 with `sys_ni_syscall` so 424 and 434 land
    on the right rows. It assumes `calls.S` ends at `sys_pkey_free` (396); check that on a
    32-bit ARM tree.

Google's series has a fourteenth commit, `UPSTREAM: Make anon_inodes unconditional`, which
edits twenty Kconfig files. It is left out: `CONFIG_ANON_INODES` is selected by `EPOLL`,
`SIGNALFD`, `TIMERFD` and `EVENTFD`, which every Android kernel has, so the option is already
on. If your `.config` somehow lacks it, enable it, do not port that commit.

## Two flavours of patches 4 and 6

Between 4.9.118 and 4.9.2xx a stable backport moved the `p->set_child_tid` and
`p->clear_child_tid` assignments in `copy_process()` from just after `alloc_pid()` to the
top of the function, and changed the comment after the `cgroup_can_fork()` error path.
Google's patches 4 and 6 are written against the later layout.

- A tree at 4.9.2xx uses the thirteen files in this directory as they are.
- A tree at 4.9.1xx uses `alt-4.9.1xx/0004-*.patch` and `alt-4.9.1xx/0006-*.patch` in
  place of the top-level 4 and 6. Same code, two hunks placed by hand. If `git am` of the
  top-level patch 4 rejects on `kernel/fork.c`, that is the sign you need these.

## Apply

```
git am 0001-*.patch 0002-*.patch 0003-*.patch
git am 0004-*.patch || { git am --abort; git am alt-4.9.1xx/0004-*.patch; }
git am 0005-*.patch
git am 0006-*.patch || { git am --abort; git am alt-4.9.1xx/0006-*.patch; }
git am 0007-*.patch 0008-*.patch 0009-*.patch 0010-*.patch 0011-*.patch 0012-*.patch 0013-*.patch
```

Then continue with [`kernel-4.9-series/`](../kernel-4.9-series/README.md). That series
expects this backport's syscall table layout: 424 and 434 present, `__NR_syscalls` and
`__NR_compat_syscalls` at 435, which is also what every Android 10 or newer 4.9 kernel has.

## What was checked

- `aosp-mirror/kernel_common`, branch `deprecated/android-4.9-p`, 4.9.299. All thirteen
  applied unchanged, then all fourteen of the 4.9 series applied unchanged. Applied only.
- `aosp-mirror/kernel_common`, branch `deprecated/android-4.9-p-release`, 4.9.118. Eleven
  applied unchanged, 4 and 6 in the `alt-4.9.1xx/` form, then all fourteen of the 4.9 series
  applied unchanged. Compiled on that tree with `defconfig` and Ubuntu clang 18:
  `kernel/exit.o`, `kernel/fork.o`, `kernel/signal.o`, `kernel/pid.o`, `fs/proc/base.o`,
  the arm64 syscall tables and the objects the series README lists, no errors and no new
  warnings.
- After the thirteen, the probe reports `pidfd_send_signal`, `CLONE_PIDFD`, `pidfd_open` and
  `pidfd_poll` as present.

Not boot-tested. The code is Google's backport unmodified apart from where two hunks sit,
and the same code has shipped in every Android 10 4.9 kernel.

## For other old trees

A vendor 4.9.1xx kernel will differ in `kernel/fork.c` and `kernel/signal.c` in its own
ways. The commits are small and the originals are in Google's history (`git log
--grep=pidfd deprecated/android-4.9-q` in `aosp-mirror/kernel_common`), so if one rejects,
read Google's version of the hunk and place it by hand. None of them changes logic that
vendors touch.

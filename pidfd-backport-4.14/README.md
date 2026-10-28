# pidfd backport for 4.14 kernels that never got it

Twelve patches, Google's own Android R backport of the pidfd work, taken from the
`android-4.14-stable` history and re-applied to a Samsung stock 4.14.113 tree. Any Android
4.14 kernel from before mid 2019 (Android 9 and early Android 10 vendor trees) lacks them,
and without them nothing else in this repository helps: systemd 258 needs `pidfd_open()`,
`CLONE_PIDFD` and pidfd polling before anything else comes into play.

Run `tools/probe-kernel.sh <your tree> HEAD` first. If it prints `pidfd_open yes`, you do
not need this directory.

## The patches

Google's commit hash first, then the upstream commit it came from in brackets where the
subject was changed.

1. `BACKPORT: signal: add pidfd_send_signal() syscall`, c8b9b2c5cca3 (3eb39f47934f, 5.1)
2. `UPSTREAM: signal: don't silently convert SI_USER signals to non-current pidfd`, b0358816aa3a (5.1)
3. `UPSTREAM: signal: use fdget() since we don't allow O_PATH`, 5cc6eff44967 (5.1)
4. `BACKPORT: clone: add CLONE_PIDFD`, 4f3acf41da49 (b3e583825266, 5.2)
5. `BACKPORT: signal: support CLONE_PIDFD with pidfd_send_signal`, f2ab0796400a (5.2)
6. `UPSTREAM: fork: do not release lock that wasn't taken`, 379fed52b72d (5.2)
7. `UPSTREAM: signal: improve comments`, b8a24925e8e6 (5.2)
8. `UPSTREAM: pidfd: add polling support`, e44e96da7f04 (b53b0b9d9a61, 5.3)
9. `BACKPORT: pid: add pidfd_open()`, f944e462eaa7 (32fcb426ec00, 5.3)
10. `BACKPORT: arch: wire-up pidfd_open()`, 708c2df8cdb7 (5.3)
11. `UPSTREAM: pidfd: fix a poll race when setting exit_state`, 98e47d9a1a3a (b191d6491be6, 5.3)
12. `BACKPORT: arch: add pidfd and io_uring syscalls everywhere`, a48da8903efa (5.1)

Google's series has a thirteenth commit, `UPSTREAM: Make anon_inodes unconditional`, which
edits twenty Kconfig files. It is left out: `CONFIG_ANON_INODES` is selected by `EPOLL`,
`SIGNALFD`, `TIMERFD` and `EVENTFD`, which every Android kernel has, so the option is already
on. If your `.config` somehow lacks it, enable it, do not port that commit.

## Apply

```
git am 00*.patch
```

Then continue with [`kernel-4.14-series/`](../kernel-4.14-series/README.md). That series
expects this backport's syscall table layout: 424 and 434 present, `__NR_syscalls` and
`__NR_compat_syscalls` at 435, which is also what every Android R or newer 4.14 kernel has.

## What was checked

Applied with `git am` to `Kernels-by-ravindu644/samsung_kernel_exynos9820_stockrom`,
branch `pure-stock`, Samsung's 4.14.113 with no pidfd at all. Eleven of the twelve went in
unchanged. Patch 4 needed one hunk placed by hand, a pure insertion of `pidfd_release()`,
`pidfd_fops` and `pidfd_create()` whose surrounding context in `kernel/fork.c` differs in
Samsung's tree. The exported patch file carries the fixed hunk, so it applies cleanly now.
After the twelve, the probe reports `pidfd_send_signal`, `CLONE_PIDFD`, `pidfd_open` and
`pidfd_poll` as present, and all ten patches of the 4.14 series apply unchanged.

Not compiled: the stock tree was only checked out in part. The code is Google's backport
unmodified apart from where the one hunk sits, and the same code has shipped in every
Android R 4.14 kernel, so a compile problem would be a Samsung-specific include or symbol,
which the first build will show.

Samsung's `include/uapi/linux/sched.h`, `kernel/fork.c` and `include/linux/pid.h` are mode
0755 in that tree. `git am` keeps the mode and only warns.

## For other old trees

A 4.14.1xx vendor kernel from a different OEM will differ in `kernel/fork.c` and
`kernel/signal.c` in its own ways. The twelve commits are small and the originals are in
Google's history (`git log --grep=pidfd deprecated/android-4.14-stable` in
`aosp-mirror/kernel_common`), so if one rejects, read Google's version of the hunk and place
it by hand. None of them changes logic that vendors touch.

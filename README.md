# Modern systemd on old Android kernels

Kernel patches that let a [Droidspaces](https://github.com/ravindu644/Droidspaces-OSS)
container boot systemd 258 through 262 on an Android 4.9, 4.14 or 4.19 kernel.

systemd 258 raised its kernel baseline to 5.4 and 260 raised it to 5.10. The fallbacks that
let it run on anything older are gone from the code. The patches here put back the handful
of kernel features it now assumes. They are small, and most are mainline cherry-picks.

If you do not want to touch the kernel, pin systemd to 257. It still boots on 4.x.

## Result

A Samsung Galaxy S10 on kernel 4.14.356, on 2026-10-28, and a Samsung Galaxy A01 on kernel
4.9.227, on 2026-10-28 and 2026-10-29, with the patches applied:

<table>
  <tr>
    <td width="50%" align="center"><img src="Documentation/resources/fedora-4.14.png" width="100%"><br>Galaxy S10, 4.14.356: Fedora 44, systemd 259</td>
    <td width="50%" align="center"><img src="Documentation/resources/arch-4.14.png" width="100%"><br>Galaxy S10, 4.14.356: Arch Linux ARM, systemd 262</td>
  </tr>
  <tr>
    <td width="50%" align="center"><img src="Documentation/resources/fedora-4.9.png" width="100%"><br>Galaxy A01, 4.9.227: Fedora 44, systemd 259</td>
    <td width="50%" align="center"><img src="Documentation/resources/arch-4.9.png" width="100%"><br>Galaxy A01, 4.9.227: Arch Linux ARM, systemd 262</td>
  </tr>
</table>

All four guests boot to their login prompt with zero failed units, get an address from
networkd, resolve DNS through resolved, and report nothing worse than `Tainted: old-kernel`.

## What you need

- A 4.9, 4.14 or 4.19 Android kernel tree you can build. For 5.4 or a vendor tree that
  rejects a patch, read the [porting page](Documentation/Porting.md).
- Droidspaces newer than 7.1.0. Part of the fix lives in the runtime, not the kernel, and
  landed in [commit 3132cc93](https://github.com/ravindu644/Droidspaces-OSS/commit/3132cc9311c5e2582a9c47c40476925b3a9a2c57).
  Until the next release, use the [CI build](https://t.me/DroidspacesCI/990). Run
  `droidspaces check` and look for the `New mount API` row to confirm your build has it.

## How to use it

1. Run the probe against your kernel tree. It prints yes or no for every feature these
   patches add, and works on a blobless clone.

   ```
   tools/probe-kernel.sh <kernel dir>
   ```

2. If the probe says `pidfd_open no`, apply the pidfd backport for your kernel first:
   [`pidfd-backport-4.9/`](pidfd-backport-4.9/README.md) or
   [`pidfd-backport-4.14/`](pidfd-backport-4.14/README.md). Vendor trees frozen before
   mid 2019 need it; newer ones and every 4.19 do not.
3. Apply the series for your kernel: [`kernel-4.9-series/`](kernel-4.9-series/README.md),
   [`kernel-4.14-series/`](kernel-4.14-series/README.md) or
   [`kernel-4.19-series/`](kernel-4.19-series/README.md). Skip any patch whose feature
   the probe already reports as `yes`.
4. Build, boot a systemd guest, and if anything is red, look it up on the
   [boot log page](Documentation/Boot-Log.md).

## Documentation

- [Porting](Documentation/Porting.md): applying the patches to a tree that is not one of
  the tested ones, including 5.4, and which trees were tested.
- [Boot log](Documentation/Boot-Log.md): what each error line means and which patch fixes it.
- [Internals](Documentation/Internals.md): why systemd needs each of these features, read
  out of its source, and why the new mount API is handled in Droidspaces rather than in the
  kernel. Reference material, not needed to use the patches.

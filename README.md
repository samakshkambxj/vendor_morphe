# vendor/morphe — Morphe-patched YouTube vendor tree

Root-replacement prebuilts for custom ROMs (A16 / A17, AOSP/Lineage based).
Ships **stock** YouTube + YT Music as system apps and bind-mounts **patched**
(Morphe) builds over them at boot. One YouTube icon, stock package names,
works with real Play Services or system microG — no parallel packages, no
per-app MicroG login.

Morphe is used because it is the actively maintained patch set in 2026
(tracks latest YouTube releases); its root modules already exclude the
GmsCore-spoof patch, which is exactly what a system-level install wants.

## How it works

```
common/product/app/YouTube/com.google.android.youtube.apk   stock, installed as a product app
common/product/app/YTMusic/com.google.android.apps.youtube.music.apk
common/product/etc/rv/YTPatched.apk                         patched, shipped as inert data
common/product/etc/rv/YTMusicPatched.apk
common/product/etc/init/init.morphe.rc                      boot swap, gated by property
```

At install/scan time PackageManager sees valid stock signatures. At
`boot_completed`, `init.morphe.rc` bind-mounts the patched file over the
stock path, so the running code is patched. The mount is gated by
`persist.sys.morphe.mod` (default `true`) — flipping it off + rebooting
restores pure stock behavior. `MorpheManager` (privileged toggle app) owns
the switch.

Because the swap happens below PackageManager, the 100MB+ patched blobs
need no re-signing or dexpreopt at build time — they are installed with
the `ETC` class byte-for-byte.

## Layout

```
vendor/morphe/
  products/morphe.mk        # entry point — inherit this
  products/board.mk         # BoardConfig hook — include this
  common/Android.mk         # 6 prebuilt modules (stock/patched/libdir x YT/Music)
  common/common-vendor.mk   # PRODUCT_PACKAGES + Soong namespace
  common/product/...        # APKs, libs, init script (see above)
  morphemanager/            # privileged toggle app (platform-signed)
  sepolicy/                 # init mount rules, app domain, property type
  vendorsetup.sh            # envsetup hook: merge parts, extract libs, fetch patched
  update.sh                 # patched downloader + stock stager
  split-apk.sh              # chunk APKs for git before committing
```

## 1. Add to your manifest

```xml
<project name="samakshkambxj/vendor_morphe" path="vendor/morphe" remote="github" revision="main" />
```

## 2. Populate APKs

Patched builds auto-fetch on envsetup (see §3). Stock builds are **optional**:
supply them only if you want mount mode (toggleable stock/patched); on
stockless ROMs skip this entirely and the patched builds install directly
as the apps (see §4).

When supplying stock, use APKs matching the patched base version: pull
`base.apk` from a device (`adb pull $(adb shell pm path
com.google.android.youtube | cut -d: -f2)`) or grab the same base version
(arm64 nodpi, plain APK, not `.apkm` bundles) from APKMirror. E.g. for
patched bases YouTube `v21.20.405` / YT Music `v9.20.53`, those exact
versions are on APKMirror.

```bash
cd vendor/morphe
./update.sh --stock-yt /path/to/youtube-base.apk --stock-music /path/to/music-base.apk
# patched-only refresh:  ./update.sh
# local modules (e.g. from a builder checkout's build.sh run, per app or both):
#   ./update.sh --yt-module /path/to/yt-module.zip --music-module /path/to/music-module.zip
# pin builder release:   TAG=<tag> ./update.sh
# alternate builder:     REPO=<owner/repo> ./update.sh
```

Verify with `aapt dump badging` — staged patched APKs must report
`com.google.android.youtube` / `com.google.android.apps.youtube.music`.
`app.morphe.*` means the non-root asset was grabbed by mistake.

Committing refreshed APKs (they exceed GitHub's 100MB limit as whole files):

```bash
./split-apk.sh   # creates *.apk.part* chunks, which ARE committed
```

## 3. Automatic setup on envsetup

`vendorsetup.sh` is sourced automatically by `source build/envsetup.sh`
and prepares the prebuilts before every build:

1. merges `*.apk.part*` chunks back into full APKs,
2. extracts `arm64` native libs from the stock APKs into `.../lib/arm64`,
3. downloads patched builds via `update.sh` when missing.

```bash
source build/envsetup.sh   # all of the above happens automatically
```

Controls:

```bash
MORPHE_NO_AUTO_FETCH=1 source build/envsetup.sh  # offline / CI: skip downloads
MORPHE_FETCH=1 source build/envsetup.sh          # force re-download of patched builds
```

## 4. Inherit in your tree

```make
# device/<oem>/<codename>/<codename>.mk (or ROM common config):
$(call inherit-product, vendor/morphe/products/morphe.mk)

# BoardConfig.mk:
include vendor/morphe/products/board.mk
```

Then build as usual.

### Stock vs stockless (automatic, per app)

The tree detects each stock APK with `wildcard` at build time — no flags:

- **Stock mode** (stock APK supplied): stock installs as the signature
  source, patched ships under `/product/etc/rv/...`, init bind-mounts it
  over stock at boot, MorpheManager toggles it. Output also includes the
  init script and arm64 lib dir for that app.
- **Stockless mode** (no stock APK — vanilla ROMs with no Google apps):
  the patched build installs directly as
  `/product/app/YouTube/com.google.android.youtube.apk` (same for Music);
  PackageManager extracts its libs itself. No mount, no init script, no
  lib staging for that app. The MorpheManager toggle has nothing to swap
  in this mode (documented in-app behavior is mount-only).

You can mix: stock YouTube + stockless Music, or vice versa.

Caveats for stockless:

- **Do not flash a GApps package that also ships YouTube/Music**
  afterwards: same package name, different (builder vs Google) signature
  → install conflict. Use a GApps variant without those apps, or supply
  stock bases and run stock mode instead.
- **Login needs GMS or system microG.** A vanilla ROM with neither gives
  a logged-out experience (same as any root install on degoogled ROMs) —
  add system microG (`com.google.android.gms`) if you want sign-in.

## 5. ROM-side requirements (do these or the mod misbehaves)

- **Detach from Play Store updates.** Play will otherwise replace the
  mounted patched build with stock on first update. Detach
  `com.google.android.youtube` and
  `com.google.android.apps.youtube.music` — via your ROM's update-block
  mechanism (framework-side package denylist) or a user-side detach module
  (Magisk/KernelSU). Without this, the mod silently unpatches itself.
- **GMS.** GApps builds work as-is. Vanilla builds need system microG
  (`com.google.android.gms` as a system app). The per-app MicroG build
  (`app.revanced.android.gms`) is for non-root parallel installs and is
  NOT used here.
- **Optional Settings toggle.** `persist.sys.morphe.mod` is world-readable
  by design (`morphe_prop`), so a Settings switch can flip the mod the
  same way MorpheManager does (reboot to apply).

## 6. Updating

Patched bases move fast — old patches break on new YouTube within weeks.
Per ROM release cycle: re-run `./update.sh` (with matching stock APKs),
`./split-apk.sh`, commit, rebuild. Pin `TAG` in CI for reproducible builds.

## Files

- `products/morphe.mk` — packages, sepolicy include, per-app init copy, default property
- `common/Android.mk` — stock/patched/libdir modules, or patched-direct install when stock absent
- `common/product/etc/init/init.morphe.{yt,music}.rc` — boot bind-mounts, one per app, property-gated
- `sepolicy/` — `morphe_init` (mount), `morphe_app` (manager domain), `morphe_prop`
- `morphemanager/` — toggle UI + reboot, platform priv-app + whitelist

# vendor/morphe — Morphe-patched YouTube vendor tree

Root-replacement prebuilts for custom ROMs (A16 / A17, AOSP/Lineage based).
Ships **stock** YouTube, YT Music and Reddit as system apps and bind-mounts
**patched** (Morphe) builds over them at boot. One YouTube icon, stock package names,
works with real Play Services or system microG — no parallel packages, no
per-app MicroG login.

Morphe is used because it is the actively maintained patch set in 2026
(tracks latest YouTube releases); its root modules already exclude the
GmsCore-spoof patch, which is exactly what a system-level install wants.

## How it works

```
common/product/app/YouTube/com.google.android.youtube.apk   stock, installed as a product app
common/product/app/YTMusic/com.google.android.apps.youtube.music.apk
common/product/app/Reddit/com.reddit.frontpage.apk
common/product/etc/rv/YTPatched.apk                         patched, shipped as inert data
common/product/etc/rv/YTMusicPatched.apk
common/product/etc/rv/RedditPatched.apk
common/product/etc/init/init.morphe.{yt,music,reddit}.rc    boot swap, gated by property
```

At install/scan time PackageManager sees valid stock signatures. At
`boot_completed`, the per-app init scripts bind-mount the patched files
over the stock paths, so the running code is patched. Each mount is gated
by its own property (`persist.sys.morphe.{yt,music,reddit}`, default
`true`) — flipping one off + rebooting restores pure stock behavior for
that app. `MorpheManager` (privileged manager app) owns the per-app
switches, shows live mount state, warns when a store update shadows a
patched build, and runs an update center tracking new builder bases.

Because the swap happens below PackageManager, the 100MB+ patched blobs
need no re-signing or dexpreopt at build time — they are installed with
the `ETC` class byte-for-byte.

## Layout

```
vendor/morphe/
  products/morphe.mk        # entry point — inherit this
  products/board.mk         # BoardConfig hook — include this
  common/Android.mk         # stock/patched/libdir modules per app (stock/stockless aware)
  common/common-vendor.mk   # PRODUCT_PACKAGES + Soong namespace + include flags
  common/product/...        # APKs, libs, init scripts (see above)
  morphemanager/            # privileged manager app: toggles, live state, update center
  sepolicy/                 # init mount rules, app domain (+net), property type
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
./update.sh --stock-yt /path/to/youtube-base.apk --stock-music /path/to/music-base.apk --stock-reddit /path/to/reddit-base.apk
# patched-only refresh:  ./update.sh
# local modules (e.g. from a builder checkout's build.sh run, per app or all):
#   ./update.sh --yt-module /path/to/yt-module.zip --music-module /path/to/music-module.zip --reddit-module /path/to/reddit-module.zip
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

`vendorsetup.sh` is sourced automatically by `source build/envsetup.sh`.
On first source it asks which apps to include (one prompt each, Enter
accepts the default); the choice is saved to gitignored `.apps.conf`,
exported so the make flags pick it up, and printed on every source:

```bash
source build/envsetup.sh   # ask once, then merge/libs/fetch automatically
```

After the choice it prepares the prebuilts before every build: merges
`*.apk.part*` chunks back into full APKs, extracts `arm64` native libs
into `.../lib/arm64`, and downloads patched builds via `update.sh` when
missing (skipping apps you excluded).

Controls:

```bash
MORPHE_NO_AUTO_FETCH=1 source build/envsetup.sh  # offline / CI: skip downloads
MORPHE_FETCH=1 source build/envsetup.sh          # force re-download of patched builds
MORPHE_ASK=1 source build/envsetup.sh            # re-ask the app selection
rm vendor/morphe/.apps.conf                      # same effect, forgets the choice
MORPHE_INCLUDE_REDDIT=false source build/envsetup.sh  # one-shot override, no file
```

## 4. Inherit in your tree

```make
# device/<oem>/<codename>/<codename>.mk (or ROM common config):
$(call inherit-product, vendor/morphe/products/morphe.mk)

# BoardConfig.mk:
include vendor/morphe/products/board.mk
```

Then build as usual.

To drop the MorpheManager app entirely, set this in your device/ROM
makefile *before* the inherit line:

```make
MORPHE_INCLUDE_MANAGER := false
$(call inherit-product, vendor/morphe/products/morphe.mk)
```

To drop the patched apps entirely (YouTube, YT Music, their lib dirs and
init scripts — e.g. a vanilla build flavor without them) while keeping the
tree inherited:

```make
MORPHE_INCLUDE_APPS := false
$(call inherit-product, vendor/morphe/products/morphe.mk)
```

Both flags default to on and are independent; set either or both before
the inherit line.

Per-app switches (effective inclusion is master `MORPHE_INCLUDE_APPS` AND
the per-app flag) — drop any single app the same way:

```make
MORPHE_INCLUDE_YOUTUBE := false
MORPHE_INCLUDE_MUSIC := false
MORPHE_INCLUDE_REDDIT := false
$(call inherit-product, vendor/morphe/products/morphe.mk)
```

Mirror the same names as environment when sourcing envsetup so it skips
fetching/warning about excluded apps:

```bash
MORPHE_INCLUDE_REDDIT=false source build/envsetup.sh
```

### Stock vs stockless (automatic, per app)

The tree detects each stock APK with `wildcard` at build time — no flags:

- **Stock mode** (stock APK supplied): stock installs as the signature
  source, patched ships under `/product/etc/rv/...`, init bind-mounts it
  over stock at boot, MorpheManager toggles it. Output also includes the
  init script and arm64 lib dir for that app.
- **Stockless mode** (no stock APK — vanilla ROMs with no Google apps):
  the patched build installs directly as
  `/product/app/YouTube/com.google.android.youtube.apk` (same for Music
  and Reddit), with its native lib set staged alongside in `lib/arm64`
  (module APKs ship Deflated libs with extraction disabled, so the tree
  materializes them — otherwise startup dies with `UnsatisfiedLinkError`).
  No mount, no init script for that app. In this mode the manager's
  toggles lock on with an explanatory note (there is no stock build to
  restore); its update center and override detection still work.

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

- **Detach from Play Store updates.** In stock mode Play can replace the
  mounted patched build with stock on first update (the update shadows the
  system app, silently disabling the mod). Detach
  `com.google.android.youtube`,
  `com.google.android.apps.youtube.music` and `com.reddit.frontpage` — via
  your ROM's update-block mechanism (framework-side package denylist) or a
  user-side detach module (Magisk/KernelSU). MorpheManager also watches for
  this and notifies when a store build shadows a patched one. (Stockless
  builds are builder-signed, so Play updates fail loudly instead — still
  detach to avoid the noise.)
- **GMS.** GApps builds work as-is. Vanilla builds need system microG
  (`com.google.android.gms` as a system app). The per-app MicroG build
  (`app.revanced.android.gms`) is for non-root parallel installs and is
  NOT used here.
- **Optional Settings toggle.** `persist.sys.morphe.{yt,music,reddit}` are
  world-readable by design (`morphe_prop`), so Settings switches can flip
  them the same way MorpheManager does (reboot to apply). This tree can
  install such a screen for you — see §7.

## 6. Updating

Patched bases move fast — old patches break on new YouTube within weeks.
Per ROM release cycle: re-run `./update.sh` (with matching stock APKs),
`./split-apk.sh`, commit, rebuild. Pin `TAG` in CI for reproducible builds.

On-device, MorpheManager's Updates tab tracks the same builder releases:
daily auto-check (JobScheduler, toggleable) with notifications on new
bases, manual check, installed-vs-latest per app, and one-tap module-zip
downloads into Downloads. Note the boundary: the app can fetch but cannot
apply — the system image is read-only, so getting a new base onto the
device still means a ROM rebuild (or flashing the downloaded module zip
with root). The manager needs `INTERNET` (auto-granted) and asks for
notification permission on first use.

## 7. Optional: Morphe screen inside ROM Settings

`settings-patch/` carries a Settings fragment (one switch per property)
plus an auto-apply script. On `source build/envsetup.sh` you are asked
once whether to install it into `packages/apps/Settings` (top-level
entry + screen); afterwards it stays silent. Controls:

```bash
cd vendor/morphe/settings-patch
./apply-settings-patch.sh            # status + prompt
./apply-settings-patch.sh --apply    # no prompt
./apply-settings-patch.sh --check    # exit 0 = installed
./apply-settings-patch.sh --revert   # remove again
MORPHE_SETTINGS_AUTO=1 source build/envsetup.sh    # apply without asking
MORPHE_NO_SETTINGS_PATCH=1 source build/envsetup.sh # never ask
```

Notes: the fragment writes the toggle props, which needs
`set_prop(system_app, morphe_prop)` — already in this tree's sepolicy.
Settings search indexing is one manual line: `--find-search` locates the
registry file and shows the exact call shape to mirror (registry call
shapes differ per tree, so the script shows instead of guessing).

## Files

- `products/morphe.mk` — packages, sepolicy include, per-app init copy, default properties, include flags
- `common/Android.mk` — stock/patched/libdir modules per app, stock/stockless aware
- `common/product/etc/init/init.morphe.{yt,music,reddit}.rc` — boot bind-mounts, one per app, property-gated
- `sepolicy/` — `morphe_init` (mount), `morphe_app` (manager domain + net), `morphe_prop` (3 toggle props)
- `morphemanager/` — M3E manager app (per-app toggles, live mount state, override alerts, update center with changelog + per-app ignore + setup status), platform priv-app + whitelist
- `settings-patch/` — ROM Settings fragment + screen XML + auto-apply script (prompted on envsetup)

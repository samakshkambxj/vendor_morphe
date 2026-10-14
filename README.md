<!-- Copyright (C) 2026 Samaksh Kamboj. SPDX-License-Identifier: Apache-2.0 -->
# vendor/morphe — patched YouTube, Music & Reddit, baked into your ROM

Morphe-patched **YouTube**, **YT Music** and **Reddit** as first-class ROM
citizens: one icon each, stock package names, no root needed on device, no
parallel packages, no per-app MicroG login. You pick the apps once, the
tree handles fetching, mounting, toggling, updating and Settings
integration.

## Features

**Patched apps, system-level**
- YouTube, YT Music and Reddit with Morphe patches (ad blocking,
  background play, SponsorBlock, premium unlocks, Reddit mods) installed
  as product apps under their stock package names.
- No rooted device required — the ROM itself is the privileged installer.
- Works with real Play Services or system microG for login; logged-out
  playback needs neither.

**Two install modes, automatic per app**
- *Stock mode* (stock base supplied): valid Google signatures at
  install time, patched builds bind-mounted over them at boot, fully
  toggleable back to stock.
- *Stockless mode* (no stock base — vanilla ROMs): patched builds install
  directly, with their native lib sets staged alongside (module APKs ship
  compressed, unextractable libs — without this YouTube dies on launch).
- Mix freely: stock YouTube + stockless Music, any combination.

**App selection, your way**
- Interactive picker on first `source build/envsetup.sh` ( Enter accepts
  defaults), saved to gitignored `.apps.conf`, printed on every source.
- `MORPHE_ASK=1` re-asks; `MORPHE_INCLUDE_{YOUTUBE,MUSIC,REDDIT}=false`
  one-shot overrides; `MORPHE_INCLUDE_APPS=false` drops everything;
  explicit `device.mk` assignments always win.

**Zero-friction fetching**
- `vendorsetup.sh` runs on every envsetup: merges git-friendly
  `.apk.part*` chunks, extracts `arm64` libs (stock first, patched
  fallback), downloads missing patched builds automatically.
- `update.sh` resolves the newest builder release *holding all needed
  modules* (tag rotation aware), stages the true patched build (never the
  bundled stock copy), verifies package names, stages stock bases and
  local `--*-module` builds alike.
- `split-apk.sh` chunks refreshed APKs for committing; never commit full
  binaries.

**MorpheManager app (Material3 Expressive)**
- Per-app toggles bound to `persist.sys.morphe.{yt,music,reddit}`
  (reboot to apply), with the switch locked and explained in
  direct-install mode where there is nothing to restore.
- Live state per app: active / pending-reboot / stock / missing /
  Play-shadowed, from PackageManager + `/proc/mounts`.
- Play-override detection: boot + package-replaced watcher warns when a
  store update shadows a patched build.
- Update center: daily auto-check (toggleable) with notifications, manual
  check, installed-vs-latest per app, release-notes card, per-app ignore,
  one-tap module downloads. It fetches but cannot apply (read-only
  system) — new bases land via ROM rebuild.
- Setup-status card (GMS readiness, detach reminder), dynamic launcher
  icon (red while any mod is on, muted when all stock), reboot helper.
- Privileged platform app with its own sepolicy domain; opt out with
  `MORPHE_INCLUDE_MANAGER := false`.

**ROM Settings integration (optional)**
- Ships a Settings fragment (one switch per property) plus an auto-apply
  script offered once on envsetup (`[y/N]`, `MORPHE_SETTINGS_AUTO=1` /
  `MORPHE_NO_SETTINGS_PATCH=1`, `--check`/`--apply`/`--revert`/`--refresh`,
  stale copies self-heal on every source).
- Auto-discovers the search-registry file and shows the exact line to add
  (registry call shapes differ per tree, so that one line stays manual).

**Hygiene built in**
- Sepolicy: init mount rules, `morphe_app` domain (coredomain-labeled for
  treble checks), `morphe_prop` type shared with Settings'
  `system_app` writers.
- Never breaks envsetup: every failure degrades to a warning; offline CI
  via `MORPHE_NO_AUTO_FETCH=1`.

## Quick start

```xml
<!-- ROM manifest -->
<project name="samakshkambxj/vendor_morphe" path="vendor/morphe" remote="github" revision="main" />
```

```bash
source build/envsetup.sh   # pick apps, auto-fetch does the rest
```

```make
# device makefile:
$(call inherit-product, vendor/morphe/products/morphe.mk)
# BoardConfig.mk:
include vendor/morphe/products/board.mk
```

Build as usual. First source asks which apps to include; later sources
just print the selection.

## App selection & flags

| Flag | Default | Set where | Effect |
|---|---|---|---|
| `MORPHE_INCLUDE_APPS` | `true` | makefile, before inherit | Master switch for all patched apps |
| `MORPHE_INCLUDE_YOUTUBE` / `_MUSIC` / `_REDDIT` | `true` | makefile or env | Per-app switch (ANDed with master) |
| `MORPHE_INCLUDE_MANAGER` | `true` | makefile, before inherit | Manager app on/off |
| `MORPHE_ASK=1` | — | envsetup env | Re-ask the app picker |
| `MORPHE_FETCH=1` | — | envsetup env | Force re-download of patched builds |
| `MORPHE_NO_AUTO_FETCH=1` | — | envsetup env | Offline: skip downloads |
| `MORPHE_SETTINGS_AUTO=1` / `MORPHE_NO_SETTINGS_PATCH=1` | — | envsetup env | Auto-apply / never ask Settings patch |

Env exports feed the make flags (environment beats `?=` defaults), so
`MORPHE_INCLUDE_REDDIT=false source build/envsetup.sh` just works with no
makefile edit.

## Install modes (automatic, per app)

Detected per app with `wildcard` — no flags needed.

- **Stock** (stock APK supplied via `./update.sh --stock-*`): signature
  source + patched blob under `/product/etc/rv/` + boot bind-mount +
  toggle + lib dir.
- **Stockless** (no stock APK): patched installs directly as
  `/product/app/<App>/…`, libs staged in `lib/arm64`, no mount/init for
  that app. Manager toggles lock on with an explanatory note.

Stock APKs can't be auto-downloaded (redistribution): pull `base.apk`
from a device or grab the matching base (arm64, plain APK, not `.apkm`)
from APKMirror.

## MorpheManager

Lives in `system_ext` as a privileged platform app (`com.android.morphe`).
See Features above for the full tour. Needs `INTERNET` (auto-granted);
asks for notification permission once for update alerts.

## ROM Settings integration

```bash
cd vendor/morphe/settings-patch
./apply-settings-patch.sh            # status + prompt
./apply-settings-patch.sh --apply    # no prompt
./apply-settings-patch.sh --check    # exit 0 = installed
./apply-settings-patch.sh --refresh  # refresh stale copies only
./apply-settings-patch.sh --revert   # remove again
./apply-settings-patch.sh --find-search  # locate the search registry
```

Puts a top-level *Morphe* entry in Settings. The fragment writes the
toggle props (`set_prop(system_app, morphe_prop)` included in our
sepolicy).

## Updating

Bases move fast — refresh per ROM release cycle:

```bash
cd vendor/morphe
./update.sh            # or TAG=<tag> / REPO=<owner/repo> / --*-module zips
./split-apk.sh         # chunk for git
# commit, rebuild. Pin TAG in CI for reproducible builds.
```

On-device, the manager's Updates tab tracks the same releases and can
download module zips, but applying needs a rebuild (or root-flashing the
zip).

## Requirements & caveats

- **Detach from Play Store updates** in stock mode (update shadows the
  mount and silently unpatches; stockless builds fail loudly instead).
  Detach all three packages via your ROM mechanism or a user-side module.
  The manager watches and warns regardless.
- **No GApps-with-YouTube over stockless builds**: same package, foreign
  signature → install conflict. Use GApps variants without those apps.
- **Login on vanilla** needs GMS or system microG; otherwise logged-out.

## Repo layout

```
vendor/morphe/
  products/morphe.mk        # entry point — inherit this
  products/board.mk         # BoardConfig hook — include this
  common/Android.mk         # stock/patched/libdir modules, mode-aware
  common/common-vendor.mk   # packages + namespaces + include flags
  common/product/...        # APKs, libs, per-app init scripts
  morphemanager/            # M3E manager app + whitelist
  settings-patch/           # Settings fragment + auto-apply script
  vendorsetup.sh            # picker + merge/libs/fetch + Settings offer
  update.sh / split-apk.sh  # fetch/stage + chunk-for-git tooling
  sepolicy/                 # morphe_init, morphe_app, morphe_prop
```

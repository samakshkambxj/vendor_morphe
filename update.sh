#!/bin/bash
# update.sh — stage patched + stock APKs for this vendor tree.
#
# Patched builds come from ROOT module zips (stock package names com.google.*,
# meant to replace stock apps). Two ways to supply them:
#   1. Downloaded automatically from a module builder's GitHub releases
#      (default). The builder rotates tag names across daily runs and the
#      newest release doesn't always carry every app, so the newest
#      release holding all still-needed modules is auto-selected.
#   2. Locally-built module zips, e.g. produced by a builder checkout's
#      build.sh run — pass them via flags and the download is skipped
#      for that app.
# (Release "APK" assets are NON-ROOT builds with custom packages + GmsCore
# spoof — wrong variant for this tree.) The largest APK in each module is
# staged as common/product/etc/rv/{YTPatched,YTMusicPatched,RedditPatched}.apk.
#
# Stock builds: cannot be auto-downloaded (redistribution) and OPTIONAL.
# Omit them on stockless ROMs (no Google apps in-tree): the patched build
# then installs directly as the app instead of mounting over stock.
#
# Usage:
#   ./update.sh                                                  # patched only (latest)
#   ./update.sh --stock-yt /path/to/base.apk --stock-music /path/to/base.apk
#   ./update.sh --yt-module /path/to/yt-module.zip --music-module /path/to/music-module.zip
#   ./update.sh --reddit-module /path/to/reddit-module.zip
#   REPO=<builder> ./update.sh                                   # alternate module builder
#   TAG=<release-tag> ./update.sh                               # pin a builder release
#   STOCK_YT=/path STOCK_MUSIC=/path STOCK_REDDIT=/path YT_MOD=/path MUSIC_MOD=/path REDDIT_MOD=/path ./update.sh  # env form
#
# After refreshing APKs for commit: ./split-apk.sh (vendorsetup.sh merges on envsetup).

set -euo pipefail

REPO="${REPO:-j-hc/revanced-magisk-module}"
VENDOR_DIR="$(cd "$(dirname "$0")" && pwd)"
YT_OUT="$VENDOR_DIR/common/product/etc/rv/YTPatched.apk"
MUSIC_OUT="$VENDOR_DIR/common/product/etc/rv/YTMusicPatched.apk"
REDDIT_OUT="$VENDOR_DIR/common/product/etc/rv/RedditPatched.apk"
YT_STOCK="$VENDOR_DIR/common/product/app/YouTube/com.google.android.youtube.apk"
MUSIC_STOCK="$VENDOR_DIR/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk"
REDDIT_STOCK="$VENDOR_DIR/common/product/app/Reddit/com.reddit.frontpage.apk"
mkdir -p "$(dirname "$YT_OUT")" "$(dirname "$YT_STOCK")" "$(dirname "$MUSIC_STOCK")" "$(dirname "$REDDIT_STOCK")"

STOCK_YT="${STOCK_YT:-}"
STOCK_MUSIC="${STOCK_MUSIC:-}"
STOCK_REDDIT="${STOCK_REDDIT:-}"
YT_MOD="${YT_MOD:-}"
MUSIC_MOD="${MUSIC_MOD:-}"
REDDIT_MOD="${REDDIT_MOD:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --stock-yt) STOCK_YT="${2:-}"; shift 2 ;;
        --stock-music) STOCK_MUSIC="${2:-}"; shift 2 ;;
        --stock-reddit) STOCK_REDDIT="${2:-}"; shift 2 ;;
        --yt-module) YT_MOD="${2:-}"; shift 2 ;;
        --music-module) MUSIC_MOD="${2:-}"; shift 2 ;;
        --reddit-module) REDDIT_MOD="${2:-}"; shift 2 ;;
        --help|-h)
            sed -n '2,/^$/p' "$0"
            echo "Full usage: see header comments."
            exit 0 ;;
        *) echo "Unknown arg: $1 (try --help)"; exit 1 ;;
    esac
done

if [ -n "$STOCK_YT" ]; then
    echo "[*] Staging stock YouTube: $STOCK_YT"
    cp -f "$STOCK_YT" "$YT_STOCK"
fi
if [ -n "$STOCK_MUSIC" ]; then
    echo "[*] Staging stock YT Music: $STOCK_MUSIC"
    cp -f "$STOCK_MUSIC" "$MUSIC_STOCK"
fi
if [ -n "$STOCK_REDDIT" ]; then
    echo "[*] Staging stock Reddit: $STOCK_REDDIT"
    cp -f "$STOCK_REDDIT" "$REDDIT_STOCK"
fi

# Stage the PATCHED APK out of a module zip. Module layout: the mountable
# patched build lives at the zip root (base.apk); stock/ holds the pristine
# stock base for the module's version management. Never stage by largest
# file: stock is bigger, and a largest-file rule once shipped stock YouTube
# as "patched" (launched → died on UnsatisfiedLinkError). Fails loudly when
# no non-stock APK exists.
_stage_apk() {
    python3 -c "
import zipfile, sys
zip_path, out_path = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(zip_path)
apks = [(i.filename, i.file_size) for i in z.infolist()
        if i.filename.endswith('.apk') and 'stock' not in i.filename.lower()]
print(zip_path, apks)
if not apks:
    sys.exit('no PATCHED apk (outside stock/) found in ' + zip_path)
biggest = max(apks, key=lambda x: x[1])[0]
print('staging:', biggest)
with z.open(biggest) as src, open(out_path, 'wb') as dst:
    dst.write(src.read())
" "$1" "$2"
}

# Stage the native lib set out of a module zip's STOCK apk into the tree
# lib dir. The patched build carries zero .so files and resolves them from
# beside the installed app at runtime, so without this the app dies at
# startup with UnsatisfiedLinkError. Stock is version-identical to the base
# the patch set was built against — exactly the right set.
_stage_libs() {
    # $1 = module zip, $2 = dest lib/arm64 dir
    python3 -c "
import zipfile, sys, os, io
zip_path, dest = sys.argv[1], sys.argv[2]
z = zipfile.ZipFile(zip_path)
stock = [(i.filename, i.file_size) for i in z.infolist()
         if i.filename.endswith('.apk') and 'stock' in i.filename.lower()]
print(zip_path, 'stock candidates:', stock)
if not stock:
    sys.exit('no stock apk found in ' + zip_path)
src = max(stock, key=lambda x: x[1])[0]
print('lib source:', src)
inner = zipfile.ZipFile(io.BytesIO(z.read(src)))
names = [i.filename for i in inner.infolist()
         if i.filename.startswith('lib/arm64-v8a/') and i.filename.endswith('.so')]
print('arm64 libs:', len(names))
if not names:
    sys.exit('no arm64 libs in ' + src)
# Wipe first: a base update may drop libs, and stale .so files must not ship.
import shutil
shutil.rmtree(dest, ignore_errors=True)
os.makedirs(dest, exist_ok=True)
for n in names:
    out = os.path.join(dest, n.split('/')[-1])
    with inner.open(n) as s, open(out, 'wb') as d:
        d.write(s.read())
open(os.path.join(os.path.dirname(dest), 'placeholder.txt'), 'w').close()
" "$1" "$2"
}

NEED_DL_YT=1
NEED_DL_MUSIC=1
NEED_DL_REDDIT=1

if [ -n "$YT_MOD" ]; then
    echo "[*] Staging patched YouTube from local module: $YT_MOD"
    _stage_apk "$YT_MOD" "$YT_OUT"
    _stage_libs "$YT_MOD" "$VENDOR_DIR/common/product/app/YouTube/lib/arm64"
    NEED_DL_YT=0
fi
if [ -n "$MUSIC_MOD" ]; then
    echo "[*] Staging patched YT Music from local module: $MUSIC_MOD"
    _stage_apk "$MUSIC_MOD" "$MUSIC_OUT"
    _stage_libs "$MUSIC_MOD" "$VENDOR_DIR/common/product/app/YTMusic/lib/arm64"
    NEED_DL_MUSIC=0
fi
if [ -n "$REDDIT_MOD" ]; then
    echo "[*] Staging patched Reddit from local module: $REDDIT_MOD"
    _stage_apk "$REDDIT_MOD" "$REDDIT_OUT"
    _stage_libs "$REDDIT_MOD" "$VENDOR_DIR/common/product/app/Reddit/lib/arm64"
    NEED_DL_REDDIT=0
fi

if [ "$NEED_DL_YT" -eq 1 ] || [ "$NEED_DL_MUSIC" -eq 1 ] || [ "$NEED_DL_REDDIT" -eq 1 ]; then
    WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/morphe-update.XXXXXX")"
    trap 'rm -rf "$WORKDIR"' EXIT

    _pick_urls() {
        # $1 = one release's JSON. Sets *_ZIP_URL (empty if absent).
        YT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'youtube-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        # Prefer arm64, fall back to whatever arch the release carries.
        MUSIC_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'music-morphe-module-' | grep 'arm64' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        if [ -z "$MUSIC_ZIP_URL" ]; then
            MUSIC_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'music-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        fi
        REDDIT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'reddit-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
    }

    _have_needed() {
        # True when every still-to-download app already has a URL resolved.
        { [ "$NEED_DL_YT" -eq 0 ] || [ -n "$YT_ZIP_URL" ]; } && \
        { [ "$NEED_DL_MUSIC" -eq 0 ] || [ -n "$MUSIC_ZIP_URL" ]; } && \
        { [ "$NEED_DL_REDDIT" -eq 0 ] || [ -n "$REDDIT_ZIP_URL" ]; }
    }

    YT_ZIP_URL=""
    MUSIC_ZIP_URL=""
    REDDIT_ZIP_URL=""
    if [ -n "${TAG:-}" ]; then
        echo "[*] Using pinned tag: $TAG"
        TAG_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$TAG")"
        _pick_urls "$TAG_JSON"
        _have_needed || { echo "[!] Tag $TAG lacks the needed module(s): https://github.com/$REPO/releases/tag/$TAG"; exit 1; }
    else
        # This builder rotates a pool of tag names across daily runs and the
        # newest release doesn't always carry every app, so scan newest-first
        # for the first release holding everything still needed.
        echo "[*] Scanning recent releases of $REPO ..."
        RELEASES_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases?per_page=10")"
        for t in $(printf '%s\n' "$RELEASES_JSON" | grep '"tag_name"' | cut -d'"' -f4); do
            TAG_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$t")"
            _pick_urls "$TAG_JSON"
            if _have_needed; then
                TAG="$t"
                break
            fi
        done
        [ -n "${TAG:-}" ] || { echo "[!] No recent release of $REPO holds the needed module(s)."; exit 1; }
        echo "[*] Selected tag: $TAG"
    fi

    if [ "$NEED_DL_YT" -eq 1 ]; then
        echo "[*] Downloading: $YT_ZIP_URL"
        curl -fL -o "$WORKDIR/yt.zip" "$YT_ZIP_URL"
        _stage_apk "$WORKDIR/yt.zip" "$YT_OUT"
        _stage_libs "$WORKDIR/yt.zip" "$VENDOR_DIR/common/product/app/YouTube/lib/arm64"
    fi
    if [ "$NEED_DL_MUSIC" -eq 1 ]; then
        echo "[*] Downloading: $MUSIC_ZIP_URL"
        curl -fL -o "$WORKDIR/music.zip" "$MUSIC_ZIP_URL"
        _stage_apk "$WORKDIR/music.zip" "$MUSIC_OUT"
        _stage_libs "$WORKDIR/music.zip" "$VENDOR_DIR/common/product/app/YTMusic/lib/arm64"
    fi
    if [ "$NEED_DL_REDDIT" -eq 1 ]; then
        echo "[*] Downloading: $REDDIT_ZIP_URL"
        curl -fL -o "$WORKDIR/reddit.zip" "$REDDIT_ZIP_URL"
        _stage_apk "$WORKDIR/reddit.zip" "$REDDIT_OUT"
        _stage_libs "$WORKDIR/reddit.zip" "$VENDOR_DIR/common/product/app/Reddit/lib/arm64"
    fi
fi

echo "[*] Verifying package names (needs aapt) ..."
if command -v aapt >/dev/null 2>&1; then
    [ -s "$YT_OUT" ] && aapt dump badging "$YT_OUT" | head -n1
    [ -s "$MUSIC_OUT" ] && aapt dump badging "$MUSIC_OUT" | head -n1
    [ -s "$REDDIT_OUT" ] && aapt dump badging "$REDDIT_OUT" | head -n1
    echo "[*] Expected: com.google.android.youtube + com.google.android.apps.youtube.music + com.reddit.frontpage"
    echo "[*] app.morphe.* here means the NON-ROOT asset was grabbed — re-run, modules only."
else
    echo "    (aapt not found, skipping check — verify before building)"
fi

ls -lh "$YT_OUT" "$MUSIC_OUT" "$REDDIT_OUT"
echo "[*] Stock APKs: $([ -s "$YT_STOCK" ] && echo present || echo MISSING) YouTube, $([ -s "$MUSIC_STOCK" ] && echo present || echo MISSING) Music, $([ -s "$REDDIT_STOCK" ] && echo present || echo MISSING) Reddit"
echo "[+] Done. Run ./split-apk.sh before committing refreshed APKs."

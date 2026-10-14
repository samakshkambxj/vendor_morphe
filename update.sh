#!/bin/bash
# update.sh — fetch Morphe ROOT modules and stage the APKs for this vendor tree.
#
# Patched builds: downloaded automatically. Release "module" zips contain ROOT
# builds with stock package names (com.google.*) meant to replace stock apps.
# (Release "APK" assets are NON-ROOT builds with custom packages + GmsCore
# spoof — wrong variant for this tree.) The largest APK in each module is
# staged as common/product/etc/rv/{YTPatched,YTMusicPatched}.apk.
#
# Stock builds: cannot be auto-downloaded (redistribution). Supply them via
# flags or env, e.g. APKs matching the patched base version from APKMirror,
# or pulled from a device with adb. They install as the signature source
# that the patched builds mount over at boot.
#
# Usage:
#   ./update.sh                                                  # patched only (latest)
#   ./update.sh --stock-yt /path/to/base.apk --stock-music /path/to/base.apk
#   REPO=<builder> ./update.sh                                   # alternate module builder
#   TAG=<release-tag> ./update.sh                               # pin a builder release
#   STOCK_YT=/path STOCK_MUSIC=/path ./update.sh                # env form for stock
#
# After refreshing APKs for commit: ./split-apk.sh (vendorsetup.sh merges on envsetup).

set -euo pipefail

REPO="${REPO:-sixstrings/morphe-revanced-builder}"
VENDOR_DIR="$(cd "$(dirname "$0")" && pwd)"
YT_OUT="$VENDOR_DIR/common/product/etc/rv/YTPatched.apk"
MUSIC_OUT="$VENDOR_DIR/common/product/etc/rv/YTMusicPatched.apk"
YT_STOCK="$VENDOR_DIR/common/product/app/YouTube/com.google.android.youtube.apk"
MUSIC_STOCK="$VENDOR_DIR/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk"
mkdir -p "$(dirname "$YT_OUT")" "$(dirname "$YT_STOCK")" "$(dirname "$MUSIC_STOCK")"

STOCK_YT="${STOCK_YT:-}"
STOCK_MUSIC="${STOCK_MUSIC:-}"
while [ $# -gt 0 ]; do
    case "$1" in
        --stock-yt) STOCK_YT="${2:-}"; shift 2 ;;
        --stock-music) STOCK_MUSIC="${2:-}"; shift 2 ;;
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

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/morphe-update.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

if [ -n "${TAG:-}" ]; then
    echo "[*] Using pinned tag: $TAG"
else
    echo "[*] Querying latest release of $REPO ..."
    # Fetched to a variable first: piping curl into grep -m1/head under
    # `set -o pipefail` trips curl SIGPIPE (exit 23).
    RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")"
    TAG="$(printf '%s\n' "$RELEASE_JSON" | grep -m1 '"tag_name"' | cut -d'"' -f4)"
    echo "[*] Latest tag: $TAG"
fi

echo "[*] Listing release assets ..."
TAG_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$TAG")"
printf '%s\n' "$TAG_JSON" | grep '"browser_download_url"' | cut -d'"' -f4 || true

# `|| true`: grep -m1 closes the pipe early by design; don't let pipefail abort.
YT_ZIP_URL="$(printf '%s\n' "$TAG_JSON" | grep -m1 -o '"browser_download_url": *"[^"]*youtube-morphe-module-[^"]*\.zip"' | cut -d'"' -f4 || true)"
MUSIC_ZIP_URL="$(printf '%s\n' "$TAG_JSON" | grep -m1 -o '"browser_download_url": *"[^"]*youtube-music-morphe-module-[^"]*arm64-v8a\.zip"' | cut -d'"' -f4 || true)"

if [ -z "$YT_ZIP_URL" ] || [ -z "$MUSIC_ZIP_URL" ]; then
    echo "[!] Could not resolve module URLs. Check asset names at:"
    echo "    https://github.com/$REPO/releases/tag/$TAG"
    exit 1
fi

echo "[*] Downloading:"
echo "    $YT_ZIP_URL"
echo "    $MUSIC_ZIP_URL"
curl -fL -o "$WORKDIR/yt.zip" "$YT_ZIP_URL"
curl -fL -o "$WORKDIR/music.zip" "$MUSIC_ZIP_URL"

echo "[*] Extracting patched APKs (root builds, stock package names) ..."
# Module layout varies, so stage the largest APK in each module zip.
python3 -c "
import zipfile
for zip_path, out_path in [('$WORKDIR/yt.zip', '$YT_OUT'), ('$WORKDIR/music.zip', '$MUSIC_OUT')]:
    z = zipfile.ZipFile(zip_path)
    apks = [(i.filename, i.file_size) for i in z.infolist() if i.filename.endswith('.apk')]
    print(zip_path, apks)
    biggest = max(apks, key=lambda x: x[1])[0]
    print('biggest:', biggest)
    with z.open(biggest) as src, open(out_path, 'wb') as dst:
        dst.write(src.read())
"

echo "[*] Verifying package names (needs aapt) ..."
if command -v aapt >/dev/null 2>&1; then
    aapt dump badging "$YT_OUT" | head -n1
    aapt dump badging "$MUSIC_OUT" | head -n1
    echo "[*] Expected: com.google.android.youtube + com.google.android.apps.youtube.music"
    echo "[*] app.morphe.* here means the NON-ROOT asset was grabbed — re-run, modules only."
else
    echo "    (aapt not found, skipping check — verify before building)"
fi

ls -lh "$YT_OUT" "$MUSIC_OUT"
echo "[*] Stock APKs: $([ -s "$YT_STOCK" ] && echo present || echo MISSING) YouTube, $([ -s "$MUSIC_STOCK" ] && echo present || echo MISSING) Music"
echo "[+] Done. Run ./split-apk.sh before committing refreshed APKs."

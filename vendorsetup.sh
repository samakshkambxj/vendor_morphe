# vendor/morphe/vendorsetup.sh — build-environment hook.
# build/envsetup.sh sources every vendor/*/vendorsetup.sh, so this runs on
# `source build/envsetup.sh` (before lunch) and prepares the prebuilts:
#   1. merges *.apk.part* chunks back into full APKs (how large blobs are stored in git)
#   2. extracts arm64 native libs out of the stock APKs into .../lib/arm64
#   3. downloads patched builds via update.sh when they are missing
#
# Never breaks envsetup: every failure degrades to a warning.
#   MORPHE_NO_AUTO_FETCH=1 source build/envsetup.sh  # offline / CI: skip downloads
#   MORPHE_FETCH=1 source build/envsetup.sh          # force re-download of patched builds
#
# NOTE: this file is SOURCED, not executed. No `set -e`, no `exit`, only `return`.

if [ -n "${_MORPHE_VENDORSETUP_DONE:-}" ] && [ -z "${MORPHE_FETCH:-}" ]; then
    return 0 2>/dev/null || true
fi

_MORPHE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
_MORPHE_YT_STOCK="$_MORPHE_DIR/common/product/app/YouTube/com.google.android.youtube.apk"
_MORPHE_MUSIC_STOCK="$_MORPHE_DIR/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk"
_MORPHE_YT_PATCHED="$_MORPHE_DIR/common/product/etc/rv/YTPatched.apk"
_MORPHE_MUSIC_PATCHED="$_MORPHE_DIR/common/product/etc/rv/YTMusicPatched.apk"

echo "--- Morphe: Initializing Build Environment ---"

_morphe_merge_parts() {
    # $1 = dir, $2 = base apk name
    if [ -f "$1/$2.part000" ] || ls "$1/$2.part"* >/dev/null 2>&1; then
        echo "Merging: $2 in $1"
        if cat "$1/$2.part"* > "$1/$2"; then
            echo "Successfully merged $2"
        else
            echo "WARNING: failed to merge $2"
        fi
    fi
}

_morphe_extract_libs() {
    # $1 = app dir, $2 = apk name — stock APKs ship arm64-v8a libs that must
    # sit next to the installed APK as lib/arm64 for the runtime linker.
    if [ -s "$1/$2" ]; then
        if ! command -v unzip >/dev/null 2>&1; then
            echo "WARNING: 'unzip' not found — cannot extract libs for $2"
            return 0
        fi
        echo "Extracting libs for $2..."
        rm -rf "$1/lib"
        mkdir -p "$1/lib"
        if unzip -q -o "$1/$2" "lib/arm64-v8a/*" -d "$1" 2>/dev/null \
                && [ -d "$1/lib/arm64-v8a" ]; then
            mv "$1/lib/arm64-v8a" "$1/lib/arm64"
            touch "$1/lib/placeholder.txt"
            echo "Libs processed: $1/lib/arm64"
        else
            # APK has no bundled arm64 libs (or unzip found none) — keep dir valid.
            touch "$1/lib/placeholder.txt"
            echo "No arm64-v8a libs in $2, skipping."
        fi
    fi
}

_morphe_merge_parts "$_MORPHE_DIR/common/product/etc/rv" "YTPatched.apk"
_morphe_merge_parts "$_MORPHE_DIR/common/product/etc/rv" "YTMusicPatched.apk"
_morphe_merge_parts "$_MORPHE_DIR/common/product/app/YouTube" "com.google.android.youtube.apk"
_morphe_merge_parts "$_MORPHE_DIR/common/product/app/YTMusic" "com.google.android.apps.youtube.music.apk"

_morphe_extract_libs "$_MORPHE_DIR/common/product/app/YouTube" "com.google.android.youtube.apk"
_morphe_extract_libs "$_MORPHE_DIR/common/product/app/YTMusic" "com.google.android.apps.youtube.music.apk"

# Patched builds: fetch when missing (or forced), unless opted out.
_morphe_need_fetch=0
[ -s "$_MORPHE_YT_PATCHED" ] || _morphe_need_fetch=1
[ -s "$_MORPHE_MUSIC_PATCHED" ] || _morphe_need_fetch=1
[ -n "${MORPHE_FETCH:-}" ] && _morphe_need_fetch=1

if [ "$_morphe_need_fetch" -eq 1 ]; then
    if [ -n "${MORPHE_NO_AUTO_FETCH:-}" ]; then
        echo "[morphe] Patched APKs missing, auto-fetch disabled (MORPHE_NO_AUTO_FETCH=1)."
        echo "         Run manually: cd vendor/morphe && ./update.sh"
    elif [ ! -x "$_MORPHE_DIR/update.sh" ]; then
        echo "WARNING: $_MORPHE_DIR/update.sh not found — run ./update.sh manually."
    elif bash "$_MORPHE_DIR/update.sh"; then
        echo "[morphe] Patched APKs ready."
    else
        echo "WARNING: patched-APK fetch failed (network or upstream rename?)."
        echo "         Run manually: cd vendor/morphe && ./update.sh"
    fi
fi

# Stock APKs cannot be auto-downloaded (redistribution); they must be supplied.
[ -s "$_MORPHE_YT_STOCK" ] || echo "WARNING: stock YouTube APK missing — place it at common/product/app/YouTube/com.google.android.youtube.apk (see README)."
[ -s "$_MORPHE_MUSIC_STOCK" ] || echo "WARNING: stock YT Music APK missing — place it at common/product/app/YTMusic/com.google.android.apps.youtube.music.apk (see README)."

echo "--- Morphe: Setup Complete ---"

_MORPHE_VENDORSETUP_DONE=1
return 0 2>/dev/null || true

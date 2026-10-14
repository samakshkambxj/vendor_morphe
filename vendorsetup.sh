# vendor/morphe/vendorsetup.sh — build-environment hook.
# build/envsetup.sh sources every vendor/*/vendorsetup.sh, so this runs on
# `source build/envsetup.sh` (before lunch) and prepares the prebuilts:
#   1. merges *.apk.part* chunks back into full APKs (how large blobs are stored in git)
#   2. extracts arm64 native libs out of the stock APKs into .../lib/arm64
#   3. downloads patched builds via update.sh when they are missing
#
# Never breaks envsetup: every failure degrades to a warning.
# Re-evaluates from scratch on every source (no sticky state): sourcing twice
# in one shell still warns about missing APKs instead of going silent.
#   MORPHE_NO_AUTO_FETCH=1 source build/envsetup.sh  # offline / CI: skip downloads
#   MORPHE_FETCH=1 source build/envsetup.sh          # force re-download of patched builds
#
# NOTE: this file is SOURCED, not executed. No `set -e`, no `exit`, only `return`.

_MORPHE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
_MORPHE_YT_STOCK="$_MORPHE_DIR/common/product/app/YouTube/com.google.android.youtube.apk"
_MORPHE_MUSIC_STOCK="$_MORPHE_DIR/common/product/app/YTMusic/com.google.android.apps.youtube.music.apk"
_MORPHE_YT_PATCHED="$_MORPHE_DIR/common/product/etc/rv/YTPatched.apk"
_MORPHE_MUSIC_PATCHED="$_MORPHE_DIR/common/product/etc/rv/YTMusicPatched.apk"

echo "--- Morphe: Initializing Build Environment ---"

_morphe_merge_parts() {
    # $1 = dir, $2 = base apk name. Merges only when the target is missing
    # or any chunk is newer (keeps repeat sources fast, refreshes on update).
    local found=0 stale=0 p
    for p in "$1/$2.part"*; do
        [ -e "$p" ] || continue
        found=1
        if [ ! -s "$1/$2" ] || [ "$p" -nt "$1/$2" ]; then
            stale=1
        fi
    done
    if [ "$found" -eq 1 ] && [ "$stale" -eq 1 ]; then
        echo "Merging: $2 in $1"
        if cat "$1/$2.part"* > "$1/$2"; then
            echo "Successfully merged $2"
        else
            echo "WARNING: failed to merge $2"
        fi
    fi
}

_morphe_extract_libs() {
    # $1 = app dir; remaining args = candidate APK full paths in preference
    # order (stock first: version-identical full set; patched fallback in
    # stockless mode — module APKs keep libs Deflated with extraction
    # disabled, so without staging them the app dies at startup with
    # UnsatisfiedLinkError). Skips when lib/arm64 is already populated.
    local app_dir=$1
    shift
    local apk=""
    for a in "$@"; do
        if [ -s "$a" ]; then
            apk="$a"
            break
        fi
    done
    [ -n "$apk" ] || return 0
    if [ -d "$app_dir/lib/arm64" ] && [ -n "$(ls -A "$app_dir/lib/arm64" 2>/dev/null)" ]; then
        return 0
    fi
    if ! command -v unzip >/dev/null 2>&1; then
        echo "WARNING: 'unzip' not found — cannot extract libs for $(basename "$apk")"
        return 0
    fi
    echo "Extracting libs for $(basename "$apk")..."
    rm -rf "$app_dir/lib"
    mkdir -p "$app_dir/lib"
    if unzip -q -o "$apk" "lib/arm64-v8a/*" -d "$app_dir" 2>/dev/null \
            && [ -d "$app_dir/lib/arm64-v8a" ]; then
        mv "$app_dir/lib/arm64-v8a" "$app_dir/lib/arm64"
        touch "$app_dir/lib/placeholder.txt"
        echo "Libs processed: $app_dir/lib/arm64"
    else
        # APK has no bundled arm64 libs (or unzip found none) — keep dir valid.
        touch "$app_dir/lib/placeholder.txt"
        echo "No arm64-v8a libs in $(basename "$apk"), skipping."
    fi
}

_morphe_merge_parts "$_MORPHE_DIR/common/product/etc/rv" "YTPatched.apk"
_morphe_merge_parts "$_MORPHE_DIR/common/product/etc/rv" "YTMusicPatched.apk"
_morphe_merge_parts "$_MORPHE_DIR/common/product/app/YouTube" "com.google.android.youtube.apk"
_morphe_merge_parts "$_MORPHE_DIR/common/product/app/YTMusic" "com.google.android.apps.youtube.music.apk"

_morphe_extract_libs "$_MORPHE_DIR/common/product/app/YouTube" "$_MORPHE_YT_STOCK" "$_MORPHE_YT_PATCHED"
_morphe_extract_libs "$_MORPHE_DIR/common/product/app/YTMusic" "$_MORPHE_MUSIC_STOCK" "$_MORPHE_MUSIC_PATCHED"

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

# Stock APKs cannot be auto-downloaded (redistribution) and are OPTIONAL:
# stockless ROMs (no Google apps in-tree) skip them and the patched build
# installs directly as the app — mount mode needs a stock base to swap over.
[ -s "$_MORPHE_YT_STOCK" ] || echo "NOTE: no stock YouTube APK — stockless mode, patched build installs directly (mount mode needs a stock base; see README)."
[ -s "$_MORPHE_MUSIC_STOCK" ] || echo "NOTE: no stock YT Music APK — stockless mode, patched build installs directly (mount mode needs a stock base; see README)."

echo "--- Morphe: Setup Complete ---"

return 0 2>/dev/null || true

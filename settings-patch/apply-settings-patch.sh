#!/bin/bash
# apply-settings-patch.sh — put the Morphe toggles inside ROM Settings.
#
# Copies MorpheSettingsFragment + morphe_settings.xml into
# packages/apps/Settings and hooks a top-level entry into
# res/xml/top_level_settings.xml. Everything is marker-guarded, so the
# script is idempotent (safe to re-run) and reversible (--revert).
#
# Search indexing is the one step this script does NOT automate: the
# registry file differs per Settings tree. The script prints the exact
# 3-line snippet for your tree when it finishes.
#
# Usage (run from anywhere; ROM root is derived from this script's path):
#   ./apply-settings-patch.sh            # status + interactive prompt if tty
#   ./apply-settings-patch.sh --apply    # apply without prompting
#   ./apply-settings-patch.sh --check    # exit 0 applied, 1 missing
#   ./apply-settings-patch.sh --refresh  # refresh stale marked copies only
#   ./apply-settings-patch.sh --revert   # remove everything again
# Env:
#   SETTINGS_DIR=...  override the Settings path (default:
#                     <rom-root>/packages/apps/Settings)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES_DIR="$SCRIPT_DIR/files"
ROM_ROOT="${ROM_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
SETTINGS_DIR="${SETTINGS_DIR:-$ROM_ROOT/packages/apps/Settings}"

FRAGMENT_SRC="$FILES_DIR/src/com/android/settings/morphe/MorpheSettingsFragment.kt"
XML_SRC="$FILES_DIR/res/xml/morphe_settings.xml"
FRAGMENT_DST="src/com/android/settings/morphe/MorpheSettingsFragment.kt"
XML_DST="res/xml/morphe_settings.xml"
DASHBOARD="res/xml/top_level_settings.xml"
BEGIN_MARK="morphe-settings:dashboard-begin"
END_MARK="morphe-settings:dashboard-end"

DASHBOARD_BLOCK='    <!-- morphe-settings:dashboard-begin -->
    <Preference
        android:key="morphe_settings"
        android:title="Morphe"
        android:summary="Patched YouTube, Music and Reddit"
        android:fragment="com.android.settings.morphe.MorpheSettingsFragment" />
    <!-- morphe-settings:dashboard-end -->'

# Locate the search-index registry (name varies: .kt/.java, Impl or not)
# and print a tailored registration snippet for the style found there.
# Deliberately locate-only: inventing a registry call blind risks breaking
# the Settings build, so the one line stays manual — but exact.
show_search_guidance() {
    local -a cands=()
    mapfile -t cands < <(find "$SETTINGS_DIR/src" -iname '*searchindexable*' 2>/dev/null | sort) || true
    if [ ${#cands[@]} -eq 0 ]; then
        echo "[settings-patch] no search registry found under src/ by name."
        echo "[settings-patch] add the SEARCH_INDEX_DATA_PROVIDER line manually (see README §7)."
        return 0
    fi
    echo "[settings-patch] search registry discovery:"
    local f
    for f in "${cands[@]}"; do
        echo "  file: ${f#$SETTINGS_DIR/}"
        if grep -q -E 'sResMap\.put|sResMap\[' "$f"; then
            echo "  style: map entries — add one line in the same shape:"
            grep -m2 -E 'sResMap\.(put|\[)' "$f" | sed 's/^/    | /'
            echo "    + equivalent entry for"
            echo "      com.android.settings.morphe.MorpheSettingsFragment with"
            echo "      R.xml.morphe_settings (see its SEARCH_INDEX_DATA_PROVIDER)."
        elif grep -q 'addIndex(' "$f"; then
            echo "  style: addIndex helper — mirror a neighboring line:"
            grep -m2 'addIndex(' "$f" | sed 's/^/    | /'
            echo "    + equivalent addIndex for"
            echo "      com.android.settings.morphe.MorpheSettingsFragment."
        else
            echo "  style: unrecognized — open it, mirror a neighboring entry for"
            echo "  com.android.settings.morphe.MorpheSettingsFragment (README §7)."
        fi
    done
    echo "[settings-patch] rebuild Settings afterwards; the entry then appears in search."
}

die() { echo "[settings-patch] ERROR: $*" >&2; exit 1; }
[ -d "$SETTINGS_DIR" ] || die "no Settings tree at $SETTINGS_DIR (set SETTINGS_DIR=... to override)"

is_applied() {
    grep -q "$BEGIN_MARK" "$SETTINGS_DIR/$DASHBOARD" 2>/dev/null \
        && grep -q "morphe-settings:fragment" "$SETTINGS_DIR/$FRAGMENT_DST" 2>/dev/null \
        && grep -q "morphe-settings:xml" "$SETTINGS_DIR/$XML_DST" 2>/dev/null
}

do_apply() {
    # Always refresh the file copies: is_applied only tells whether the
    # patch exists, not whether the copies match a newer kit revision.
    [ -f "$FRAGMENT_SRC" ] || die "patch files missing under $FILES_DIR"
    mkdir -p "$SETTINGS_DIR/src/com/android/settings/morphe" "$SETTINGS_DIR/res/xml"
    cp -f "$FRAGMENT_SRC" "$SETTINGS_DIR/$FRAGMENT_DST"
    cp -f "$XML_SRC" "$SETTINGS_DIR/$XML_DST"
    echo "[settings-patch] copied fragment + screen XML."

    if [ ! -f "$SETTINGS_DIR/$DASHBOARD" ]; then
        echo "[settings-patch] WARNING: $DASHBOARD not found in this tree."
        echo "  Files are in place; add a dashboard entry manually pointing at"
        echo "  fragment com.android.settings.morphe.MorpheSettingsFragment."
    else
        if python3 - "$SETTINGS_DIR/$DASHBOARD" <<'EOF'
import sys
path = sys.argv[1]
block = """    <!-- morphe-settings:dashboard-begin -->
    <Preference
        android:key="morphe_settings"
        android:title="Morphe"
        android:summary="Patched YouTube, Music and Reddit"
        android:fragment="com.android.settings.morphe.MorpheSettingsFragment" />
    <!-- morphe-settings:dashboard-end -->"""
src = open(path).read()
if "morphe-settings:dashboard-begin" in src:
    print("dashboard entry already present.")
    sys.exit(0)
anchor = "</PreferenceScreen>"
if anchor not in src:
    sys.exit("DASHBOARD_ANCHOR_MISSING")
open(path, "w").write(src.replace(anchor, block + "\n" + anchor, 1))
print("dashboard entry added.")
EOF
        then
            true
        else
            echo "[settings-patch] WARNING: dashboard anchor not found — add the entry manually:"
            echo "$DASHBOARD_BLOCK"
        fi
    fi
    echo "[settings-patch] applied."
    show_search_guidance
}

do_refresh() {
    # Refresh kit file copies when the tree holds a marked but outdated
    # revision (dashboard block untouched). Silent when already current.
    # Files without our marker are never touched.
    local refreshed=0 f base
    for f in "$FRAGMENT_DST" "$XML_DST"; do
        base="$SETTINGS_DIR/$f"
        if [ -f "$base" ] && grep -q "morphe-settings:" "$base" \
                && ! cmp -s "$FILES_DIR/$f" "$base"; then
            cp -f "$FILES_DIR/$f" "$base"
            refreshed=1
        fi
    done
    if [ "$refreshed" -eq 1 ]; then
        echo "[settings-patch] refreshed to latest kit revision."
    fi
    return 0
}

do_revert() {
    if ! is_applied && [ ! -f "$SETTINGS_DIR/$FRAGMENT_DST" ] && [ ! -f "$SETTINGS_DIR/$XML_DST" ]; then
        echo "[settings-patch] nothing applied — nothing to revert."
        return 0
    fi
    python3 - "$SETTINGS_DIR/$DASHBOARD" <<'EOF' 2>/dev/null || true
import sys, re
path = sys.argv[1]
try:
    src = open(path).read()
except OSError:
    sys.exit(0)
pat = re.compile(r"^[ \t]*<!--[ \t]*morphe-settings:dashboard-begin.*?morphe-settings:dashboard-end[ \t]*-->[ \t]*\n", re.M | re.S)
open(path, "w").write(pat.sub("", src))
print("dashboard entry removed.")
EOF
    for f in "$SETTINGS_DIR/$FRAGMENT_DST" "$SETTINGS_DIR/$XML_DST"; do
        if [ -f "$f" ] && grep -q "morphe-settings:" "$f"; then
            rm -f "$f"
            echo "[settings-patch] removed $f"
        elif [ -f "$f" ]; then
            echo "[settings-patch] WARNING: $f lacks our marker — left untouched."
        fi
    done
    # Prune the now-empty package dir (only if we created it and it is empty).
    rmdir "$SETTINGS_DIR/src/com/android/settings/morphe" 2>/dev/null || true
    echo "[settings-patch] reverted. (Search-registry line, if you added it, must be removed manually.)"
}

case "${1:-}" in
    --check)
        if is_applied; then echo "[settings-patch] applied."; exit 0
        else echo "[settings-patch] missing."; exit 1; fi ;;
    --apply) do_apply ;;
    --revert) do_revert ;;
    --refresh) do_refresh ;;
    --find-search) show_search_guidance ;;
    "" )
        if is_applied; then
            echo "[settings-patch] already applied."
        elif [ ! -t 0 ]; then
            echo "[settings-patch] missing (non-interactive; re-run with --apply)."
        else
            printf '[settings-patch] add the Morphe screen to ROM Settings at %s? [y/N] ' "$SETTINGS_DIR"
            read -r ans || ans=""
            if [[ "$ans" == [yY]* ]]; then do_apply
            else echo "[settings-patch] skipped (re-run with --apply anytime)."; fi
        fi ;;
    --help|-h) sed -n '2,/^$/p' "$0" ;;
    *) die "unknown arg: $1 (try --help)" ;;
esac

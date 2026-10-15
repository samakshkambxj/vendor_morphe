#!/bin/bash
# update.sh — stage patched + stock APKs for this vendor tree.
#
# Patched builds come from ROOT module zips (stock package names com.google.*,
# meant to replace stock apps). Two ways to supply them:
#   1. Downloaded automatically, own builder first:
#      samakshkambxj/morphe-builder releases (exact youtube/music/reddit-
#      module.zip assets + versions.json manifest, sha256-verified), falling
#      back per-run to the upstream builder's rotating tags when ours has no
#      usable release yet. Force one side with REPO=<owner/repo>.
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
#   REPO=<owner/repo> ./update.sh                            # force single builder (skip own/upstream chain)
#   OWN_REPO=<owner/repo> UPSTREAM_REPO=<owner/repo> ./update.sh  # override either side of the chain
#   TAG=<release-tag> ./update.sh                               # pin a builder release
#   STOCK_YT=/path STOCK_MUSIC=/path STOCK_REDDIT=/path YT_MOD=/path MUSIC_MOD=/path REDDIT_MOD=/path ./update.sh  # env form
#
# After refreshing APKs for commit: ./split-apk.sh (vendorsetup.sh merges on envsetup).

set -euo pipefail

REPO_OVERRIDE="${REPO:-}"
OWN_REPO="${OWN_REPO:-samakshkambxj/morphe-builder}"
# Optional second source consulted only when set (never a default).
UPSTREAM_REPO="${UPSTREAM_REPO:-}"
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

    _pick_upstream() {
        # $1 = one release's JSON (upstream rotating-tag layout). Sets *_ZIP_URL.
        YT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'youtube-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        # Prefer arm64, fall back to whatever arch the release carries.
        MUSIC_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'music-morphe-module-' | grep 'arm64' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        if [ -z "$MUSIC_ZIP_URL" ]; then
            MUSIC_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'music-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        fi
        REDDIT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'reddit-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
    }

    _pick_own() {
        # $1 = one release's JSON (own builder). Current versioned names
        # (<prefix>-morphe-module-v<base>-<arch>.zip) first, then the legacy
        # flat names (youtube/music/reddit-module.zip) so older releases
        # stay consumable.
        YT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'youtube-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        [ -n "$YT_ZIP_URL" ] || YT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep '/youtube-module\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        MUSIC_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'music-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        [ -n "$MUSIC_ZIP_URL" ] || MUSIC_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep '/music-module\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        REDDIT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep 'reddit-morphe-module-' | grep '\.zip"' | head -n1 | cut -d'"' -f4 || true)"
        [ -n "$REDDIT_ZIP_URL" ] || REDDIT_ZIP_URL="$(printf '%s\n' "$1" | grep 'browser_download_url' | grep '/reddit-module\.zip"' | head -n1 | cut -d'"' -f4 || true)"
    }

    fetch_versions() {
        # $1 = repo, $2 = tag, $3 = out path. Prints path on success, nothing otherwise.
        if curl -fsSL -o "$3" "https://github.com/$1/releases/download/$2/versions.json" 2>/dev/null; then
            echo "$3"
        fi
    }

    verify_sha() {
        # $1 = staged apk, $2 = versions.json, $3 = app key (YouTube|Music|Reddit).
        [ -f "$2" ] || return 0
        python3 - "$1" "$2" "$3" <<'EOF'
import json, sys, hashlib
apk, man, app = sys.argv[1], sys.argv[2], sys.argv[3]
want = json.load(open(man))["apps"][app]["sha256"]
got = hashlib.sha256(open(apk, "rb").read()).hexdigest()
print(f"sha256 {app}: manifest {want[:12]}.. staged {got[:12]}..")
sys.exit(0 if want == got else f"SHA256 MISMATCH for {app}")
EOF
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
    MANIFEST=""
    pick_repo() {
        # $1 = repo, $2 = own|upstream. Resolves URLs for still-needed apps
        # (TAG pin or newest-first scan), sets TAG on success. Returns nonzero
        # when this repo cannot satisfy the run.
        local repo=$1 mode=$2 t json tags
        if [ -n "${TAG:-}" ]; then
            echo "[*] Using pinned tag: $TAG ($repo)"
            json="$(curl -fsSL "https://api.github.com/repos/$repo/releases/tags/$TAG")" || return 1
            if [ "$mode" = "own" ]; then _pick_own "$json"; else _pick_upstream "$json"; fi
            _have_needed || return 1
        else
            echo "[*] Scanning recent releases of $repo ..."
            tags="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=10" | grep '"tag_name"' | cut -d'"' -f4)" || return 1
            for t in $tags; do
                json="$(curl -fsSL "https://api.github.com/repos/$repo/releases/tags/$t")" || continue
                if [ "$mode" = "own" ]; then _pick_own "$json"; else _pick_upstream "$json"; fi
                if _have_needed; then TAG="$t"; break; fi
            done
            [ -n "${TAG:-}" ] || return 1
            echo "[*] Selected tag: $TAG ($repo)"
        fi
        return 0
    }
    if [ -n "$REPO_OVERRIDE" ]; then
        echo "[*] Forced single builder: $REPO_OVERRIDE (own/upstream chain skipped)"
        if [ -n "${TAG:-}" ]; then
            echo "[*] Using pinned tag: $TAG"
            TAG_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO_OVERRIDE/releases/tags/$TAG")"
            _pick_upstream "$TAG_JSON"
            _have_needed || { echo "[!] Tag $TAG lacks the needed module(s): https://github.com/$REPO_OVERRIDE/releases/tag/$TAG"; exit 1; }
        else
            echo "[*] Scanning recent releases of $REPO_OVERRIDE ..."
            RELEASES_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO_OVERRIDE/releases?per_page=10")"
            for t in $(printf '%s\n' "$RELEASES_JSON" | grep '"tag_name"' | cut -d'"' -f4); do
                TAG_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO_OVERRIDE/releases/tags/$t")"
                _pick_upstream "$TAG_JSON"
                if _have_needed; then TAG="$t"; break; fi
            done
            [ -n "${TAG:-}" ] || { echo "[!] No recent release of $REPO_OVERRIDE holds the needed module(s)."; exit 1; }
            echo "[*] Selected tag: $TAG"
        fi
    elif pick_repo "$OWN_REPO" own; then
        echo "[*] Source: own builder."
        MANIFEST="$WORKDIR/versions.json"
        fetch_versions "$OWN_REPO" "$TAG" "$MANIFEST" >/dev/null || MANIFEST=""
        [ -n "$MANIFEST" ] && echo "[*] Manifest: $OWN_REPO tag $TAG (staged builds will be sha256-verified)."
    elif [ -n "$UPSTREAM_REPO" ] && pick_repo "$UPSTREAM_REPO" upstream; then
        echo "[*] Source: upstream fallback ($UPSTREAM_REPO tag $TAG — own builder has no usable release yet)."
    else
        echo "[!] No usable release in $OWN_REPO (set UPSTREAM_REPO=<owner/repo> to enable fallback)."
        exit 1
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

    if [ -n "${MANIFEST:-}" ] && [ -f "$MANIFEST" ]; then
        echo "[*] Verifying staged builds against the release manifest ..."
        if [ "$NEED_DL_YT" -eq 1 ]; then verify_sha "$YT_OUT" "$MANIFEST" YouTube; fi
        if [ "$NEED_DL_MUSIC" -eq 1 ]; then verify_sha "$MUSIC_OUT" "$MANIFEST" Music; fi
        if [ "$NEED_DL_REDDIT" -eq 1 ]; then verify_sha "$REDDIT_OUT" "$MANIFEST" Reddit; fi
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

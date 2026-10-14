#!/bin/bash
# split-apk.sh — split large APKs into 20MB chunks for git storage.
# GitHub rejects files over 100MB; *.apk.part* chunks stay committable
# (see .gitignore) and vendorsetup.sh merges them back on envsetup.
# Run from this directory before committing refreshed APKs:
#   cd vendor/morphe && ./split-apk.sh
set -euo pipefail

SIZE="20m"

find . -type f -name "*.apk" ! -name "*.part*" | while read -r apk; do
    echo "Splitting: $apk"

    rm -f "$apk.part"*

    if split -b "$SIZE" -d -a 3 "$apk" "$apk.part"; then
        echo "Successfully created parts for $(basename "$apk")"
    else
        echo "Error: Failed to split $apk"
    fi
done

echo "--- Splitting Complete ---"

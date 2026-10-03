#!/bin/sh
# Compile content/ (models, materials, Panorama) into the addon with Dota's resourcecompiler.
. "$(dirname "$0")/env.sh"
python "$HERE/tools/check_lua.py" || exit 1
for g in "models/*.vmdl" "panorama/*.xml" "panorama/*.js"; do "$RC" -fshallow2 -r -i "$ADDON_CONTENT/$g" 2>&1; done | grep -E "OK:|failed|rror|Unable"

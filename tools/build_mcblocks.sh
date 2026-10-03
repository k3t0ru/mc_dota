#!/bin/sh
# Every Minecraft block as a Dota model: generate from the local Minecraft jar, then compile (~13 min the first time).
# Run once per PC (setup.sh does), and again after a Minecraft version change.
. "$(dirname "$0")/env.sh"
python "$HERE/tools/gen_mcblocks.py" && "$RC" -fshallow2 -r -i "$ADDON_CONTENT/models/mcb/*.vmdl" 2>&1 | grep -E "OK:|failed|rror" | tail -3

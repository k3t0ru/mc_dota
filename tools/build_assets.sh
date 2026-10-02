#!/bin/sh
# Compile content/ (models, materials) into the addon with Dota's resourcecompiler.
RC="/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/bin/win64/resourcecompiler.exe"
C="C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta/content/dota_addons/mc_dungeons"
for g in "models/*.vmdl" "panorama/*.xml" "panorama/*.js"; do "$RC" -fshallow2 -r -i "$C/$g" 2>&1; done | grep -E "OK:|failed|rror|Unable" 

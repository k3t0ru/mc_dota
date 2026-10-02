#!/bin/sh
# One-time setup on a new PC (run from Git Bash inside the project folder):  sh tools/setup.sh
# Needs: Dota 2 + "Dota 2 Workshop Tools" DLC, JDK 21, Python 3 with Pillow (pip install pillow), Git for Windows, internet.
. "$(dirname "$0")/env.sh"
set -e
[ -f "$DOTA_EXE" ] || { echo "Dota not found at $DOTA_DIR - set DOTA_DIR"; exit 1; }
[ -d "$DOTA_DIR/content" ] || { echo "Install the Dota 2 Workshop Tools DLC first (Steam > Dota 2 > Properties > DLC)"; exit 1; }
java -version 2>&1 | grep -q '"21' || echo "WARNING: JDK 21 expected (java -version)"

# link the addon into Dota (game side + content side)
W=$(cygpath -w "$HERE")
powershell -NoProfile -Command "foreach (\$d in @('game','content')) { \$p = '$(cygpath -w "$DOTA_DIR")\' + \$d + '\dota_addons\mc_dungeons'; if (-not (Test-Path \$p)) { New-Item -ItemType Junction -Path \$p -Target ('$W' + \$(if (\$d -eq 'content') { '\content' } else { '' })) | Out-Null } }"

# test map: a copy of Valve's hero_demo map from the user's own install (never shipped)
mkdir -p "$HERE/maps"
cp -n "$DOTA_DIR/game/dota_addons/hero_demo/maps/hero_demo_main.vpk" "$HERE/maps/" 2>/dev/null || true

# Minecraft: first build downloads Minecraft + Fabric (~5-10 min), then the world and options
(cd "$HERE/mcmod" && ./gradlew --no-daemon build)
mkdir -p "$HERE/mcmod/run/saves/mcdota"
cp -n "$HERE/tools/template/level.dat" "$HERE/mcmod/run/saves/mcdota/level.dat" 2>/dev/null || true
cp -n "$HERE/tools/template/options.txt" "$HERE/mcmod/run/options.txt" 2>/dev/null || true

# block models + Minecraft textures from the local Minecraft jar (downloaded by the build above), Panorama
python "$HERE/tools/gen_blocks.py" && sh "$HERE/tools/build_assets.sh"
echo "Done. Set Dota to windowed 1600x900 (see SETUP.md), then:  sh tools/dev_launch.sh"

#!/bin/sh
# Rebuild everything for the checked-out version: Dota assets (models, Panorama) + the Minecraft mod.
# Switch versions:  git checkout overlay-v1   (old: Minecraft draws blocks)  |  git checkout hybrid   (Dota draws blocks)
# then:             sh tools/build_all.sh && sh tools/dev_launch.sh   (kill old dota2/java first; Panorama needs a Dota restart)
cd "$(dirname "$0")/.."
python tools/gen_blocks.py >/dev/null && sh tools/build_assets.sh
(cd mcmod && ./gradlew --no-daemon build 2>&1 | grep -E "error|BUILD")

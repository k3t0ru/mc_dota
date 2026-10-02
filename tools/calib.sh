#!/bin/sh
# Camera calibration shot: Steve at MC 0,0 facing north, three reference blocks, then Dota's camera probe + a composite
# screenshot (CALIBRATE=true in addon_game_mode.lua shows Dota's own cubes under Minecraft's). Needs dev_launch.sh first.
UM=/c/Users/Roman/.claude/plugins/cache/universal-modder/universal-modder/0.1.0/bin/um
LOG="/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota/console.log"
OUT=${1:-calib}
for c in "/tp @p 0.5 -60 0.5 ${YAW:-180} ${PITCH:-12}" "/fill -4 -60 -8 3 -58 -3 minecraft:air" "/setblock 0 -60 -4 minecraft:cobblestone" "/setblock 2 -60 -7 minecraft:oak_log" "/setblock -3 -60 -6 minecraft:stone"; do
	"$UM" win drive --proc java "key 0x54" "type $c" "key 0x0D" >/dev/null 2>&1
	sleep 1
done
sleep 4
grep "\[mc\] probe" "$LOG" | tail -1
FF=/c/Users/Roman/AppData/Local/universal-modder/ffmpeg/bin/ffmpeg.exe
"$FF" -y -loglevel error -f lavfi -i "ddagrab=0:framerate=5,hwdownload,format=bgra" -frames:v 1 "$OUT.png"

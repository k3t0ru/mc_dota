#!/bin/sh
# Dev run: Dota custom game (cheats, Steve auto-picked) then the Minecraft client with the overlay mod.
# Needs the MC server + bridge already running (see MODLOG.md). Kill old dota2/java clients first (by PID).
UM=/c/Users/Roman/.claude/plugins/cache/universal-modder/universal-modder/0.1.0/bin/um
LOG="/c/Program Files (x86)/Steam/steamapps/common/dota 2 beta/game/dota/console.log"
D='C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta\game\bin\win64\dota2.exe'
HERE=$(cd "$(dirname "$0")/.." && pwd)

rm -f "$LOG"
("$UM" win launch "$D" -- -novid -console -condebug -windowed -noborder -w 1600 -h 900 +dota_camera_edgemove 0 +dota_camera_speed 0 +dota_camera_lock 0 +sv_cheats 1 +dota_launch_custom_game mc_dungeons hero_demo_main >/dev/null 2>&1 &)
for i in $(seq 1 90); do grep -q "bridge online" "$LOG" 2>/dev/null && break; sleep 2; done
grep -E "\[mc\]" "$LOG" | tail -2

cd "$HERE/mcmod"
rm -f run/logs/latest.log
(./gradlew --no-daemon runClient > run/gradle_run.log 2>&1 &)
for i in $(seq 1 120); do grep -qE "joined the game|has crashed" run/logs/latest.log 2>/dev/null && break; sleep 2; done
grep -E "joined the game|has crashed" run/logs/latest.log | tail -1

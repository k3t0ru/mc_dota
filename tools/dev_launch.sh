#!/bin/sh
# Start everything: the bridge (if not running), the Dota custom game (cheats, Steve auto-picked), the Minecraft client.
# Closes an old Dota / Minecraft first.
. "$(dirname "$0")/env.sh"
python "$HERE/tools/check_lua.py" || exit 1 # a Lua syntax error drops the whole game mode silently
kill_pids $(mc_pids) $(dota_pids)
sleep 3
[ -z "$(bridge_pids)" ] && (cd "$HERE" && python -u bridge/bridge.py > bridge/bridge.log 2>&1 &)

rm -f "$DOTA_LOG"
cmd //c start "" "$(cygpath -w "$DOTA_EXE")" -novid -console -condebug -windowed -noborder -w ${DOTA_SIZE%x*} -h ${DOTA_SIZE#*x} +dota_camera_edgemove 0 +dota_camera_speed 0 +dota_camera_lock 0 +dota_camera_fov_min 90 +dota_camera_fov_max 90 +dota_camera_z_interp_speed 100000 +fps_max $DOTA_FPS +engine_no_focus_sleep 0 +fog_enable 0 +r_farz 40000 +dota_camera_zfar_zoomed_in 40000 +dota_camera_zfar_zoomed_out 40000 +snd_mute_losefocus 0 +snd_musicvolume 0 +sv_cheats 1 +dota_launch_custom_game mc_dungeons $DOTA_MAP
for i in $(seq 1 120); do grep -q "bridge online" "$DOTA_LOG" 2>/dev/null && break; sleep 2; done
grep -E "\[mc\] bridge" "$DOTA_LOG" | tail -1
# a runtime error while loading the game mode leaves Dota running without it (hero pick, no bridge): say so loudly
grep -E "Script load error|Error running script|Script Runtime Error" "$DOTA_LOG" && echo "!!! Dota script error: see $DOTA_LOG"

# a fresh Minecraft world every launch: Dota rebuilds the terrain from its map anyway, and columns left over from earlier
# sessions (other heights, another origin) made the ground stop matching Dota's
rm -rf "$HERE/mcmod/run/saves/mcdota/region" "$HERE/mcmod/run/saves/mcdota/entities" "$HERE/mcmod/run/saves/mcdota/poi"
cd "$HERE/mcmod"
rm -f run/logs/latest.log
(./gradlew --no-daemon runClient > run/gradle_run.log 2>&1 &)
for i in $(seq 1 150); do grep -qE "joined the game|has crashed" run/logs/latest.log 2>/dev/null && break; sleep 2; done
grep -E "joined the game|has crashed" run/logs/latest.log | tail -1

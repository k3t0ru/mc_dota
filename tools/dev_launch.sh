#!/bin/sh
# Start everything: the bridge (if not running), the Dota custom game (cheats, Steve auto-picked), the Minecraft client.
# Closes an old Dota / Minecraft first.
. "$(dirname "$0")/env.sh"
kill_pids $(mc_pids) $(dota_pids)
sleep 3
[ -z "$(bridge_pids)" ] && (cd "$HERE" && python -u bridge/bridge.py > bridge/bridge.log 2>&1 &)

rm -f "$DOTA_LOG"
cmd //c start "" "$(cygpath -w "$DOTA_EXE")" -novid -console -condebug -windowed -noborder -w ${DOTA_SIZE%x*} -h ${DOTA_SIZE#*x} +dota_camera_edgemove 0 +dota_camera_speed 0 +dota_camera_lock 0 +dota_camera_fov_min 90 +dota_camera_fov_max 90 +dota_camera_z_interp_speed 100000 +fps_max $DOTA_FPS +engine_no_focus_sleep 0 +fog_enable 0 +snd_mute_losefocus 0 +snd_musicvolume 0 +sv_cheats 1 +dota_launch_custom_game mc_dungeons $DOTA_MAP
for i in $(seq 1 120); do grep -q "bridge online" "$DOTA_LOG" 2>/dev/null && break; sleep 2; done
grep -E "\[mc\] bridge" "$DOTA_LOG" | tail -1

cd "$HERE/mcmod"
rm -f run/logs/latest.log
(./gradlew --no-daemon runClient > run/gradle_run.log 2>&1 &)
for i in $(seq 1 150); do grep -qE "joined the game|has crashed" run/logs/latest.log 2>/dev/null && break; sleep 2; done
grep -E "joined the game|has crashed" run/logs/latest.log | tail -1

#!/bin/sh
# Restart only the Minecraft client and wait until it is in the world.
. "$(dirname "$0")/env.sh"
kill_pids $(mc_pids)
cd "$HERE/mcmod"
for i in $(seq 1 20); do rm -f run/logs/latest.log 2>/dev/null && break; sleep 1; done
(./gradlew --no-daemon runClient > run/gradle_run.log 2>&1 &)
for i in $(seq 1 150); do grep -qE "joined the game|has crashed" run/logs/latest.log 2>/dev/null && break; sleep 2; done
grep -E "joined the game|has crashed" run/logs/latest.log | tail -1

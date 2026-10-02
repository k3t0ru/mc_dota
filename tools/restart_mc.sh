#!/bin/sh
# Restart only the Minecraft dev client (kills the running one by exact PID) and wait until it is in the world.
UM=/c/Users/Roman/.claude/plugins/cache/universal-modder/universal-modder/0.1.0/bin/um
cd "$(dirname "$0")/../mcmod"
for p in $(powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='java.exe'\" | Where-Object { \$_.CommandLine -like '*fabric.dli*' } | ForEach-Object { \$_.ProcessId }"); do
	"$UM" win kill "$p" >/dev/null
done
for i in $(seq 1 20); do rm -f run/logs/latest.log 2>/dev/null && break; sleep 1; done
(./gradlew --no-daemon runClient > run/gradle_run.log 2>&1 &)
for i in $(seq 1 150); do grep -qE "joined the game|has crashed" run/logs/latest.log 2>/dev/null && break; sleep 2; done
grep -E "joined the game|has crashed" run/logs/latest.log | tail -1

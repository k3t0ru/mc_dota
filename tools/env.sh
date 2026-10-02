# Shared paths. Override DOTA_DIR if Dota 2 is installed elsewhere, e.g.  DOTA_DIR="D:/SteamLibrary/steamapps/common/dota 2 beta"
DOTA_DIR=${DOTA_DIR:-"C:/Program Files (x86)/Steam/steamapps/common/dota 2 beta"}
DOTA_EXE="$DOTA_DIR/game/bin/win64/dota2.exe"
DOTA_LOG="$DOTA_DIR/game/dota/console.log"
RC="$DOTA_DIR/game/bin/win64/resourcecompiler.exe"
ADDON_CONTENT="$DOTA_DIR/content/dota_addons/mc_dungeons"
HERE=$(cd "$(dirname "$0")/.." && pwd)

# kill running processes by exact PID (never by name pattern)
kill_pids() { for p in "$@"; do taskkill //PID "$p" //F >/dev/null 2>&1; done; }
mc_pids() { powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='java.exe'\" | Where-Object { \$_.CommandLine -like '*fabric.dli*' } | ForEach-Object { \$_.ProcessId }" | tr -d '\r'; }
dota_pids() { powershell -NoProfile -Command "(Get-Process dota2 -ErrorAction SilentlyContinue).Id" | tr -d '\r'; }
bridge_pids() { powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"name='python.exe'\" | Where-Object { \$_.CommandLine -like '*bridge.py*' } | ForEach-Object { \$_.ProcessId }" | tr -d '\r'; }

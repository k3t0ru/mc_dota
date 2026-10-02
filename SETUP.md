# Minecraft x Dota: setting up on another PC

## What you need
- **Dota 2** in Steam plus the free **Dota 2 Workshop Tools** DLC (Steam → Dota 2 → Properties → DLC).
- **JDK 21**: https://adoptium.net (Temurin 21, the version with "Add to PATH").
- **Python 3** (https://python.org, tick "Add to PATH"), then in a console: `pip install pillow`
- **Git for Windows**: https://git-scm.com (it includes Git Bash; run all commands in it).
- Internet: the first build downloads Minecraft 1.21.11 and Fabric (~300 MB). A Minecraft licence isn't needed to play:
  the game runs in single-player in developer mode.

## Moving the project
1. On the old PC the project is packed into `mc_dungeons.bundle` (all of git history, both versions).
2. Copy the file to the new PC, open Git Bash in the folder where it should live, and run:
   ```
   git clone mc_dungeons.bundle mc_dungeons
   cd mc_dungeons
   git checkout hybrid
   ```
3. If Dota isn't in `C:\Program Files (x86)\Steam\...`, set the path first:
   `export DOTA_DIR="D:/SteamLibrary/steamapps/common/dota 2 beta"`
4. One-time setup (10-15 minutes): `sh tools/setup.sh`
5. In Dota (video settings): **windowed mode, 1600×900**, and turn off "Minimize on focus loss".

## Running
```
sh tools/dev_launch.sh
```
It closes the old Dota/Minecraft, starts the bridge, Dota and Minecraft. Click the Dota picture and control
passes to Minecraft (WASD, mouse, E for inventory). Restart only Minecraft: `sh tools/restart_mc.sh`.

## Versions
- `git checkout hybrid`: Dota draws the blocks (current).
- `git checkout overlay-v1`: Minecraft draws everything on top of Dota (the first version).
After switching: `sh tools/build_all.sh`, then `sh tools/dev_launch.sh`.

## Notes
- Block textures are taken from Minecraft on that same PC and are not stored in the project (they are Mojang's files).
- Dota is played only in a local lobby with cheats (`sv_cheats 1`), never on official servers.

# MODLOG: Minecraft x Dota (custom game)

## Goal
An ARPG custom game in Dota 2 in the spirit of Minecraft Dungeons: Dota heroes plus Steve, Minecraft mechanics, progression.
Co-op 1–4. Slice 1 = Steve + mining/crafting.

## Route
Official Dota 2 custom game (Lua VScript + KV + Panorama). No client modding (VAC, online game).
- Dota: `C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta`
- Addon source: `C:\p\projects\New folder\mc_dungeons` → junction `game\dota_addons\mc_dungeons`
  (remove: `Remove-Item` on the junction only; the source stays)
- Workshop Tools DLC: NOT installed at start (2026-10-02), user is installing it. Without it: no own map, Panorama, or models.

## Facts
- Map: a copy of `hero_demo\maps\hero_demo_main.vpk` (Valve file, gitignored, never ship it). Replace with our own map in Hammer.
- Steve = override of `npc_dota_hero_kunkka` (Kunkka model as placeholder). Name changed via the `npc_dota_hero_kunkka` token.
- Blocks = `npc_dota_creature` on team BADGUYS, HULL_HUGE (80) → adjacent blocks on a 128 grid form a wall.
- Ore = one rock model `models/props_rock/riveredge_rock006a.vmdl` + SetRenderColor. Log = `crate_drop_crate.vmdl`.
- Mining: DamageFilter replaces damage to a block with pickaxe power; tier too low → 0. Steve ×2.
- Crafting: every hero gets their own crafting table (unit), recipes = its abilities (`abilities/mc_craft.lua`).
- Night (native Dota day/night cycle): zombies/skeletons near heroes; at dawn they "burn" (ForceKill).
- Model list: `uvx vpk -l game/dota/pak01_dir.vpk` (dump in the session scratchpad).
- Localization: `python tools/gen_lang.py` → `resource/addon_{english,russian}.txt`.

## Launch (test)
`dota2.exe -novid -console -condebug +dota_launch_custom_game mc_dungeons hero_demo_main`
Log: `game/dota/console.log`, look for `[mc] loaded` and `[mc] world blocks:`.

## Status / next
- [ ] First launch: check KV loading, block spawning, mining, crafting
- [ ] Workshop Tools: own map (biomes, dungeon), Panorama (crafting UI, hotbar), Steve model (blocky)
- [ ] Furnace/smelting, creeper, enchanting, emeralds, hub/camp, saves (between sessions)

## 2026-10-02: test run 1 (results)
- Works: Lua loads, Steve (Kunkka override) spawns, 140 blocks, mining a log → Log item, chat -give (sv_cheats 1 before launch).
- Bug: npc_spawned fires while the hero is at (0,0,0) → table/world were at the map centre. Fixed (SetContextThink 1 frame); NOT re-verified.
- Ward relationship does NOT stop hero auto-attack on blocks → blocks moved to DOTA_TEAM_NEUTRALS (not verified).
- hero_demo_main = a full Dota map (lanes/towers). Needs our own map.
- Workshop Tools installed (content/ appeared).

## Idea from the user: asymmetric PvP
Steve team in real Minecraft (first person) vs Dota heroes (top-down), seeing each other.
Planned route (passthrough via official APIs, no client modding):
Dota custom game (Lua, CreateHTTPRequestScriptVM) ↔ local bridge ↔ Paper plugin on a Minecraft server.
Steve = proxy unit in Dota; a Dota hero = an entity in MC; damage/blocks are synced as events.
Caveat: Minecraft is installed via TLauncher; the Minecraft side needs a licensed Java account.
The "Minecraft in Elden Ring" method was never published (only chasm's description of passthrough).

## 2026-10-02: MC ⇄ Dota bridge (works)
- Vanilla server 1.21.11 (Java 21; 26.3 needs Java 25) in `mc_server/` (gitignored), online-mode, RCON 127.0.0.1:25575.
  Start: `cd mc_server && java -Xmx2G -jar server.jar nogui`. The user accepted the EULA.
- Bridge: `python bridge/bridge.py` (HTTP 127.0.0.1:27100/sync, text lines). `MC_FAKE_STEVE=1`: a fake Steve walking in a circle.
- Verified: FakeSteve → unit in Dota moves; `-createhero axe` → a husk named "axe" in MC follows him;
  `damage` of 20 in MC → −200 HP for Axe in Dota.
- Lessons: (1) every Dota script file has its own env → share globals via `_G` (otherwise MC=nil in other files);
  (2) no `debug` in the sandbox → xpcall(debug.traceback) gives "error in error handling", use pcall;
  (3) thinks: timers live on an info_target, wrapped in safe(); (4) peaceful forbids summoning monsters → difficulty easy.
- Not verified: a real MC client (needs a licensed account), Dota damage → `damage <player>` in MC.
- Next: block sync (Dota 128 = 2×2 MC blocks), hero/Steve models (resource pack + blocky Steve), our own arena map.

## 2026-10-02: architecture (user's decision) + camera
- The Steve player has 2 clients: Dota = main screen, Minecraft computes all its own logic and renders from Dota's camera
  without sky; its picture (blocks, hand, UI) is overlaid on Dota with a transparent window (NO injection into Dota, VAC).
  Pattern = Minecraft×GTA V passthrough (github rehan-remade/universal-modder examples/minecraft-gta5-passthrough), host = Dota.
- Camera: Panorama GameUI.SetCameraPitchMin/Max + SetCameraDistance + SetCameraLookAtPositionHeightOffset + SetCameraTarget work.
  pitch 5 / dist 150 / h 150 = over-the-shoulder with horizon. pitch 0 / dist 50 = inside the model (hide the hero for 1st person).
- New Panorama files are visible only after RESTARTING the dota2.exe process (models — after a map restart).
- Fast start: in cheat mode ForceHero(Steve) + PreGame 0, SetCustomGameSetupAutoLaunchDelay(0): map → hero in 2 s.
  Launch: dota2.exe -novid -console -condebug -windowed -noborder -w 1600 -h 900 +sv_cheats 1 +dota_launch_custom_game mc_dungeons hero_demo_main

## 2026-10-02: Fabric mod mcmod/ (Minecraft overlay over Dota) — WORKS
- Template fabric-example-mod branch 1.21.11; Loom 1.18 needs Java 25 → plugin id 'fabric-loom' 1.14.10 (Java 21).
  Build: `cd mcmod && ./gradlew --no-daemon build`, run: `runClient` (straight into run/saves/mcdota = a copy of the server world).
- Composition: GLFW_TRANSPARENT_FRAMEBUFFER and a colour-keyed GL window STAY OPAQUE on Intel UHD (GL is presented past DWM).
  Working approach: Minecraft clears the frame to magenta (no sky pass), glReadPixels before blitToScreen →
  a separate WS_EX_LAYERED|TRANSPARENT|TOPMOST|NOACTIVATE window (UpdateLayeredWindow, per-pixel alpha) on top of
  the "Dota 2" window (FindWindow + GetWindowRect every second), nearest upscale 1920x1080 → Dota size.
  The MC window itself is borderless at x=-20000: it keeps focus and input.
- Gotchas: @ModifyArg on clearColorAndDepthTextures with method="*" also caught the entity-outline clear (argb 0) → the whole
  frame went magenta; filter argb!=0. Vignette darkens the key to (246,0,246) → tolerance. glfwSetWindowSize inside
  the Window constructor → NPE (resize before Minecraft.window exists) → do it in CLIENT_STARTED.
  First launch shows the accessibility screen: options.txt onboardAccessibility:false. pauseOnLostFocus:false.
- Screen 3840x2160, Dota is stretched to the whole screen. With the monitor off WGC/ddagrab give no frames — F2 in MC works.
  Full-desktop capture: ffmpeg -f lavfi -i "ddagrab=0:framerate=5,hwdownload,format=bgra" -frames:v 1 out.png
- Next: camera sync MC→Dota (Panorama polls the bridge), empty MC world (void + barriers along Dota's terrain), Dota camera = MC eye.

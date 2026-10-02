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

## 2026-10-02 17:20: first person over Dota WORKS (screenshot p3)
- Panorama: `$.AsyncWebRequest has been removed` → the camera goes MC → UDP → bridge → reply to Lua /sync → CustomGameEvent "mc_cam" → Panorama.
- Dota pitch <= 0 behaves badly → clamp to 5 (MIN_PITCH in bridge). Can't look up.
- Dota video.txt (userdata/491223219/570/local/cfg): fullscreen_min_on_focus_loss 1→0 (with the user's permission; backup
  ~/.universal-modder/backups/dota-cfg/20261002-171041.zip and video.txt.bak-mcdota). Otherwise Dota minimizes when MC is focused.
- Mouse: GLFW can't hold the cursor in an off-screen window → grabOrReleaseMouse cancelled, MouseInput reads GetCursorPos from the
  centre of Dota (anchor = actual position after SetCursorPos, otherwise DPI virtualisation → endless spinning), buttons via
  GetAsyncKeyState → KeyMapping.set/click. Focus: overlay NOACTIVATE; if Dota/overlay is foreground → Alt tap + SetForegroundWindow(MC).
- MC ground → barrier (Arena.java / bridge), radius 160, forceload. renderDistance 8.
- Scripts: tools/dev_launch.sh (Dota + MC), tools/restart_mc.sh.
- PROBLEM: the dev client plays single-player, the bridge talks to the dedicated server over RCON → MC players/stand-ins don't connect.
  Next: the mod itself (integrated server) exchanges with the bridge (blocks, Dota hero stand-ins, damage), 1 MC block = 64 Dota units.

## 2026-10-02 17:30: playable prototype (single-player MC + Dota)
- bridge.py = a plain relay (no RCON): Dota /sync, mod /mc, camera UDP. Dedicated server no longer needed for dev.
- Dota: GRID 64 aligned to the anchor (MC:CellOf/CellPos), MC.cells registry, blocks ModelScale 0.5 / HULL_HERO.
  Dota blocks → "block" → setblock in MC; MC block changes (LevelMixin on Level.setBlock, y -60..-40) → mcblock/mcbreak in Dota.
- Steve = the Dota hero STEVE, driven by "steve" from MC (SetAbsOrigin), AddNoDraw (camera inside him), HP mirrors MC.
- Dota heroes → invisible husks (tag dota_<id>, 1024 hp) in MC; health drop → hit → ApplyDamage (×10). Dota damage to Steve → dmg → /damage @p.
- Verified in screenshots: Dota blocks show up as MC blocks, the camera follows yaw and pitch. NOT verified: breaking/placing/hits/damage.

## 2026-10-02 18:07: user feedback fixed
- Lag: Dota video.txt fullscreen 1→0 (1600x900 window, with permission) → overlay 1:1 without 4K upscaling.
- Can't look up: Dota with negative pitch shows the ground → Steve's pitch clamped to >= 3 (MouseInput.MIN_PITCH = bridge MIN_PITCH).
- "Camera floats": SetCameraTargetPosition lerp 0 = creeping → 1; + launch with +dota_camera_edgemove 0 +dota_camera_speed 0 +dota_camera_lock 0
  (convar names from strings in client.dll; they may get saved into the user's Dota config).
- Couldn't walk: (1) WASD went to the Claude app — a click on the overlay now hands focus to MC; (2) thousands of blocks
  accumulated in the MC world from old Dota runs. The world is now EMPTY: level.dat superflat = 4×barrier, regions wiped, Dota generates
  no blocks (GenerateWorld removed), "reset" on Dota start clears ±112 (fill fails on unloaded chunks).
- No rain: weather clear + doWeatherCycle/advance_weather false + addWeatherPass cancelled. Cursor: ShowCursor(false) in the overlay thread.
- Verified: walking 5.2 blocks in 1.2 s, placing cobblestone (screenshot b1). Not verified: blocks reaching Dota, hits, damage.

## 2026-10-02 18:30: camera/scale/terrain pass
- SCALE/GRID 96 (Steve hero-sized), block ModelScale 0.75, SetHullRadius(36) so Dota heroes can't squeeze between blocks.
- Terrain: Dota samples ±40 cells → "h x z y" (+3 where GridNav isn't traversable/trees) → MC raises/lowers the barrier floor.
- Stand-ins for ALL units within 2500 of Steve (creeps too), with height; invisibility via /effect (the SNBT effect didn't stick).
- FOV: Dota +dota_camera_fov_min/max 90 (horizontal 4:3) ↔ MC fov 74 vertical, fovEffectScale 0.
- Camera lag measured (Date.now in Panorama vs MC millis): median ~95 ms, 35-170 ms jitter = the "floating".
  Fix: synchronized playback — Panorama shows the pose from PLAYBACK_MS=150 ago (interpolated), the overlay shows MC frames 125 ms late (ring of 16).
- "Floats right after loading" = Steve spawned next to creeps/towers, Dota damage → knockback + hurt tilt in MC.
  Fix: tp to 0,0 on join, knockback_resistance 1, damageTiltStrength 0, bobView off, heal on join.
- Perf: overlay 54-57 fps, MC 56-59 fps; the bottleneck is Dota on Intel UHD (~37 fps).

## 2026-10-02 18:57: cameras matched (measured, not by eye)
- Panorama probe: GameUI.GetCameraPosition/GetCameraLookAtPosition + Game.WorldToScreenX/Y.
  * "floating": SetCameraTargetPosition(pos, lerp) — lerp is a transition time; called every frame → the camera crept along
    with ~1 s smoothing (at lagged the target by 60-70 units). lerp 0.001 → at == the target exactly.
  * Dota's focal at 1600x900 = 692 px = 66° vertical → MC fov 66 (was 74). Yaw/pitch/dist/eye height matched exactly.
- Dota cube model was half underground: OBJ is Y-up, ModelDoc rotated it. gen_blocks writes v x z -y.
- Calibration (tools/calib.sh, CALIBRATE=true in Lua): MC blocks and Dota cubes match to the pixel at rest.
- Overlay delay in motion: sweep 125/175/225/275 → 150 ms. Live knob: mcmod/run/mcdota_delay.txt.
- Invisible walls removed (trees/GridNav made walls almost everywhere), autojump off (user's request), creep loot kept.
- Verified: 15 stand-ins (creeps, Roshan); /damage 10 on Roshan's stand-in → −57 HP in Dota.

## 2026-10-02 20:25: diggable ground, half-block terrain, occlusion via magenta
- World = superflat bedrock 1 / stone 59 / dirt 3 / podzol 1 → feet on y 0 (MC_FLOOR = GROUND_Y = 0).
- Magenta textures in the mod's resources: podzol_top/side, mud_bricks (slab = half step). The overlay turns magenta (with
  shading tolerance r,b>90 g<40) into holes → Dota's ground is visible, but it still occludes MC blocks behind hills.
  Husk (stand-ins) is magenta too → Dota units cut through MC blocks in front of them. Fog off (FogRenderer.toggleFog),
  time locked to noon (night darkens the magenta).
- Terrain: "h x z hh" in half blocks, R=64; garbage height at the map edge (|dz|>1500) → 0 (otherwise 1261 commands "out of this world").
- Autojump on, step_height NOT raised (user's request). No loot from stand-ins; Steve's kills → "xp" → /xp add (DeathXP/10).
- Verified: no terrain errors, clean Dota ground under MC, digging down (dirt shaft, 4 dirt in the inventory).

## 2026-10-02 20:38: user screenshots (orange edges, pink silhouettes, labels, outline, lowland height)
- Orange edges = dirt in the side walls where Dota's ground drops. Now "h x z hh low": magenta skin down to the lowest neighbour.
- Black triangles = ambient occlusion on magenta → AO off; hole() widened to dark magenta (g*3<r, |r-b|<=max(24,r/4)).
- Magenta stand-ins came out pink (mob lighting) and shaky → back to invisible husks (/effect), no CustomName (there were labels),
  husk texture override removed. Old stand-ins from past sessions are killed on join/reset (they were visible).
- No outline on podzol/mud_brick_slab (OutlineMixin on LevelRenderer.extractBlockOutline).
- "Higher than the floor in lowlands / up first, then down off a cliff": Dota measures the height offset from its smoothed
  "camera ground". Fix: dota_camera_z_interp_speed 100000 + feedback in Panorama (zFix += (wanted - GetCameraLookAtPosition z)*0.5).
  Measured: want z == fact; in the lowland (8,13) feet on -1.5 (-3 half blocks), eye 139 above Dota's ground (155 - rounding).

## 2026-10-02 20:48: respawn + dig visibility
- Death screen needs a GUI mouse → doImmediateRespawn/immediate_respawn + setworldspawn/spawnpoint 0 0 0; AFTER_RESPAWN re-applies
  knockback_resistance (a respawn resets attributes). Verified: /kill → straight back at 0.5 0 0.5.
- Top layer: podzol with ONLY the top magenta (podzol_side is vanilla again) → a hole's walls are real dirt (verified on screen).
  Exposed walls (raised columns, a lower neighbour) = mud_bricks, magenta on every face → Dota's slope shows through.
- Gotcha: WinDrive "type" with the user's Russian layout turns commands into Cyrillic — test with mouse/keys, not chat.

## 2026-10-02 21:12: jitter, 360, HUD, keepInventory, map edge
- Jitter: one stamp per MC frame (pose and picture); Panorama shows EXACTLY the pose of a frame (newest with t <= now-180),
  no interpolation. Overlay delay sweep 180/210/240/270 → 270 (Dota lags ~90 ms more at 30 fps). Both games fps 30.
- 360: Steve's pitch is no longer clamped; Dota stays at MIN_PITCH (looking up in Dota is impossible).
- Dota HUD: GameUI.SetDefaultUIEnabled(all DotaDefaultUIElement_t, false).
- keepInventory/keep_inventory true.
- Map edge: GetWorldMin/MaxX/Y → cells; outside the map / garbage height → "void" (column of air down to -64 = falling out);
  worldborder = 2R+1 (R = map + 6). The map is huge (cells x -149..192) → terrain is built by chunk: columns of unloaded
  chunks wait in pending, ServerChunkEvents.CHUNK_LOAD → ready, ≤400 columns per server tick (otherwise MC froze at 0 fps).
  Verified: steady 30 fps; tp past the edge → "fell out of the world" → respawn at 0,0.
- The MC window's layout must be EN for chat tests: WM_INPUTLANGCHANGEREQUEST to the MC window only.

## 2026-10-02 22:05: HYBRID (branch hybrid; old version = tag overlay-v1, rollback: git checkout overlay-v1 && sh tools/build_all.sh)
- Dota draws Minecraft's blocks: every "mcblock" → prop_dynamic (models/mc/<kind>.vmdl, scale GRID/128) at
  anchor + ((x+.5)*96, -(z+.5)*96, y*96); the bottom 2 levels also get the invisible collision unit (as before).
- Minecraft doesn't draw them: RenderSectionRegion.getBlockState returns AIR for Hybrid.drawnByDota (non-terrain,
  y >= column surface) — so neighbours' faces aren't culled either. (A WrapOperation on renderBatched didn't fire: Fabric's
  Indigo replaces that call.) The magenta ground is emissiveRendering (otherwise black under a block = no light).
- Overlay delay 0 (only hand/HUD/UI), Panorama PLAYBACK_MS 0 (the newest pose).
- Textures: tools/gen_blocks.py takes Minecraft's textures from the local jar (~/.gradle/caches/fabric-loom/*/minecraft-client.jar),
  per face (top/side/bottom: log rings/bark, crafting table). PNGs are gitignored — Mojang files, never commit/publish.

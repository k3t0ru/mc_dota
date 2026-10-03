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

## 2026-10-02 22:45: hybrid round 2 (user video)
- Inventory/crafting with the mouse: when a Screen is open, MouseInput feeds MouseHandler.onMove/onButton (Invoker) with the cursor
  over Dota's window; the overlay shows an arrow cursor. Verified: logs → crafting grid → 4 planks.
  GOTCHA for tests: python must be DPI-aware (SetProcessDpiAwareness(2)), otherwise SetCursorPos misses.
- Focus: any LMB/RMB press over Dota's window → Minecraft gets focus (STATIC overlay doesn't always get WM_LBUTTONDOWN).
- Cracks: ClientLevel.destroyBlockProgress (own player) → "crack x y z stage" → Dota prop crack_<n>.vmdl (alpha-test,
  destroy_stage_N from the local MC jar), 1.02× over the block. Verified on screen.
- Allies: a "hit" on a teammate only works below 50% HP (deny); no XP for kills of your own team.
- Look-up limit returned (MIN_PITCH 3): above the horizon Dota has nothing to show anyway.
- Camera height jerking on high/low ground: offset = wanted - (Dota's ground = lookAt.z - last offset), with no slow
  feedback loop. Verified: want z == actual z while walking.

## 2026-10-02 23:10: rollback of prediction, portability, Roshan
- Camera prediction rolled back (git revert) — the user found it worse. Dota fps_max 60 stays.
- Roshan/Tormentor died at start: stand-ins fell into the void / suffocated → "hit" with all their HP. Now NoGravity
  and only damage whose getLastDamageSource().getEntity() is a Player counts. Verified: Roshan 6130/6130.
- Portability: tools/env.sh (DOTA_DIR, kill by PID via taskkill, no um), setup.sh (junctions, map, gradle, world/options from
  tools/template, assets), SETUP.md. Transfer: git bundle mc_dungeons.bundle --all.

## 2026-10-03 00:25: new PC (RTX 3060 Ti, 1920x1080 screen), camera pose rate, noon
- Set up from the bundle per SETUP.md: Dota in D:/SteamLibrary (DOTA_DIR), default java is 24 → run with JAVA_HOME=jdk-21.0.12.
- Resolution: tools/env.sh DOTA_SIZE (default 1920x1080) → Dota -w/-h and Minecraft render size (-Dmcdota.size via build.gradle).
- Dota ran at 40 fps: engine_no_focus_sleep 20 in the user's config (Minecraft holds focus) → launch with +engine_no_focus_sleep 0,
  +fps_max $DOTA_FPS (default 0). Minecraft fps from MC_FPS (default 60; was hard 30). Result: Dota 250-400 fps.
- Camera jerk: Lua waited for each /sync answer → only ~10 poses/s reached Panorama. Now one request per tick, up to 4 in flight,
  stale answers don't move Steve → 30 poses/s, lag median 75 → 35 ms. Panorama interpolates poses by Minecraft stamp with an
  auto delay (90th pct of arrival lag + 8 ms, ~70 ms). "[mc] smooth" log = evenness per 50 ms bucket; synthetic 90°/s spin: 0.11.
- Blue blocks = Dota night lighting (+ cyan fog sky). Dota locked to noon (SetDaynightCycleDisabled), +fog_enable 0.
  unlit.vfx for blocks made them INVISIBLE (reverted to global_lit_simple).
- Gotcha: "Cannot set convar ..., missing required FCVAR flag" on the command line is harmless (fps_max still applied).

## 2026-10-03 01:10: progression (emeralds, traders), denies, towers, void, walking on blocks
- BUG (big): bridge_pids looked for python.exe, but here python runs as python3.11.exe (Store build) → every launch
  started ANOTHER bridge (16 were running), and Windows' allow_reuse_address let them all bind :27100 → requests spread
  over different bridges (Dota's lines to one, Minecraft polled another; lost loot). Fixed: match python%.exe,
  allow_reuse_address = False (a second copy now fails to start).
- BUG: Lua modifiers were linked only in addon_game_mode.lua (server VM) → client "unknown modifier type". Now addon_init.lua.
- BUG: void never appeared: queued column builds ran after their chunk unloaded again ("That position is not loaded") and were
  lost. Now they wait for the chunk again. The map edge IS the garbage-height test (rays: rim at +256, then -16512);
  a GridNav flood fill + margin cut the map short (reverted). Terrain columns now restore bedrock/stone/dirt (were voided).
- Progression (Progress.java): per Dota match; start = wooden sword/pickaxe, bread, planks. Steve's kills (Lua MC:LootFor)
  → "loot <emeralds> <food> <n>": emeralds = gold bounty / EMERALD_GOLD (25); creeps bread 50%, neutrals beef, heroes and
  towers golden apple. Steve's Dota level → "lvl" → MC max_health 20 + (lvl-1).
- Traders: Dota draws them (tools/gen_villager.py: VillagerModel boxes + jar textures, alpha-tested), positions from Lua
  TRADERS → "trader x z prof" (resent every 5 s); Minecraft keeps invisible villagers there (trading UI). Upgrades cost
  emeralds + the previous tier item (buyB). Offers in Progress.java.
- Overlay delay follows Panorama's camera playback delay ("delay" via mc_delay event; +5 ms) → hand/arrows/items no longer
  drift. run/mcdota_delay.txt (old PC: "0") overrides it → renamed to .bak.
- Towers/buildings get stand-ins (scale attribute 2.5-3). Shield: "dmg <amt> <attackerid>" → damage ... by <stand-in>.
- Denies like Dota: creeps < 50%, towers < 10%, heroes never; "!" particle, no loot/xp.
- Walking on blocks: a column with only a ground-level block = walkable (modifier_mc_block stack 1 → NO_UNIT_COLLISION),
  units in it get modifier_mc_lift (VISUAL_Z_DELTA 96) and their stand-in y+1. 2 high = wall. No staircases.
- Test trick: POST "hit <id> <n>" / "set x y z kind" to /mc fakes Minecraft events (an empty POST lists hero lines, but
  it also eats queued to_mc lines).

## 2026-10-03 01:30: real Dota map, crafting economy, death penalty, repair, sound
- Map: DOTA_MAP (env.sh, default "dota") = game/dota/maps/dota.vpk copied into maps/ (setup.sh; gitignored maps/*.vpk,
  addoninfo lists both). Secret shop = nearest trigger_shop > 30 cells from the spawn (no API for the shop type);
  on the real map: cell 18,-90. hero_demo_main has a single shop at 22,14.
- Terrain on the big map: the build queue is now per chunk, nearest chunk to the player first ("terrain: N columns ready"
  every 10 s). Half-loaded chunks at the view edge are drawn by the client but not built → podzol SIDE is magenta too
  (was an orange "dirt" strip across the river). Base restore (bedrock/stone/dirt) only if bedrock is missing.
  Routine terrain/void fills no longer log "No blocks were filled".
- Denies: ApplyDamage isn't an attack, so Dota didn't count it (no "!", enemy full XP). Now Steve:PerformAttack on the ally,
  DamageFilter swaps in the Minecraft hit (steve.mc_attack).
- Economy = crafting: villagers sell MATERIALS (Progress.java): fletcher (logs, string, flint, feathers, leather, iron,
  gunpowder, paper, food), librarian (enchanting), toolsmith (tables; sneak + right click = repair held item for 1/3 of
  its material value x wear), mason (blocks Dota has models for), secret shop (diamonds, netherite + template, elytra,
  totem, pearls, top books). Neutrals drop materials by name (NEUTRAL_LOOT), Roshan = totem + netherite + diamonds.
  Emeralds from gold bounty with the remainder carried over (MC.goldLeft): units differ like in Dota.
- Death: MC death → "died <lost>" (lost = min(carried, 2 + level) emeralds) → Lua kills Steve's hero crediting the last
  attacker (bounty/XP to them), "dead <secs> <lost>" → title; frozen at spawn (adventure, speed/jump 0) until Dota's
  respawn → "respawn".
- Shield: blocked in our code (isBlocking + attacker stand-in within 90° → no damage, shield wear, block sound);
  /damage ... by <stand-in> alone didn't block.
- Arrows from the player: no gravity, gone after 80 ticks (Dota's camera can't look up to lob). Sweep: sweeping_damage_ratio 0.8.
- Sound: Dota muted itself without focus → snd_mute_losefocus 0; Dota music off (snd_musicvolume 0 — persists in the
  user's Dota config!), Minecraft music stays (user's choice).

## 2026-10-03 01:50: user round (sell-back, target bar, denies, traders, ground, sounds)
- Denies gave Dota XP to Steve (the killing attack): XP/gold filters return false while steve.mc_denying.
- Sweep never touches allies: "hit <id> <amt> <direct>", direct = projectile or player.getLastHurtMob() == stand-in.
- Target bar (Target.java): crosshair stand-in -> boss bar "name hp/max", red enemy / green ally / yellow DENY.
  hero lines carry a last field: 1 = Steve's team.
- Sell-back trades (item -> emeralds, ~half price): fletcher buys jungle materials, secret shop buys diamonds/netherite/totem.
  Loot message: only "+N emeralds, +n item" (no gold).
- Traders on the real map stood inside the fountain: base row now 9+ cells from the spawn toward the world origin (map
  centre), first traversable cell, facing the spawn.
- Blocks floated: Dota drew them at the absolute MC height, but MC terrain is half-block steps. MC:BlockPos draws them
  from Dota's real ground under the cell, counted from the first standable level (ceil(halfh/2)).
- Strip on the horizon: columns next to the void had real dirt/stone sides; void neighbours count as bottomless for the skin.
- Footsteps: podzol = SoundType.GRAVEL, skin = MUD_BRICKS → sounds.json maps their step events to grass steps.

## 2026-10-03 11:55: fountain market, Aegis totem, dev command channel, Lua syntax check
- Market: two stalls (after Dio Rods' "Market Stall": log posts, plank counter, spruce frame, striped wool awning with
  side flaps), red (fletcher + mason) and blue (librarian + toolsmith), facing each other across an aisle. Placed by a
  search: nearest centre (<= 12 cells from our fountain, both grid orientations) where both stalls and the aisle are
  GridNav-walkable, no trees, off the spawn. Real map, Radiant: centre -4,-3, aisle along MC x (the fountain is in a
  walled corner: "both sides of it" put a stall on cliffs). Dota's fountain shopkeeper (ent_dota_shop) hidden (EF_NODRAW).
- Dota-built blocks (MC:PlaceBlock): Minecraft gets them queued behind the column's terrain build, Dota draws them and
  their collision units are invulnerable (the fountain shot them: neutral team). Barriers around the fountain basin
  (MC only) keep the player out of the Dota model.
- Block props drawn at the absolute Minecraft height again (ground-relative broke roofs into steps).
- Villager model looks -X at yaw 0 (checked on screen); traders turn toward Steve within 10 cells (max 80° off counter).
- Totem of undying: only from Roshan (not sold); TotemMixin: full health + food + saturation when it saves you (Aegis).
- Dev channel: POST /cmd to the bridge = Minecraft commands (tp/gamemode/give) for testing; screenshots + tp views.
- tools/check_lua.py (lupa): dev_launch/build_assets refuse to run with a Lua syntax error. A broken addon_game_mode.lua
  loads NOTHING (silently): hero pick 90 s, strategy, showcase came back, no bridge. Not the real map's fault.
- Gotcha: never pipe dev_launch.sh (| tail): Dota inherits the pipe, the command waits until Dota exits.

## 2026-10-03 12:20: market by hand, aim-based melee, horizon strip, tick budget
- Market (real map, Radiant): red stall where Dota's shopkeeper stood, nudged (rel 1,2), counter toward the map centre;
  blue stall perpendicular (rel 8,8), counter toward -V; Steve spawns/respawns on the square between (rel 5,4) —
  "spawnat" from Lua, Progress.spawnAt/joined (no more fixed MC 0,0). Secret trader replaces Dota's secret
  shopkeeper (hidden), at his exact spot and facing. Barriers around the fountain skip stall cells (a trader inside a
  barrier could not be clicked). Traders stand on top of slabs (half-block y).
- Melee: AttackMixin sends "swing <dmg>" (attack cooldown, sharpness, crit) on every left click; it lands on the unit
  Panorama finds under the crosshair (GameUI.FindScreenEntities at the centre and 4 points around it, "mc_aim"),
  kept 0.3 s, within MELEE_REACH 3.5 blocks + hull. Melee hits on stand-ins are ignored; arrows/sweeps still use them.
  The target boss bar is gone. Verified: swing 6 on a test creep at 170 units.
- Stand-ins removed with discard() (no death puff, no dropped loot), after 1 s unlisted.
- Horizon strip: underground air in chunks the client doesn't have counts as stone when meshing (SectionCompilerMixin).
- Twitching while walking: terrain builds were 400 columns/tick (100+ ms stalls in new chunks) → 6 ms per tick budget;
  "server tick" in the terrain log line (1.5 ms with an 85k backlog). Traders turn smoothly (eased).
- Testing: bridge POST /dota "testunit <unit> <dist>" (stunned unit in front of Steve) or any console command.
  Don't test enemies near our fountain or towers: they kill it in seconds.

## 2026-10-03 12:35: swing damage, no sweep on denies
- BUG: the swing's damage came from the CLIENT's ATTACK_DAMAGE, which is a bare fist (1.0): equipment attribute
  modifiers live on the server only. Now the client sends cooldown + crit, the integrated server computes like
  Player.attack: weapon attribute * (0.2 + 0.8 s^2) (* 1.5 crit) + enchantments (EnchantmentHelper.modifyDamage) * s.
  Verified with a synthesized click: iron sword = 6.0. (Sweeps came out stronger than the main hit because of this.)
- Denies: a swing at an ally suppresses splash ("hit ... 0") for 0.4 s; Lua scans the batch for the swing first.
- Testing: tools for clicks — SendInput/mouse_event left clicks over Dota's window reach MouseInput (first one focuses).

## 2026-10-03 12:45: mouse wheel, emerald popup
- Mouse wheel did nothing: Windows gives it to the window under the cursor (Dota's; Minecraft's is off screen) and
  Dota ignores input while not in front (Panorama's SetMouseCallback never fired either). MouseWheel.java: a
  WH_MOUSE_LL hook (JNA, own message-loop thread) swallows the wheel while Minecraft is in front with no menu and
  switches the hotbar like Minecraft's scroll. Verified with synthesized wheel notches.
- Kill popup: Steve gets no Dota gold at all (gold filter; he pays in emeralds), so no yellow "+45"; MC:Popup shows
  the emeralds as msg_gold particle tinted Minecraft green (55FF55) at the corpse, 40 units up (160 rose out of a
  first-person view). Other loot only on the actionbar. Verified on screen.

## 2026-10-03 13:25: smoothness (measured), TNT, no digging, test kit
- Smoothness, measured with synthetic input (scratchpad tools: motion.py = precise mouse/W input, measure.sh = Panorama
  "[mc] smooth" lines, bridge MCDOTA_POSELOG=<file> = raw pose stream, poses.py = its evenness):
  1. Cursor was read at the END of a frame but applied by Minecraft in the NEXT one, stamped with that frame → turn per
     stamped ms varied 32% for a steady mouse. Now read right before MouseHandler.handleAccumulatedMovement, stamp there.
  2. Read+SetCursorPos each frame raced with moves in between → some frames got double turns. Now the low-level hook
     (MouseWheel) adds up WM_MOUSEMOVE and swallows it (cursor stays at Dota's centre); MouseInput takes the sum per
     frame. Safety: capture only while MC renews it every frame (<250 ms) and MC's window is in front.
  3. Pose stamps in fractional ms (nanoTime aligned to wall clock), end to end.
  4. Panorama: a late pose no longer freezes then jumps: extrapolate from the last two up to 60 ms; delay = 95th pct.
  Result (steady motion): raw stream spread 32% → 12%; Panorama camera unevenness 0.25–0.40 → 0.04–0.05.
  Also: MC render/simulation distance 5 (MC only draws hand/HUD/entities; 8 chunks cost Dota ~40% of its frames),
  overlay readback through two PBOs (no GPU wait). MC at 120 fps: overlay stuck at 59, Dota lost frames → keep 60.
  Dota fps cap 144 vs uncapped: no better. Lua tick costs 0.5 ms avg (not the frame spikes); Dota frame-time p95 ~12 ms
  with MC running vs ~9 without (the overlay window + MC share the GPU).
- Villagers don't turn toward Steve any more (prop angles go out at 30 Hz unsmoothed: they shook).
- TNT (6) + flint and steel (2) at the fletcher. Explosions are splash (no denies); ExplosionMixin spares the ground and
  Dota-built blocks (Sync.protectedBlocks from "block" lines). Verified: owned primed TNT → 22–25 HP to stand-ins.
- No digging the ground: Hybrid.ground (terrain skin or below the column surface) → AttackBlockCallback FAIL,
  PlayerBlockBreakEvents.BEFORE false; explosions skip it too.
- Coin sound on Steve's kills with emeralds (General.Coins). Test kit: TEST_EMERALDS = 192 at every match start.
- TESTME.md: what the user still has to check by hand.

## 2026-10-03 14:35: field of view — not possible (Dota refuses it)
- Wider FOV asked. Dota's camera FOV can't be changed by a custom game: dota_camera_fov_min/max are refused from the
  launch line, Lua SendToConsole and a script-run cfg ("Cannot execute concommand ..., missing required FCVAR flag");
  a startup +exec cfg runs silently but the map load resets it; Panorama has no FOV setter (camera API: distance,
  yaw, pitch, target, height offset only); the player's cfg doesn't store it. The 90 "set" by us was just the default.
  Measured: focal stays 830 px (right100 = 3037 at dist 40) for every value.
- Kept: Panorama measures Dota's focal length every probe (2 s) → "mc_fov" → "mcfov" → Minecraft's fov (66 now), so the
  layers stay matched if anything ever changes it (e.g. another resolution).
- Gotcha: an unattended match ends by itself (~50 min: Dire creeps destroy the base) and Dota returns to the menu.

## 2026-10-03 16:50: user round — all Minecraft blocks in Dota, ground, boss bar, fire, effects
- Every Minecraft block in Dota: tools/gen_mcblocks.py builds a model per Minecraft block model from the jar (elements,
  element rotations, per-face UV + rotation, default UVs, alpha-tested textures, tinted grass/leaves, animated → frame 1;
  no elements → a cube with the particle texture), centred on the block; scripts/vscripts/mc_block_models.lua (MCB)
  maps blockstate variants to model + x/y. Minecraft sends the full state ("set x y z kind solid props"); MC:Variant
  picks the variant, the prop turns by angles (0, -y, x). 1816 models / 1081 textures, compile 13 min once
  (tools/build_mcblocks.sh, in setup.sh); everything gitignored (Mojang-derived). Load time unchanged (~1 min).
  Variants are ordered default-state first (a block placed without a state — the stalls — used axis=x logs).
- Ground mismatch: the origin (MC 0,0) moved with the hero's spawn spot and old terrain stayed in the world. Now the
  origin is our fountain snapped to the grid, and dev_launch wipes the world's region/entities/poi (rebuilt from Dota).
  Measured at 12 spots: eye 139–171 above Dota's ground (ideal 155: the half-block steps' ±24 limit).
- Fire: on half-step columns the terrain's top is a bottom slab, where vanilla fire can't stand → FireMixin lets it;
  Dota draws light non-solid blocks half a block lower there. Non-solid blocks ("set ... solid 0") don't collide/lift.
  Fire/lava/etc. damage on stand-ins counts (splash): verified 300 → 228 HP in 4 s.
- Horizon stripes: terrain side faces were shaded darker magenta (directional shading) → own block models for
  podzol/mud_bricks/slabs with "shade": false. Also mipmaps off. Verified with Minecraft's own F2 frame vs the overlay.
- Swing: crit/sweep flags; Lua deals the sweep (enemies within a block of the target, never on denies) and asks
  Minecraft for crit/sweep particles + sounds on the target's stand-in ("fx"). Minecraft's own sweep hits are dropped.
- Boss bar ("boss"): Roshan while Steve is within 900 of him, else a building Steve hit in the last 5 s. Verified.
- Steve's XP: the XP filter keeps Dota's hero XP from Steve (no level-up sound) and counts it (XP_TABLE → level → max
  health). Kunkka's voice: VoiceFile "". Blocks' Dota units are on Steve's team (our fountain shot them as neutrals),
  buildings never damage blocks. Stand-ins spawn invisible (no zombie flash). Fireworks at the secret shop. Looking up
  allowed while gliding on elytra. 3+ blocks above the ground: flying vision (modifier_mc_highground).
- tools/check_lua.py now also dry-runs addon_game_mode.lua's top level (Dota API stubbed, our globals nil until
  assigned): catches "MC used before MC = {}" — that runtime error had dropped the whole game mode again.

## 2026-10-03 17:45: looking up, XP bar = level, whole map built, fire animation, names, death title
- Looking up: Dota's camera takes a pitch of 360 - x as a real upward camera (a negative pitch is a top-down view).
  Verified: probe projections exact at 340 and 315; a block above lines up with the crosshair at 45 deg up. The bridge
  sends the signed pitch (MIN_PITCH -89), fpcam.js converts it after blending poses (blending 1 -> 359 jerked the camera
  through 180 at the horizon). Minecraft's look-up clamp is gone (MouseInput.MIN_PITCH -89).
- Terrain over the whole map: the anchor is our fountain (a corner), so the old square of +-220 cells left the enemy's
  side unbuilt (Minecraft's flat dirt showed as strips Steve walked into) and the world border cut it. Now the map's box
  (+6 void) and a border centred on it ("border size cx cz"). The superflat's underground is magenta mud bricks
  (template level.dat too): chunks not rebuilt yet show nothing instead of dirt.
- Terrain changes under the surface never reach Dota (they drew hanging dirt blocks); blocks Minecraft draws itself
  (water...) replacing a drawn one: "break". Small floating cubes = dropped items (sand falling onto fire), vanilla.
- Steve's level = Minecraft's XP bar: the number is his level, the bar the way to the next, from the hero XP Dota would
  give (Dota's table, past 30 each level 600 XP dearer than the last: no cap). Enchanting/anvil need the level but don't spend it (put back every 2 s);
  no XP bottles, no vanilla XP for kills. (A separate level boss bar was tried: two levels confused.)
- Fire animates: tools/gen_mcblocks.py makes 8 frame models for fire/soul fire/campfires (<model>__f<k>, MCB_ANIM);
  Lua swaps them 12 times a second. Fire damage on Dota units x3 (~55/s).
- Trader names: text displays over their heads (an invisible mob's own name tag isn't drawn).
- Death: Kill() by the hero himself (void, /kill: no attacker) did nothing -> ForceKill; the respawn time is read a
  frame later (was 0); the title is shown again every second with the countdown until Dota's "respawn".
- After a respawn the hero model showed (Kunkka in blue): AddNoDraw on every move.
- Blocks are neutrals again (on Steve's team, enemy creeps attacked them); blocks within 1500 of a fountain are
  invulnerable (fountains shoot neutrals).
- Alt+Tab: focus goes back to Minecraft only on a click on the picture (Alt+Tab landed on Dota, which handed the focus
  straight back and trapped the cursor); with another app in front the overlay hides.
- New match resets walk speed/jump/title (a session closed while dead left them at 0 in the player's save).

## 2026-10-03 19:25: melee curve, flames at the feet, half-step blocks, clock, buckets
- Melee damage curve (mc_bridge.lua MeleeScale): a full swing does 1.86 * damage^2.44 Dota damage (at least 10 per
  point): wooden sword 4 -> ~55 (a level 1 hero), stone ~94, iron ~147, diamond ~214, netherite ~300, netherite +
  Sharpness V (11) ~650 (Roshan in ~10 s like a 6-slotted level 30 carry). Cooldown and crit keep their share
  (AttackMixin sends the full swing's damage as a 4th field). Verified: one full netherite+S5 swing kills a 550 hp creep.
- Burning stand-ins: flames only around the feet (FlameMixin: invisible non-player entities get a short, narrow
  bounding box in their render state; FlameFeatureRenderer sizes the flame by it). Verified on an invisible husk.
- Blocks on half steps: a full block placed on a terrain slab took y surface+1 with a half-block gap under it, so Dota
  drew it floating. It now takes the slab's place (half sunk into Dota's ground, like Minecraft blocks on a slope), and
  the slab comes back when it's broken (Hybrid.slabAt, Sync.halfStep). Verified: stone and planks sit on the ground.
- Clock (fletcher, 2 emeralds): while one is in the inventory, Dota's game time and day/night top-left, Minecraft
  style (ClockHud via Fabric HudElementRegistry; Lua sends "time <s> <day>"). Verified.
- Water and lava buckets at the fletcher (2 / 4 emeralds).

## 2026-10-03 20:30: whole map visible, unbuilt-chunk walls, shops sell anything, fountain, fire aspect, raw meat
- Whole map visible: Dota's camera far plane cut the world at ~3000 units (black beyond). Launch args
  +r_farz 40000 +dota_camera_zfar_zoomed_in/out 40000 (client convars: SendToConsole can't set them, FCVAR). Units out of
  vision stay hidden by Dota's fog of war. The striped backdrop over the horizon is the map's static edge geometry.
- Invisible walls (Dire T4s, Dire top T1/T2): chunks whose load event never came stayed unbuilt (Minecraft's flat floor
  above Dota's ground = a wall along a chunk edge, x = 128). Every 2 s pending chunks that are loaded get built.
- Stand-ins never drawn on the client (StandInMixin: husks' bodies invisible; the effect arrived a few frames late, so
  a husk flashed in the air now and then). Flames still show (FlameMixin).
- Shops: every item one at a time (bulk only for 1-emerald stacks), no duplicate offers, no buckets, no grindstone.
  Any trader buys anything: on opening the trade screen, offers for what's in the inventory are appended (half the
  price; gear by durability left; +2 emeralds an enchantment level; cheap things in bulk for 1 emerald; each damaged/
  enchanted item its own exact offer). Mouse wheel scrolls menus (the trade list) via MouseHandler.onScroll.
- Fountain: twice a second in its aura 5% health + 1 food (Lua sees modifier_fountain_aura_buff, "fountain").
- Roshan killed by Steve: Dota's drops (Aegis, cheese) removed, the totem comes from Minecraft's loot.
- Neutrals drop raw beef, cooked if they died burning (hit lines from fire carry "fire"; Lua marks mc_burnUntil).
  Fire Aspect works through the swing: "fx burn <id> <s>" sets the stand-in on fire (4 s a level). Flame (bows) sold.
- Blocks into half steps also by clicking the slab's top (UseBlockCallback): pillaring up from a step works.
- Block textures 256 px (UP 16): at 128 Dota's filtering blurred Minecraft's pixels up close.
- Dev: /dota "client <cmd>" (client console), "dumpedge", "testunit <unit> <dist> free" (not stunned).

## 2026-10-03 22:00: camera bob, invulnerable after respawn, sharper textures, high ground at 4
- Picture bobbing while walking (most visible on traders/stalls): Dota's camera takes its height from its own camera
  ground (the target's z is ignored), which stepped with dota_camera_z_interp_speed 100000; our offset shows one frame
  late (measured exactly: set at n, seen at n+1), so every step jerked a frame. Now z_interp_speed 4 (smooth camera
  ground) + the 1-frame feedback + the wanted height glides (0.4 a frame); Lua takes the eye height from Dota's ground
  plus the feet's height over Minecraft's ground (MCBridge:SmoothEye: Minecraft's half steps no longer move it).
  Measured while strafing at the market: camera jerk max 46-81 -> 7-12, mean 1.4-2.1 -> 0.25-0.4.
- Creeps/towers ignored Steve after a respawn (and from the start): modifier_fountain_invulnerability stays on a hero
  moved by SetAbsOrigin (he never "walks out"). Removed when he is 900+ from a fountain. Verified: a tower hits him
  after a death. (Test creeps made with CreateUnitByName have no AI: use towers.)
- Textures: the user's Dota texture quality had r_texture_stream_mip_bias 1 (half size): launch arg 0.
- High-ground vision from 4 blocks up.
- Tried: an unlit sky box around the map (looked like a box; dropped), fow_darkess 0 (no effect). The striped dark
  backdrop over the horizon stays (Dota's far map edge, seen only with the long far plane).
- Dev: /dota "towers", "steveinfo [unit]", "nodraw 0"; fpcam.js logs "[mc] zjitter" every 3 s.
- Fountain: no invulnerability at all (Dota's modifier_fountain_invulnerability removed every move): it only heals/feeds.
- Striped horizon: tried far planes 6000/10000/14000/40000 (stripes in all; gone only at Dota's default ~3000, which
  also hides the far map), fow_unseen 0, ent_fire env_sky/fog Disable: no effect. Kept 40000.
- Minecraft render distance 5 -> 13 chunks (simulation stays 5): Minecraft 59 fps, Dota 185 fps at the market.

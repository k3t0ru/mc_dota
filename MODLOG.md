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

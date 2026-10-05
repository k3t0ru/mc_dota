-- Minecraft x Dota: mining, crafting, night mobs.

-- tier = pickaxe tier needed, hp = hits at power 1, drop = item, xp = hero xp on break, mc = Minecraft block id
BLOCKS = {
	npc_mc_block_log     = { tier = 0, hp = 3,  drop = "item_mc_log",         xp = 5,  mc = "oak_log" },
	npc_mc_block_stone   = { tier = 1, hp = 4,  drop = "item_mc_cobblestone", xp = 5,  mc = "stone" },
	npc_mc_block_cobble  = { tier = 1, hp = 4,  drop = "item_mc_cobblestone", xp = 5,  mc = "cobblestone" },
	npc_mc_block_coal    = { tier = 1, hp = 4,  drop = "item_mc_coal",        xp = 10, mc = "coal_ore" },
	npc_mc_block_iron    = { tier = 2, hp = 6,  drop = "item_mc_iron",        xp = 20, mc = "iron_ore" },
	npc_mc_block_diamond = { tier = 3, hp = 10, drop = "item_mc_diamond",     xp = 50, mc = "diamond_ore" },
}
FROM_MC = {} -- Minecraft block id -> Dota block unit (anything unknown is solid cobblestone)
for name, def in pairs( BLOCKS ) do FROM_MC[ def.mc ] = name end

-- pickaxe item -> { tier, power }
PICKAXES = {
	item_mc_pickaxe_wood    = { 1, 2 },
	item_mc_pickaxe_stone   = { 2, 3 },
	item_mc_pickaxe_iron    = { 3, 4 },
	item_mc_pickaxe_diamond = { 4, 6 },
}

STEVE = "npc_dota_hero_kunkka" -- ponytail: Steve overrides Kunkka's slot; own hero needs a model from Workshop Tools
GRID = 96 -- one Dota block cell = one Minecraft block (so Steve is hero-sized), cells are aligned to MC.anchor
CALIBRATE = false -- true: show Dota's own block cubes so they can be lined up with Minecraft's (camera calibration)
TERRAIN_R = 400 -- max cells from the anchor mirrored into Minecraft (the map's own size ends it first)
MC_FLOOR = 0 -- Minecraft y where feet stand on flat ground (the world is a superflat whose top layer is y -1)

require( "mc_bridge" )
require( "mc_world" ) -- runes, trees, outposts, watchers, lotus pools, twin gates, torch wards
require( "addon_init" ) -- Lua modifiers (the client loads addon_init.lua by itself)
require( "mc_block_models" ) -- MCB: every Minecraft block's variants -> Dota models (tools/gen_mcblocks.py)
pcall( require, "mc_held" ) -- MC_HELD: the items Steve is drawn holding (tools/gen_mobs.py)



function Precache( context )
	PrecacheResource( "particle", "particles/generic_gameplay/illusion_killed.vpcf", context )
	for _, m in ipairs( { "zombie", "skeleton", "spider_jockey", "zombie_gold" } ) do -- (Steve's: below)
		PrecacheResource( "model", "models/mc/mob_" .. m .. ".vmdl", context )
	end
	-- Steve as Dota's players see him: with an elytra or not, each item in his hand (MCBridge:Puppet); hexed: a pig, a chicken
	local models = { "pig", "chicken" }
	for _, e in ipairs( { "steve", "steve_elytra" } ) do
		table.insert( models, e )
		for item in pairs( MC_HELD or {} ) do table.insert( models, e .. "__" .. item ) end
	end
	for _, m in ipairs( models ) do
		PrecacheResource( "model", "models/mc/mob_" .. m .. ".vmdl", context )
		local anims = m:find( "^steve" ) and { "idle", "run", "attack", "sneak_idle", "sneak_run", "fly", "bow" } or { "idle", "run" }
		for _, a in ipairs( anims ) do PrecacheResource( "particle", "particles/mc/steve/" .. m .. "_" .. a .. ".vpcf", context ) end
	end
	PrecacheResource( "model", "models/mc/mob_steve.vmdl", context )
	PrecacheResource( "model", "models/mc/steve_ghost.vmdl", context )
	PrecacheResource( "model", "models/mc/block_ghost.vmdl", context )
	PrecacheUnitByNameSync( "npc_dota_hero_target_dummy", context ) -- (Steve's stand-in, MCBridge:Puppet)
	PrecacheResource( "particle", "particles/units/heroes/hero_earthshaker/earthshaker_aftershock.vpcf", context ) -- a mace's smash
	PrecacheResource( "particle", "particles/units/heroes/hero_brewmaster/brewmaster_cyclone.vpcf", context ) -- a wind charge
	for _, k in ipairs( { "wind_charge", "ender_pearl", "arrow" } ) do -- Steve's projectiles in flight (MCBridge:Projectile)
		PrecacheResource( "particle", "particles/mc/steve/proj_" .. k .. ".vpcf", context )
		PrecacheResource( "model", "models/mc/item_" .. k .. ".vmdl", context )
	end
	PrecacheResource( "model", "models/mc/villager_armorer.vmdl", context ) -- (Dire's secret trader)
	PrecacheResource( "particle", "particles/units/heroes/hero_techies/techies_land_mine_explode.vpcf", context )
	PrecacheResource( "soundfile", "soundevents/game_sounds_heroes/game_sounds_techies.vsndevts", context )
	-- wards (torches): loading them at the first torch froze Dota for ~0.2 s (the camera jerked)
	PrecacheUnitByNameSync( "npc_dota_observer_wards", context )
	PrecacheUnitByNameSync( "npc_dota_sentry_wards", context )
	PrecacheResource( "particle", "particles/items2_fx/teleport_start.vpcf", context )
	local seen = {}
	for _, vs in pairs( MCB ) do
		for _, v in ipairs( vs ) do
			if not seen[ v[2] ] then
				seen[ v[2] ] = true
				PrecacheResource( "model", "models/mcb/" .. v[2] .. ".vmdl", context )
				for k = 1, ( MCB_ANIM[ v[2] ] or 1 ) - 1 do PrecacheResource( "model", "models/mcb/" .. v[2] .. "__f" .. k .. ".vmdl", context ) end
			end
		end
	end
	for _, m in ipairs({
		"models/mc/stone.vmdl", "models/mc/cobblestone.vmdl", "models/mc/log.vmdl", "models/mc/coal_ore.vmdl",
		"models/mc/iron_ore.vmdl", "models/mc/diamond_ore.vmdl", "models/mc/crafting_table.vmdl",
		"models/mc/sky.vmdl", "models/mc/tree_crack_0.vmdl", "models/mc/tree_crack_1.vmdl", "models/mc/tree_crack_2.vmdl",
		"models/mc/tree_crack_3.vmdl", "models/mc/tree_crack_4.vmdl", "models/mc/tree_crack_5.vmdl", "models/mc/tree_crack_6.vmdl",
		"models/mc/tree_crack_7.vmdl", "models/mc/tree_crack_8.vmdl", "models/mc/tree_crack_9.vmdl", "models/mc/dirt.vmdl", "models/mc/sign_fletcher_name.vmdl", "models/mc/sign_fletcher_goods.vmdl",
		"models/mc/sign_mason_name.vmdl", "models/mc/sign_mason_goods.vmdl", "models/mc/sign_librarian_name.vmdl",
		"models/mc/sign_librarian_goods.vmdl", "models/mc/sign_toolsmith_name.vmdl", "models/mc/sign_toolsmith_goods.vmdl",
		"models/mc/sign_secret_1.vmdl", "models/mc/sign_secret_2.vmdl", "models/mc/sign_witch.vmdl", "models/mc/sand.vmdl", "models/mc/planks.vmdl", "models/mc/spruce_planks.vmdl",
		"models/mc/red_wool.vmdl", "models/mc/white_wool.vmdl", "models/mc/blue_wool.vmdl",
		"models/mc/crack_0.vmdl", "models/mc/crack_1.vmdl", "models/mc/crack_2.vmdl", "models/mc/crack_3.vmdl", "models/mc/crack_4.vmdl",
		"models/mc/crack_5.vmdl", "models/mc/crack_6.vmdl", "models/mc/crack_7.vmdl", "models/mc/crack_8.vmdl", "models/mc/crack_9.vmdl",
		"models/mc/villager_fletcher.vmdl", "models/mc/villager_librarian.vmdl", "models/mc/villager_toolsmith.vmdl", "models/mc/villager_weaponsmith.vmdl", "models/mc/villager_mason.vmdl", "models/mc/villager_cleric.vmdl",
		"models/heroes/undying/undying_minion.vmdl",
		"models/creeps/neutral_creeps/n_creep_troll_skeleton/n_creep_skeleton_melee.vmdl",
	}) do PrecacheResource( "model", m, context ) end
	PrecacheResource( "particle", "particles/units/heroes/hero_clinkz/clinkz_base_attack.vpcf", context )
	PrecacheResource( "particle", "particles/msg_fx/msg_gold.vpcf", context )
end

function Activate()
	GameRules.MC = MC
	MC:Init()
end

MC = {}

-- Dota's hero XP table (total XP for each level): Steve's level from the XP he would have got
XP_TABLE = { 0, 240, 640, 1160, 1760, 2440, 3200, 4000, 4900, 5900, 7000, 8200, 9500, 10900, 12400, 14000, 15700, 17500,
	19400, 21400, 23600, 26000, 28600, 31400, 34400, 37600, 41000, 44600, 48400, 52400 }
function MC:XPFor( lvl ) -- total XP for a level
	while not XP_TABLE[ lvl ] do
		local n = #XP_TABLE
		XP_TABLE[ n + 1 ] = XP_TABLE[ n ] + ( XP_TABLE[ n ] - XP_TABLE[ n - 1 ] ) + 600
	end
	return XP_TABLE[ lvl ]
end
function MC:SteveXP( xp )
	MC.steveXPTotal = ( MC.steveXPTotal or 0 ) + ( xp or 0 )
	local lvl = 1
	-- no cap, like Minecraft: past Dota's 30 each level costs 600 more than the one before
	while MC.steveXPTotal >= MC:XPFor( lvl + 1 ) do lvl = lvl + 1 end
	MC.steveLevel = lvl
end

-- a building's name for the boss bar: "Башня Тьмы (Т1, мид)"
-- real Dota players in the game besides Steve (Dire's): tricks only Steve's screen needs are off then
function MC:DotaPlayers()
	for pid = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
		if PlayerResource:IsValidPlayerID( pid ) and PlayerResource:GetTeam( pid ) == DOTA_TEAM_BADGUYS
			and not PlayerResource:IsFakeClient( pid ) then return true end
	end
	return false
end

function MC:BuildingName( n )
	local side = n:find( "goodguys" ) and "Света" or "Тьмы"
	local lane = n:find( "top" ) and "верх" or n:find( "mid" ) and "мид" or n:find( "bot" ) and "низ"
	local tier = n:match( "tower(%d)" )
	local kind = n:find( "tower" ) and "Башня" or n:find( "rax" ) and "Казарма" or n:find( "fort" ) and "Трон" or "Здание"
	local extra = {}
	if tier then table.insert( extra, "Т" .. tier ) end
	if lane then table.insert( extra, lane ) end
	return kind .. " " .. side .. ( #extra > 0 and " (" .. table.concat( extra, ", " ) .. ")" or "" )
end

-- the Minecraft boss bar: Roshan while Steve is in his pit, else a building Steve hit in the last 5 s
function MC:BossBar( steve )
	if GameRules:GetGameTime() - ( MC.bossAt or 0 ) < 0.2 then return end
	MC.bossAt = GameRules:GetGameTime()
	local show
	if steve and not steve:IsNull() then
		for _, r in ipairs( Entities:FindAllByClassname( "npc_dota_roshan" ) ) do
			if r:IsAlive() and ( r:GetAbsOrigin() - steve:GetAbsOrigin() ):Length2D() < 900 then show = { "purple", r, "Рошан" } end
		end
	end
	local b = MC.bossUnit
	if not show and b and not b:IsNull() and b:IsAlive() and GameRules:GetGameTime() < ( MC.bossUntil or 0 ) then
		show = { b:GetTeamNumber() == DOTA_TEAM_GOODGUYS and "green" or "red", b,
			MC:BuildingName( b:GetUnitName() ) }
	end
	local line = show and string.format( "boss %s %d %d %s", show[1], show[2]:GetHealth(), show[2]:GetMaxHealth(), show[3] ) or "boss none"
	if line ~= MC.bossLine then MC.bossLine = line MCBridge:Send( line ) end
end

function MC:Init()
	-- Radiant: Steve, the Minecraft player (the host). Dire: Dota's players, with Dota's heroes
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, 1 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, 5 )
	GameRules:SetSameHeroSelectionEnabled( true )
	-- Dota's own phases: picks, a look at the teams, then time to buy and walk out before the creeps
	GameRules:SetHeroSelectionTime( 60 )
	GameRules:SetStrategyTime( 15 )
	GameRules:SetShowcaseTime( 0 )
	GameRules:SetPreGameTime( 60 )

	local mode = GameRules:GetGameModeEntity()
	-- the host goes to Radiant (Steve), whoever joins to Dire. A real game waits in the lobby until the host starts it
	-- (everyone has time to connect; Minecraft starts only then: its cursor lock left no way to press the button);
	-- (sv_cheats is on in every game: a local custom game, and some launch settings need it; only the tools skip the lobby)
	if not IsInToolsMode() then
		GameRules:SetCustomGameSetupTimeout( -1 )
		GameRules:EnableCustomGameSetupAutoLaunch( false )
	end
	-- always noon, like Minecraft's side (time locked there too): Dota's night lighting turns the blocks blue
	mode:SetDaynightCycleDisabled( true )
	GameRules:SetTimeOfDay( 0.5 )
	mode:SetDamageFilter( Dynamic_Wrap( MC, "DamageFilter" ), MC )
	-- (Dire bots, for testing without a second player, walk and fight; only in the tools: in a real game Dota's team AI
	-- then pressed the glyph over and over, "buildings fortified" for one team, then the other)
	if IsInToolsMode() then mode:SetBotThinkingEnabled( true ) end
	mode:SetCustomGlyphCooldown( 300 ) -- (Dota's own 5 minutes: a custom game's glyph had none)
	mode:SetCustomScanCooldown( 210 )
	mode:SetFreeCourierModeEnabled( true ) -- a courier for each Dota player (Dire had none); Steve's goes (MC:OnSpawned)
	-- a deny gives the denier nothing (Dota hands out XP for the killing attack)
	-- Steve's hero XP is counted by us (MC:SteveXP), not given: a Dota level-up plays its sound and Steve's level is
	-- only his Minecraft max health. A deny gives the denier nothing.
	mode:SetModifyExperienceFilter( function( _, f )
		local s = MCBridge.steve
		if not s or f.player_id_const ~= s:GetPlayerOwnerID() then return true end
		if not s.mc_denying then MC:SteveXP( f.experience ) end
		return false
	end, MC )
	-- Steve has no use for Dota gold (his money is emeralds, MC:LootFor): none, so no yellow "+45" over his kills either
	mode:SetModifyGoldFilter( function( _, f )
		local mine = MCBridge.steve and f.player_id_const == MCBridge.steve:GetPlayerOwnerID()
		if mine and ( f.reason_const == DOTA_ModifyGold_BountyRune or GameRules:GetGameTime() - ( MC.bountyAt or -10 ) < 1 ) then
			MC.bountyAt = nil
			MC:Emeralds( f.gold ) -- a bounty rune: emeralds
		end
		return not mine
	end, MC )
	mode:SetExecuteOrderFilter( Dynamic_Wrap( MC, "OrderFilter" ), MC )

	-- the host (the Minecraft player, player 0) is Radiant's Steve; everyone joining plays Dire
	ListenToGameEvent( "player_connect_full", function( e )
		local pid = e.PlayerID or ( e.index and e.index - 1 )
		if pid then MC:AssignTeam( pid ) end
	end, nil )
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( MC, "OnSpawned" ), MC )
	-- each player's copy of the game (tools/mcdota.py writes the commit): a different one than the host's is told
	pcall( require, "mc_version" )
	CustomGameEventManager:RegisterListener( "mc_version", function( _, e )
		if MC_VERSION and e.v ~= MC_VERSION then
			local who = PlayerResource:GetPlayerName( e.PlayerID ) or "?"
			print( "[mc] version of " .. who .. ": " .. tostring( e.v ) .. ", host " .. MC_VERSION )
			GameRules:SendCustomMessage( "<font color='#ff5050'>У игрока " .. who .. " другая версия игры (" .. tostring( e.v ) ..
				", у хоста " .. MC_VERSION .. "): закройте Доту и запустите play_dota.bat заново</font>", 0, 0 )
		end
	end )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( MC, "OnKilled" ), MC )
	ListenToGameEvent( "game_rules_state_change", Dynamic_Wrap( MC, "OnState" ), MC )
	ListenToGameEvent( "player_chat", Dynamic_Wrap( MC, "OnChat" ), MC )
	print( "[mc] loaded" )
end

-- test helpers: "-give item_mc_iron 5", "-time 0.5" (cheats/tools only)
function MC:OnChat( e )
	if not ( GameRules:IsCheatMode() or IsInToolsMode() ) then return end
	local t = e.text:match( "^%-time ([%d%.]+)" )
	if t then GameRules:SetTimeOfDay( tonumber( t ) ) return end
	local item, n = e.text:match( "^%-give (%S+)%s*(%d*)" )
	local hero = item and PlayerResource:GetSelectedHeroEntity( e.playerid )
	if not hero then return end
	for _ = 1, tonumber( n ) or 1 do hero:AddItemByName( item ) end
end

-- whoever didn't pick a hero in time plays Steve
-- Steve: Radiant's hero (a Dire player may well pick the same hero)
function MC:IsSteve( h )
	return h:GetUnitName() == STEVE and h:GetTeamNumber() == DOTA_TEAM_GOODGUYS
end

function MC:AssignTeam( pid )
	if not PlayerResource:IsValidPlayerID( pid ) then return end
	PlayerResource:SetCustomTeamAssignment( pid, pid == 0 and DOTA_TEAM_GOODGUYS or DOTA_TEAM_BADGUYS )
end

-- the launcher (tools/mcdota.py) starts Minecraft at the first of these in console.log
local STATE_NAMES = { [ DOTA_GAMERULES_STATE_HERO_SELECTION ] = "hero_selection", [ DOTA_GAMERULES_STATE_STRATEGY_TIME ] = "strategy",
	[ DOTA_GAMERULES_STATE_PRE_GAME ] = "pre_game", [ DOTA_GAMERULES_STATE_GAME_IN_PROGRESS ] = "game" }

function MC:OnState()
	if STATE_NAMES[ GameRules:State_Get() ] then print( "[mc] state " .. STATE_NAMES[ GameRules:State_Get() ] ) end
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP then
		for pid = 0, DOTA_MAX_TEAM_PLAYERS - 1 do MC:AssignTeam( pid ) end
		if IsInToolsMode() then GameRules:FinishCustomGameSetup() end -- (tools: no lobby)
	end
	if GameRules:State_Get() >= DOTA_GAMERULES_STATE_PRE_GAME then GameRules:SetTimeOfDay( 0.5 ) end -- the clock starts at dawn
	local st = GameRules:State_Get()
	if st ~= DOTA_GAMERULES_STATE_HERO_SELECTION and st ~= DOTA_GAMERULES_STATE_STRATEGY_TIME and st ~= DOTA_GAMERULES_STATE_PRE_GAME then return end
	for pid = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
		local player = PlayerResource:IsValidPlayerID( pid ) and PlayerResource:GetPlayer( pid )
		-- Radiant's player is Steve; Dire's players pick their heroes
		if player and not PlayerResource:HasSelectedHero( pid ) and PlayerResource:GetTeam( pid ) == DOTA_TEAM_GOODGUYS then
			player:SetSelectedHero( STEVE )
		end
	end
end

-- Radiant's creeps are Minecraft's mobs (tools/gen_mobs.py; static models): melee zombies, ranged skeletons, the
-- siege creep a skeleton riding a spider, the flag bearer a zombie in gold armour. Their Dota cosmetics hidden.
MC.mobs = {} -- units drawn as mobs (skinned models: Dota plays their idle/run/attack itself, tools/gen_mobs.py)
function MC:HideAttached( u )
	if u:IsNull() then return end
	for _, c in ipairs( u:GetChildren() ) do
		if c.AddEffects and c:GetClassname() ~= "info_particle_system" then c:AddEffects( EF_NODRAW ) end
	end
end

function MC:MobDeath( u )
	local p, yaw = u:GetAbsOrigin(), u:GetAnglesAsVector().y
	u:AddEffects( EF_NODRAW )
	local body = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/mob_" .. u.mc_mob .. ".vmdl",
		origin = string.format( "%f %f %f", p.x, p.y, p.z ), angles = string.format( "0 %f 0", yaw ) } )
	body:SetRenderColor( 255, 80, 80 )
	local t0 = GameRules:GetGameTime()
	body:SetContextThink( "mc_fall", function()
		local k = ( GameRules:GetGameTime() - t0 ) / 0.5
		if k < 1 then
			body:SetAngles( 0, yaw, 90 * math.min( 1, k * 1.6 ) )
			return 0.03
		end
		local fx = ParticleManager:CreateParticle( "particles/generic_gameplay/illusion_killed.vpcf", PATTACH_WORLDORIGIN, nil )
		ParticleManager:SetParticleControl( fx, 0, p + Vector( 0, 0, 40 ) )
		ParticleManager:ReleaseParticleIndex( fx )
		body:RemoveSelf()
	end, 0 )
end

function MC:MobSound( u, kind )
	if kind == "attack" and ( RandomFloat( 0, 1 ) > 0.35 or GameRules:GetGameTime() - ( u.mc_soundAt or 0 ) < 3 ) then return end
	if GameRules:GetGameTime() - ( u.mc_soundAt or 0 ) < 0.4 then return end
	u.mc_soundAt = GameRules:GetGameTime()
	MCBridge:Send( string.format( "mobsound %d %s %s", u:entindex(), u.mc_mob, kind ) )
end

MOB_MODELS = { { "flagbearer", "zombie_gold" }, { "siege", "spider_jockey" }, { "ranged", "skeleton" }, { "melee", "zombie" } }
function MC:MobModel( u )
	local name = u:GetUnitName()
	if not name:find( "goodguys" ) or not ( name:find( "creep" ) or name:find( "siege" ) ) then return end
	for _, m in ipairs( MOB_MODELS ) do
		if name:find( m[1] ) then
			local model = "models/mc/mob_" .. m[2] .. ".vmdl"
			u:SetOriginalModel( model )
			u:SetModel( model )
			u:SetModelScale( 1 )
			u.mc_mob = m[2]
			MC.mobs[ u ] = true
			MC:HideAttached( u )
			u:SetContextThink( "mc_hide", function()
				MC:HideAttached( u )
				if not u:IsNull() then u:RemoveModifierByName( "modifier_flagbearer_creep_aura_effect" ) end -- (its flag: a particle of it)
			end, 0.5 )
			return
		end
	end
end

function MC:OnSpawned( e )
	local hero = EntIndexToHScript( e.entindex )
	if hero and not hero:IsNull() and hero.IsCourier and hero:IsCourier() and hero:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
		hero:SetContextThink( "mc_nocourier", function() -- (a dead courier comes back: hidden and left alone instead)
			if hero:IsNull() then return end
			hero:AddNoDraw()
			hero:AddNewModifier( hero, nil, "modifier_invulnerable", {} )
			hero:AddNewModifier( hero, nil, "modifier_mc_nobar", {} )
		end, 0.1 )
		return
	end
	if hero and not hero:IsNull() and hero.GetUnitName then MC:MobModel( hero ) end
	if hero.mc_player and hero.mc_dead then -- Dota's respawn timer is over: Minecraft's player may move again
		hero.mc_dead = nil
		MCBridge:Send( "respawn" )
	end
	if not hero:IsRealHero() or hero.mc_ready then return end
	hero.mc_ready = true
	-- npc_spawned fires while the hero is still at (0,0,0); wait a frame for the real position
	hero:SetContextThink( "mc_setup", function() MC:SetupHero( hero ) end, FrameTime() )
end

function MC:SetupHero( hero )
	if MC:IsSteve( hero ) then hero:SetIdleAcquire( false ) end -- no auto-attack in Minecraft

	local place = hero:FindAbilityByName( "mc_place_block" )
	if place then place:SetLevel( 1 ) end

	if not MC.world_done and MC:IsSteve( hero ) and hero:IsRealHero() then -- (Steve's: a Dire hero may well spawn first)
		MC.world_done = true
		-- Minecraft (0,0) maps here: our fountain, on the grid. (The hero's own spawn spot moves a little from game to game,
		-- which shifted every terrain column against what an earlier session had built: the ground stopped matching.)
		local f, best = hero:GetAbsOrigin(), nil
		for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_fountain" ) ) do
			local d = ( e:GetAbsOrigin() - hero:GetAbsOrigin() ):Length2D()
			if e:GetTeamNumber() == hero:GetTeamNumber() and ( not best or d < best ) then f, best = e:GetAbsOrigin(), d end
		end
		MC.anchor = GetGroundPosition( Vector( math.floor( f.x / GRID + 0.5 ) * GRID, math.floor( f.y / GRID + 0.5 ) * GRID, 0 ), nil )
		-- Dota's own camera controls would fight Minecraft's (launch args alone get overridden by the user's config)
		SendToConsole( "dota_hud_healthbars 0; dota_disable_unit_ring 1; dota_hero_indicators_max_distance 0; dota_hero_indicators_max_radius 0; dota_camera_edgemove 0; dota_camera_speed 0; dota_camera_lock 0; dota_camera_fov_min 90; dota_camera_fov_max 90; dota_hud_disable_damage_numbers 1; snd_mute_losefocus 0; snd_musicvolume 0" ) -- Dota's sound plays with Minecraft holding focus; music is Minecraft's
		MC:SendTerrain()
		MCWorld:SendTrees()
		MC:StructureWalls()
		MCWorld:WarmUpWards( hero:GetTeamNumber() )
		MC:SpawnTraders()
		MC:Sky()
		-- Panorama's camera playback delay: Minecraft's overlay waits as long (see fpcam.js)
		CustomGameEventManager:RegisterListener( "mc_delay", function( _, e ) MCBridge:Send( "delay " .. math.floor( tonumber( e.d ) or 0 ) ) end )
		-- Dota's real vertical field of view, measured by Panorama: Minecraft's fov follows it (the layers stay matched)
		CustomGameEventManager:RegisterListener( "mc_fov", function( _, e ) MCBridge:Send( string.format( "mcfov %.2f", tonumber( e.v ) or 66 ) ) end )
		-- the unit Dota shows under the crosshair (the screen centre): Minecraft's melee swings land on it
		CustomGameEventManager:RegisterListener( "mc_aim", function( _, e )
			if MCBridge.steve and e.PlayerID ~= MCBridge.steve:GetPlayerOwnerID() then return end -- (Steve's client only)
			local u = tonumber( e.e ) and tonumber( e.e ) > 0 and EntIndexToHScript( tonumber( e.e ) )
			-- (a target is kept 0.3 s after the crosshair leaves it: a click a frame late still lands)
			if u and u.GetUnitName then MCBridge.aim, MCBridge.aimAt = u, GameRules:GetGameTime()
			elseif MCBridge.aim and GameRules:GetGameTime() - ( MCBridge.aimAt or 0 ) > 0.3 then MCBridge.aim = nil end
		end )
		-- ponytail: thinks on the game mode entity never fired here, so timers live on their own entity
		local timer = SpawnEntityFromTableSynchronous( "info_target", { targetname = "mc_timer" } )
		local function safe( f ) -- log the real error instead of the engine's "error in error handling"
			return function()
				local ok, r = pcall( f )
				if ok then return r end
				print( "[mc] ERROR " .. tostring( r ) )
				return 1
			end
		end
		timer:SetContextThink( "mc_bridge", safe( function() return MCBridge:Tick() end ), 1 )
	end
end

-- Dota position <-> Minecraft block column (bx, bz)
-- Minecraft's grid is turned GRID_ROT degrees on Dota's map (counter-clockwise): along mid, from fountain to
-- fountain, so a straight line of blocks runs down the lane. Minecraft x, z (blocks) <-> Dota (units):
-- unturned, x -> +X and z -> -Y; then the turn.
GRID_ROT = 42.8
local COS, SIN = math.cos( math.rad( GRID_ROT ) ), math.sin( math.rad( GRID_ROT ) )
function MC:Offset( x, z ) -- Minecraft x, z -> a Dota offset from the anchor
	local dx, dy = x * GRID, -z * GRID
	return Vector( dx * COS - dy * SIN, dx * SIN + dy * COS, 0 )
end
function MC:ToMC( pos ) -- Dota position -> Minecraft x, z (blocks, not rounded)
	local dx, dy = pos.x - MC.anchor.x, pos.y - MC.anchor.y
	return ( dx * COS + dy * SIN ) / GRID, -( -dx * SIN + dy * COS ) / GRID
end
function MC:DirToDota( fx, fz ) -- a Minecraft direction -> Dota's
	return Vector( fx * COS + fz * SIN, fx * SIN - fz * COS, 0 )
end
function MC:DirToMC( v ) -- a Dota direction -> Minecraft's fx, fz
	return v.x * COS + v.y * SIN, -( -v.x * SIN + v.y * COS )
end

function MC:CellOf( pos )
	local x, z = MC:ToMC( pos )
	return math.floor( x ), math.floor( z )
end

function MC:CellPos( bx, bz )
	return GetGroundPosition( MC.anchor + MC:Offset( bx + 0.5, bz + 0.5 ), nil )
end

MC.cells = {} -- "bx,bz" -> block unit
MC.heights = {} -- "bx,bz" -> Minecraft y of the ground surface there
MC.halfh = {} -- "bx,bz" -> the same in half blocks (odd = a slab on top)

-- ground height in half blocks above MC_FLOOR (Minecraft rebuilds it with full blocks plus slabs)
function MC:HalfHeightAt( z ) return math.floor( ( z - MC.anchor.z ) / ( GRID / 2 ) + 0.5 ) end
function MC:HeightAt( z ) return MC_FLOOR + math.floor( MC:HalfHeightAt( z ) / 2 ) end

-- Minecraft's invisible floor follows Dota's terrain (1-block steps; autojump takes them)
function MC:SendTerrain()
	-- the Dota map in cells; outside it (and wherever Dota reports garbage heights) Minecraft gets bottomless void
	local a = MC.anchor
	local x1, x2, z1, z2 = 1e9, -1e9, 1e9, -1e9
	for _, c in ipairs( { { GetWorldMinX(), GetWorldMinY() }, { GetWorldMinX(), GetWorldMaxY() }, { GetWorldMaxX(), GetWorldMinY() }, { GetWorldMaxX(), GetWorldMaxY() } } ) do
		local x, z = MC:ToMC( Vector( c[1], c[2], 0 ) )
		x1, x2, z1, z2 = math.min( x1, math.floor( x ) ), math.max( x2, math.floor( x ) ), math.min( z1, math.floor( z ) ), math.max( z2, math.floor( z ) )
	end
	-- the map's own box plus a void strip past its edge, then the border. (Not a square around the anchor: the anchor is
	-- our fountain, in a corner, and a square of 220 left the far corner, the enemy's base, unbuilt behind the border.)
	local bx1, bx2 = math.max( x1 - 6, -TERRAIN_R ), math.min( x2 + 6, TERRAIN_R )
	local bz1, bz2 = math.max( z1 - 6, -TERRAIN_R ), math.min( z2 + 6, TERRAIN_R )
	MCBridge:Send( string.format( "border %d %d %d", math.max( bx2 - bx1, bz2 - bz1 ) + 1, math.floor( ( bx1 + bx2 ) / 2 ), math.floor( ( bz1 + bz2 ) / 2 ) ) )
	print( string.format( "[mc] terrain cells x %d..%d z %d..%d, map cells x %d..%d z %d..%d", bx1, bx2, bz1, bz2, x1, x2, z1, z2 ) )
	-- the world bounds are far bigger than the visible map; past its edge (a rim, then no terrain at all) Dota reports
	-- heights ~16000 below: that is where Minecraft gets its void
	local function outside( bx, bz )
		local p = a + MC:Offset( bx + 0.5, bz + 0.5 ) -- (the grid is turned: Dota's own bounds)
		return p.x < GetWorldMinX() or p.x > GetWorldMaxX() or p.y < GetWorldMinY() or p.y > GetWorldMaxY()
			or math.abs( MC:CellPos( bx, bz ).z - a.z ) > 1500
	end
	local H = {}
	local function hh( bx, bz )
		local k = bx .. "," .. bz
		if H[ k ] == nil then
			local z = MC:CellPos( bx, bz ).z
			H[ k ] = math.abs( z - MC.anchor.z ) > 1500 and 0 or MC:HalfHeightAt( z ) -- off the map edge the height is garbage
		end
		return H[ k ]
	end
	for bx = bx1, bx2 do
		for bz = bz1, bz2 do
			if outside( bx, bz ) then
				MCBridge:Send( string.format( "void %d %d", bx, bz ) )
			else
				local h = hh( bx, bz )
				-- lowest neighbour: this column's side wall is exposed down to there and must be magenta too
				-- (a void neighbour is bottomless: the side facing the map edge is skinned all the way down, or its dirt
				-- and stone showed as a strip along the horizon)
				local function nb( x, z ) return outside( x, z ) and -100 or hh( x, z ) end
				local low = math.min( h, nb( bx + 1, bz ), nb( bx - 1, bz ), nb( bx, bz + 1 ), nb( bx, bz - 1 ) )
				MC.heights[ bx .. "," .. bz ] = MC_FLOOR + math.floor( h / 2 )
				MC.halfh[ bx .. "," .. bz ] = h
				MCBridge:Send( string.format( "h %d %d %d %d", bx, bz, h, low ) ) -- flat ones too: a column voided earlier comes back
			end
		end
	end
end

-- a dark sky dome over the map (tools/gen_sky.py): hides Dota's striped map edge, never meant to be seen from the ground
SKY_R = 14000 -- the map's corners are ~11300 from its centre; Dota's far plane is 40000 (dev_launch.sh)
function MC:Sky()
	if MC.sky and not MC.sky:IsNull() then return end
	MC.sky = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/sky.vmdl", origin = "0 0 0", disableshadows = "1" } )
	MC.sky:SetModelScale( SKY_R / 100 )
end

-- Dota's structures as Minecraft walls (barrier columns, 4 high): towers, barracks, ancients, shrines/fillers, outposts,
-- watchers, twin gates, and Roshan's pit (Dota's blocked ground around him). A building's walls go when it dies.
STRUCTURE_RADIUS = { tower = 130, barracks = 220, fort = 300, filler = 150, watch_tower = 180, lantern = 90, twin_gate = 180 }
function MC:WallCells( center, radius, onlyBlocked )
	local cells = {}
	local cx, cz = MC:CellOf( center )
	local r = math.ceil( radius / GRID ) + 1
	for x = cx - r, cx + r do for z = cz - r, cz + r do
		local p = MC.anchor + MC:Offset( x + 0.5, z + 0.5 )
		p.z = 0
		local c2 = Vector( center.x, center.y, 0 )
		if ( p - c2 ):Length2D() <= radius and ( not onlyBlocked or not GridNav:IsTraversable( GetGroundPosition( p, nil ) ) ) then
			table.insert( cells, { x, z } )
		end
	end end
	return cells
end

function MC:Walls( u, cells )
	u.mc_walls = u.mc_walls or {}
	for _, c in ipairs( cells ) do
		local g = MC.heights[ c[1] .. "," .. c[2] ] or MC_FLOOR
		for y = g, g + 3 do
			MCBridge:Send( string.format( "block %d %d %d barrier", c[1], y, c[2] ) )
			table.insert( u.mc_walls, { c[1], y, c[2] } )
		end
	end
end

function MC:StructureWalls()
	local n = 0
	for _, u in ipairs( FindUnitsInRadius( DOTA_TEAM_NEUTRALS, Vector( 0, 0, 0 ), nil, 30000, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_ALL, DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD, FIND_ANY_ORDER, false ) ) do
		local name, r = u:GetUnitName(), nil
		for k, v in pairs( STRUCTURE_RADIUS ) do if name:find( k ) then r = v end end
		if not r and u:IsBuilding() and not u:GetUnitName():find( "fountain" ) then r = 150 end
		if r and not name:find( "fountain" ) then
			MC:Walls( u, MC:WallCells( u:GetAbsOrigin(), r, false ) )
			n = n + 1
		end
	end
	for _, r in ipairs( Entities:FindAllByClassname( "npc_dota_roshan" ) ) do -- the pit's walls: Dota's own blocked ground
		MC:Walls( r, MC:WallCells( r:GetAbsOrigin(), 700, true ) )
	end
	print( "[mc] structure walls: " .. n )
end

-- a fountain shoots any neutral in its range: blocks there are invulnerable (= not a target)
function MC:NearFountain( pos, range )
	for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_fountain" ) ) do
		if ( e:GetAbsOrigin() - pos ):Length2D() < ( range or 1500 ) then return true end
	end
	return false
end

-- fromMC: the block came from Minecraft, so don't echo it back
function MC:SpawnBlock( name, pos, fromMC )
	local def = BLOCKS[ name ]
	local bx, bz = MC:CellOf( pos )
	local key = bx .. "," .. bz
	if MC.cells[ key ] and not MC.cells[ key ]:IsNull() then return MC.cells[ key ] end
	-- neutrals: on a team, the other team's creeps would attack them (fountains shoot neutrals: see MC:NearFountain)
	local b = CreateUnitByName( name, MC:CellPos( bx, bz ), false, nil, nil, DOTA_TEAM_NEUTRALS )
	b.mc_block, b.mc_cell = def, key
	MC.cells[ key ] = b
	b:AddNewModifier( b, nil, "modifier_mc_block", {} )
	if not CALIBRATE then -- Dota draws the blocks as props: this unit is invisible, but clickable (Dota's players attack it)
		b:SetOriginalModel( "models/mc/block_ghost.vmdl" )
		b:SetModel( "models/mc/block_ghost.vmdl" )
		b:SetModelScale( 1 )
		b:SetAngles( 0, GRID_ROT, 0 ) -- (its hitbox square along the turned Minecraft grid)
	end
	-- (after the model: setting one reset the hull, and Dota's heroes walked through the blocks)
	b:SetHullRadius( GRID * 0.375 ) -- neighbours' hulls overlap: Dota heroes can't squeeze between blocks
	if not fromMC then MCBridge:Send( string.format( "block %d %d %d %s", bx, MC.heights[ key ] or MC_FLOOR, bz, def.mc ) ) end
	return b
end

-- Hybrid: Dota draws Minecraft's blocks (any height) as props, so they sit exactly on Dota's map
MC.props = {} -- "x,y,z" -> prop_dynamic
MODELS = { spruce_planks = "spruce_planks", red_wool = "red_wool", white_wool = "white_wool", blue_wool = "blue_wool",
	oak_log = "log", oak_planks = "planks", stone = "stone", cobblestone = "cobblestone", dirt = "dirt", sand = "sand",
	coal_ore = "coal_ore", iron_ore = "iron_ore", diamond_ore = "diamond_ore", crafting_table = "crafting_table" }

-- Where Dota draws a Minecraft block: at its Minecraft height, so walls and roofs stay level and match what the player
-- walks on. (Drawing each block from Dota's real ground under its cell broke roofs into steps; on a slope a block is
-- off by at most a quarter block, Minecraft's terrain being half-block steps of Dota's ground.)
function MC:BlockPos( bx, by, bz )
	return MC.anchor + MC:Offset( bx + 0.5, bz + 0.5 ) + Vector( 0, 0, ( by - MC_FLOOR ) * GRID )
end

-- which of a block's variants its state picks (all of the variant's properties must be in the state, as in Minecraft)
function MC:Variant( kind, state )
	local vs = MCB[ kind ]
	if not vs then return nil end
	state = "," .. ( state or "" ) .. ","
	for _, v in ipairs( vs ) do
		local ok = true
		for kv in v[1]:gmatch( "[^,]+" ) do if not state:find( "," .. kv .. ",", 1, true ) then ok = false break end end
		if ok then return v end
	end
	return vs[1]
end

-- Dota draws a Minecraft block: its own model from Minecraft's block model (tools/gen_mcblocks.py), turned for the
-- blockstate variant around the block's centre (Minecraft: x first, then y, both clockwise seen down the axis)
function MC:ShowBlock( bx, by, bz, kind, solid, state )
	local key = bx .. "," .. by .. "," .. bz
	MC:HideBlock( bx, by, bz )
	local pos = MC:BlockPos( bx, by, bz )
	local v = MC:Variant( kind, state )
	local p
	-- something light (fire, a torch, a flower) right on a half-step column stands on the terrain's slab, half a block lower
	local h = MC.halfh[ bx .. "," .. bz ]
	local under = MC.props[ bx .. "," .. ( by - 1 ) .. "," .. bz ]
	local sink = ( solid == false and h and h % 2 == 1 and by == MC_FLOOR + ( h + 1 ) / 2 and not ( under and not under:IsNull() ) ) and GRID / 2 or 0
	if v then
		p = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mcb/" .. v[2] .. ".vmdl",
			origin = string.format( "%f %f %f", pos.x, pos.y, pos.z + GRID / 2 - sink ), angles = string.format( "0 %f %d", -v[4] + GRID_ROT, v[3] ) } )
	else -- not a Minecraft block we know: the old cube
		p = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/" .. ( MODELS[ kind ] or "cobblestone" ) .. ".vmdl",
			origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ), angles = string.format( "0 %f 0", GRID_ROT ) } )
	end
	p:SetModelScale( GRID / 128 ) -- the models are 128 units a block
	if v and MCB_ANIM[ v[2] ] then MC:Animate( p, v[2] ) end
	p.mc_kind = kind
	if kind == "cobweb" then MC.cobwebs[ p ] = true end
	if WARD_KINDS[ kind ] then
		-- a torch is a ward: the ward unit itself wears the torch (a prop is seen by everyone; a ward is invisible to
		-- the enemy without true sight, like Dota's)
		MCWorld:Ward( bx, by, bz, WARD_KINDS[ kind ] )
		local w = MC.wards and MC.wards[ key ]
		if w and not w.unit:IsNull() then
			w.unit:SetOriginalModel( p:GetModelName() )
			w.unit:SetModel( p:GetModelName() )
			w.unit:SetModelScale( GRID / 128 )
			w.unit:SetAbsOrigin( p:GetAbsOrigin() )
			w.unit:SetAngles( p:GetAnglesAsVector().x, p:GetAnglesAsVector().y, p:GetAnglesAsVector().z )
			w.unit:RemoveNoDraw()
			p:AddEffects( EF_NODRAW )
		end
	end
	p.mc_solid = solid ~= false -- fire, torches, flowers: drawn, but units neither bump into nor stand on them
	MC.props[ key ] = p
end

-- fire burns like Minecraft's: its frames are models (<model>__f<k>, tools/gen_mcblocks.py), swapped ~12 times a second
MC.animated = {}
MC.cobwebs = {} -- cobweb props: MCBridge:Tick slows units in them
function MC:Animate( p, model )
	p.mc_anim = model
	MC.animated[ p ] = true
	if MC.animating then return end
	MC.animating = true
	GameRules:GetGameModeEntity():SetContextThink( "mc_anim", function()
		local t = math.floor( GameRules:GetGameTime() * 12 )
		for q in pairs( MC.animated ) do
			if q:IsNull() then MC.animated[ q ] = nil
			else
				local k = t % MCB_ANIM[ q.mc_anim ] -- all in step, like Minecraft's (one animated texture)
				q:SetModel( "models/mcb/" .. q.mc_anim .. ( k > 0 and "__f" .. k or "" ) .. ".vmdl" )
				q:SetModelScale( GRID / 128 )
			end
		end
		return 1 / 12
	end, 0 )
end

-- What Dota units can do with a Minecraft column at their height: like a Minecraft player they step up ONE block
-- (walk on top of it), two stacked blocks are a wall. Returns: block at ground level, block one above.
function MC:Column( bx, bz )
	local g = MC.heights[ bx .. "," .. bz ] or MC_FLOOR
	local function solid( y ) local p = MC.props[ bx .. "," .. y .. "," .. bz ] return p and p.mc_solid and p or nil end
	return solid( g ), solid( g + 1 ), g
end

-- a Minecraft block appeared/vanished in this column: keep its Dota block unit (mining target, and a wall when 2 high)
function MC:ColumnChanged( bx, bz )
	local low, high, g = MC:Column( bx, bz )
	MC:Obstruct( bx, bz, high ~= nil )
	if not low and not high then MC:RemoveBlock( bx, bz ) return end
	local b = MC.cells[ bx .. "," .. bz ]
	if not b or b:IsNull() or not b:IsAlive() then
		local top = low or high
		b = MC:SpawnBlock( FROM_MC[ top.mc_kind ] or "npc_mc_block_cobble", MC:CellPos( bx, bz ), true )
	end
	b.mc_y = low and g or g + 1 -- what a Dota hero mines out of this column
	b.mc_protected = MC.protected[ bx .. "," .. bz ] or MC:NearFountain( b:GetAbsOrigin() )
	local m = b:FindModifierByName( "modifier_mc_block" )
	if m then m:SetStackCount( ( ( low and not high ) and 1 or 0 ) + ( b.mc_mined and 2 or 0 ) ) end -- (modifier_mc_block)
	b:SetAbsOrigin( MC:CellPos( bx, bz ) ) -- (on its own cell, whatever moved it)
end

-- A wall (a block at head height) is an obstacle in Dota's grid like a tree: point_simple_obstruction in each of Dota's
-- 64-unit nav squares the turned Minecraft cell covers (shared squares counted). Units only bumped into the block units
-- before, and walked through walls 2-3 blocks high.
MC.navRef, MC.walls = {}, {}
function MC:Obstruct( bx, bz, on )
	local key = bx .. "," .. bz
	if ( MC.walls[ key ] ~= nil ) == on or not MC.anchor then return end
	if on then
		local squares = {}
		for _, o in ipairs( { { 0.5, 0.5 }, { 0.15, 0.15 }, { 0.85, 0.15 }, { 0.15, 0.85 }, { 0.85, 0.85 } } ) do
			local p = MC.anchor + MC:Offset( bx + o[1], bz + o[2] )
			local gx, gy = GridNav:WorldToGridPosX( p.x ), GridNav:WorldToGridPosY( p.y )
			local nk = gx .. "," .. gy
			if not squares[ nk ] then
				squares[ nk ] = true
				local r = MC.navRef[ nk ]
				if not r then
					local c = Vector( GridNav:GridPosToWorldCenterX( gx ), GridNav:GridPosToWorldCenterY( gy ), p.z )
					r = { n = 0, e = SpawnEntityFromTableSynchronous( "point_simple_obstruction",
						{ origin = string.format( "%f %f %f", c.x, c.y, c.z ), block_fow = false } ) }
					MC.navRef[ nk ] = r
				end
				r.n = r.n + 1
			end
		end
		MC.walls[ key ] = squares
	else
		for nk in pairs( MC.walls[ key ] ) do
			local r = MC.navRef[ nk ]
			if r then
				r.n = r.n - 1
				if r.n <= 0 then
					if r.e and not r.e:IsNull() then r.e:RemoveSelf() end
					MC.navRef[ nk ] = nil
				end
			end
		end
		MC.walls[ key ] = nil
	end
end

-- a unit standing in a walkable column is drawn one block up (Dota keeps it on its ground; this is only visual)
-- returns how many blocks up it stands
function MC:LiftUnit( u )
	local low, high = MC:Column( MC:CellOf( u:GetAbsOrigin() ) )
	local lift = ( low and not high ) and 1 or 0
	local m = u:FindModifierByName( "modifier_mc_lift" )
	if lift > 0 and not m then u:AddNewModifier( u, nil, "modifier_mc_lift", {} ):SetStackCount( GRID )
	elseif lift == 0 and m then m:Destroy() end
	return lift
end

-- Traders (Minecraft cells; they look west). Dota draws them; Minecraft keeps an invisible villager on each spot to trade
-- with (Progress.java has the offers). The basic shop stands by the spawn, the secret one at Dota's own secret shop.
BASE_TRADERS = { "fletcher", "librarian", "toolsmith", "mason" }
TRADERS = {} -- { Minecraft x, z (exact), profession, facing x, z }

-- a block Dota decides on: Minecraft gets it (queued behind that column's terrain), Dota draws it and collides with it
-- (protected: invulnerable in Dota, so the fountain doesn't shoot the market and nobody mines it)
MC.protected = {} -- "bx,bz" -> true
-- the traders' signs: Dota models with their text baked in (tools/gen_signs.py has the texts). Minecraft's own signs
-- lagged behind Dota's picture and drifted. kind: "wall" (against the block behind, facing = the way the text looks)
-- or "stand" (rot = Minecraft's 0-15 standing rotation).
SIGN_MODELS = { "fletcher_name", "fletcher_goods", "mason_name", "mason_goods", "librarian_name", "librarian_goods",
	"toolsmith_name", "toolsmith_goods", "secret_1", "secret_2", "witch" }
function MC:Facing( fx, fz ) return fx > 0 and "east" or fx < 0 and "west" or fz > 0 and "south" or "north" end
local FACING_YAW = { south = 0, west = 90, north = 180, east = 270 } -- Minecraft's clockwise turn from the model's south
SIGN_TURN = -90 -- the imported model's board runs along Dota y: a quarter turn puts it along the wall
-- a sign whose text looks along Dota direction d (a model at yaw 0 shows its text toward +X)
function MC:SignFacing( x, y, z, id, d )
	MC:Sign( x, y, z, id, -math.deg( math.atan2( d.y, d.x ) ) + SIGN_TURN + GRID_ROT )
end

function MC:Sign( x, y, z, id, yaw, back )
	local pos = MC:BlockPos( x, y, z )
	local p = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/sign_" .. id .. ".vmdl",
		origin = string.format( "%f %f %f", pos.x, pos.y, pos.z + GRID / 2 ), angles = string.format( "0 %f 0", -yaw + SIGN_TURN + GRID_ROT ) } ) -- (checked on screen)
	p:SetModelScale( GRID / 128 )
end

function MC:PlaceBlock( x, y, z, kind )
	MC.protected[ x .. "," .. z ] = true
	MCBridge:Send( string.format( "block %d %d %d %s", x, y, z, kind ) )
	MC:ShowBlock( x, y, z, kind )
	MC:ColumnChanged( x, z )
end

-- a secret trader: in the place of Dota's secret shopkeeper there (hidden), looking the way he did, his two standing
-- signs in front of him, left and right
function MC:SecretTrader( shop, profession )
	local keeper, keeperD
	for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_shop" ) ) do
		local d = ( e:GetAbsOrigin() - shop:GetAbsOrigin() ):Length2D()
		if d < 1500 and ( not keeperD or d < keeperD ) then keeper, keeperD = e, d end
	end
	if not keeper then
		local x, z = MC:CellOf( shop:GetAbsOrigin() )
		table.insert( TRADERS, { x + 2.5, z + 0.5, profession } )
		return
	end
	keeper:AddEffects( EF_NODRAW )
	local p, f = keeper:GetAbsOrigin(), keeper:GetForwardVector()
	local tx, tz = MC:ToMC( p )
	local fx, fz = MC:DirToMC( f )
	table.insert( TRADERS, { tx, tz, profession, fx, fz } )
	for _, side in ipairs( { -1, 1 } ) do
		local w = 1.6
		local fo = side < 0 and 0.6 or 1.6 -- (the name sign a block nearer him, the goods one further back)
		local x, z = math.floor( tx + fo * fx - w * side * fz ), math.floor( tz + fo * fz + w * side * fx )
		MC:SignFacing( x, MC.heights[ x .. "," .. z ] or MC_FLOOR, z, side < 0 and "secret_1" or "secret_2", MC:DirToDota( fx, fz ) )
	end
	print( string.format( "[mc] secret trader %s at %.1f %.1f", profession, tx, tz ) )
end

function MC:SpawnTraders()
	-- the basic shop: a little market ON our fountain, two rows of stalls facing each other across an aisle that runs
	-- toward the map centre. Laid out on Minecraft's grid (the aisle along whichever axis is closer to that way).
	local a = MC.anchor
	local fountain, best = a, nil
	for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_fountain" ) ) do
		local d = ( e:GetAbsOrigin() - a ):Length2D()
		if not best or d < best then fountain, best = e:GetAbsOrigin(), d end
	end
	local cx, cz = MC:CellOf( fountain )
	-- Dota's own fountain shopkeeper stands where our stalls go: hide him (the shop trigger stays, it's unused here)
	-- (laid out by hand in the unturned grid: each spot below is that same place on Dota's map, in the turned grid)
	local a0 = MC.anchor
	local function oldCell( p ) return math.floor( ( p.x - a0.x ) / GRID ), math.floor( -( p.y - a0.y ) / GRID ) end
	local function snap( fx, fz ) -- an unturned grid direction -> the turned grid's nearest axis
		local x, z = MC:DirToMC( Vector( fx, -fz, 0 ) )
		if math.abs( x ) >= math.abs( z ) then return { x > 0 and 1 or -1, 0 } end
		return { 0, z > 0 and 1 or -1 }
	end
	local shopX, shopZ
	for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_shop" ) ) do
		if ( e:GetAbsOrigin() - fountain ):Length2D() < 1600 then
			e:AddEffects( EF_NODRAW )
			shopX, shopZ = oldCell( e:GetAbsOrigin() )
		end
	end
	-- The market, laid out by hand on the real map (Radiant; Dire is the same turned 180 degrees): U = the Minecraft axis
	-- closest to the way toward the map centre, V = U turned 90 degrees. The red stall stands where Dota's shopkeeper
	-- was (nudged 1 along U, 2 along V), its counter toward U (the open ground); the blue one perpendicular to it, 8 cells along U and 8 along V,
	-- its counter toward -V. Steve (re)spawns on the square between them.
	local out = -fountain:Normalized() -- toward the world origin = the map centre
	local Uo = math.abs( out.x ) >= math.abs( out.y ) and { out.x > 0 and 1 or -1, 0 } or { 0, out.y > 0 and -1 or 1 } -- (unturned: z runs against Dota y)
	local Vo = { -Uo[2], Uo[1] }
	local fcx, fcz = oldCell( fountain )
	local sx, sz = shopX or ( fcx + 4 * Uo[1] ), shopZ or ( fcz + 4 * Uo[2] )
	local U, V = snap( Uo[1], Uo[2] ), snap( Vo[1], Vo[2] ) -- the stalls' axes in the turned grid
	local function rel( u, v )
		local x, z = sx + u * Uo[1] + v * Vo[1], sz + u * Uo[2] + v * Vo[2]
		return MC:CellOf( a0 + Vector( ( x + 0.5 ) * GRID, -( z + 0.5 ) * GRID, 0 ) )
	end
	local function ground( x, z ) return MC.heights[ x .. "," .. z ] or MC_FLOOR end
	MC.spawnX, MC.spawnZ = rel( 5, 4 )
	MC.witchX, MC.witchZ = rel( 10, 3 )
	MC.witchF = { -U[1], -U[2] }
	local function free( x, z ) return math.abs( x - MC.spawnX ) > 1 or math.abs( z - MC.spawnZ ) > 1 end
	-- Two market stalls (after Dio Rods' "Market Stall"), two traders in each, told apart by their awnings.
	-- Each stall: centre, F = toward its open front, D = along it.
	local rx, rz = rel( 1, 2 ) -- (moved by hand: a block toward its front, two to the player's left)
	-- the grid axis from one cell nearest the way to another
	local function toward( x0, z0, x1, z1 )
		local dx, dz = x1 - x0, z1 - z0
		if math.abs( dx ) >= math.abs( dz ) then return { dx > 0 and 1 or -1, 0 } end
		return { 0, dz > 0 and 1 or -1 }
	end
	local bx, bz = rel( 8, 8 )
	local STALLS = {
		{ x = rx, z = rz, F = toward( rx, rz, bx, bz ), D = nil, awning = "red_wool", traders = { "fletcher", "mason" } },
		{ x = bx, z = bz, F = { -V[1], -V[2] }, D = U, awning = "blue_wool", traders = { "librarian", "toolsmith" } },
	}
	for _, st in ipairs( STALLS ) do st.D = st.D or { -st.F[2], st.F[1] } end -- (along the counter: F turned a quarter)
	MC.witchF = STALLS[2].F -- (she, her sign and her stand look the way the blue stall does)
	local taken = {} -- stall cells: the fountain's barriers must not fill them (a trader inside a barrier can't be clicked)
	for _, st in ipairs( STALLS ) do
		for du = -3, 3 do for dv = -1, 2 do
			taken[ ( st.x + du * st.D[1] + dv * st.F[1] ) .. "," .. ( st.z + du * st.D[2] + dv * st.F[2] ) ] = true
		end end
	end
	-- the fountain itself: Minecraft has nothing there, so the player walked into its basin; invisible barriers (not
	-- drawn by Dota: only Minecraft gets them) keep him out
	for du = -3, 3 do for dv = -3, 3 do
		local x, z = cx + du, cz + dv
		if du * du + dv * dv <= 10 and free( x, z ) and not taken[ x .. "," .. z ] then
			local g = ground( x, z )
			for y = g, g + 2 do MCBridge:Send( string.format( "block %d %d %d barrier", x, y, z ) ) end
		end
	end end
	for _, st in ipairs( STALLS ) do
		local function at( du, dv ) return st.x + du * st.D[1] + dv * st.F[1], st.z + du * st.D[2] + dv * st.F[2] end
		local base = -1000 -- the stall stands level on its highest ground; lower columns get a spruce footing
		for du = -2, 2 do for dv = -1, 1 do base = math.max( base, ground( at( du, dv ) ) ) end end
		local function put( du, dv, dy, kind )
			local x, z = at( du, dv )
			if free( x, z ) then MC:PlaceBlock( x, base + dy, z, kind ) end
		end
		for du = -2, 2 do for dv = -1, 1 do
			local x, z = at( du, dv )
			for y = ground( x, z ), base - 1 do if free( x, z ) then MC:PlaceBlock( x, y, z, "spruce_planks" ) end end
		end end
		for _, du in ipairs( { -2, 2 } ) do for _, dv in ipairs( { -1, 1 } ) do -- corner posts
			for dy = 0, 2 do put( du, dv, dy, "oak_log" ) end
		end end
		for du = -1, 1 do
			put( du, 1, 0, "oak_planks" ) -- counter, open front above it
			put( du, -1, 0, "spruce_planks" ) -- back bench
		end
		for du = -2, 2 do for dv = -1, 1 do -- spruce frame under the awning, then the striped awning
			if du == -2 or du == 2 or dv ~= 0 then put( du, dv, 3, "spruce_planks" ) end
			put( du, dv, 4, ( du % 2 == 0 ) and st.awning or "white_wool" )
		end end
		for du = -2, 2 do put( du, 2, 3, ( du % 2 == 0 ) and st.awning or "white_wool" ) end -- awning lip over the front
		for _, du in ipairs( { -3, 3 } ) do for dv = -1, 1 do -- hanging side flaps
			put( du, dv, 3, st.awning )
			if dv == 1 then put( du, dv, 2, st.awning ) end
		end end
		for i, prof in ipairs( st.traders ) do
			local x, z = at( i == 1 and -1 or 1, 0 )
			table.insert( TRADERS, { x + 0.5, z + 0.5, prof, st.F[1], st.F[2], base } )
			-- his signs: his name on the awning's lip above him, what he sells on the counter's front
			local yaw = FACING_YAW[ MC:Facing( st.F[1], st.F[2] ) ]
			local du = i == 1 and -1 or 1
			local sx2, sz2 = at( du, 3 )
			MC:Sign( sx2, base + 3, sz2, prof .. "_name", yaw, st.F )
			sx2, sz2 = at( du, 2 )
			MC:Sign( sx2, base, sz2, prof .. "_goods", yaw, st.F )
		end
	end
	print( string.format( "[mc] market: shop %d,%d, red stall %d,%d, blue stall %d,%d, spawn %d,%d", sx, sz, rx, rz, bx, bz, MC.spawnX, MC.spawnZ ) )
	-- Dota's shops are trigger_shop volumes (no API tells their type): the two secret shops are the ones well away from
	-- both fountains (the base shops stand by them); Radiant's is the one nearer our spawn. A map with fewer: what there is.
	local dire
	for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_fountain" ) ) do
		if e:GetTeamNumber() == DOTA_TEAM_BADGUYS then dire = e:GetAbsOrigin() end
	end
	local secrets, any = {}, nil
	for _, e in ipairs( Entities:FindAllByClassname( "trigger_shop" ) ) do
		any = any or e
		local far = ( e:GetAbsOrigin() - a ):Length2D() / GRID > 30 and not ( dire and ( e:GetAbsOrigin() - dire ):Length2D() < 2500 )
		if far then table.insert( secrets, e ) end
	end
	table.sort( secrets, function( p, q ) return ( p:GetAbsOrigin() - a ):Length2D() < ( q:GetAbsOrigin() - a ):Length2D() end )
	if #secrets == 0 and any then secrets = { any } end
	-- Radiant's secret trader the weaponsmith, Dire's the armorer (Progress.java: the same goods)
	for i, shop in ipairs( secrets ) do
		if i <= 2 then MC:SecretTrader( shop, i == 1 and "weaponsmith" or "armorer" ) end
	end
	if #secrets == 0 then table.insert( TRADERS, { 22.5, 0.5, "weaponsmith" } ) end
	-- the witch (potions): standing on the square, facing the spawn
	table.insert( TRADERS, { MC.witchX + 0.5, MC.witchZ + 0.5, "cleric", MC.witchF[1], MC.witchF[2] } )
	do -- her sign on one side, a brewing stand on the other (just for the look)
		local fx, fz = MC.witchF[1], MC.witchF[2]
		local sx, sz = MC.witchX - fz, MC.witchZ + fx
		local rot = math.floor( ( math.deg( math.atan2( -fx, fz ) ) % 360 ) / 22.5 + 0.5 ) % 16
		MC:SignFacing( sx, MC.heights[ sx .. "," .. sz ] or MC_FLOOR, sz, "witch", MC:DirToDota( fx, fz ) ) -- (text the way she looks)
		local bx2, bz2 = MC.witchX + fz, MC.witchZ - fx
		MC:PlaceBlock( bx2, MC.heights[ bx2 .. "," .. bz2 ] or MC_FLOOR, bz2, "brewing_stand" )
	end
	-- Dota's banners on poles: Minecraft's world has none (and they hid the view)
	local hidden = 0
	for _, e in ipairs( Entities:FindAllByClassname( "prop_dynamic" ) ) do
		local m = e:GetModelName() or ""
		if m:find( "banner" ) or m:find( "flag" ) then e:AddEffects( EF_NODRAW ) hidden = hidden + 1 end
	end
	print( "[mc] banners hidden: " .. hidden )
	for _, t in ipairs( TRADERS ) do
		print( string.format( "[mc] trader %s at %.1f, %.1f", t[3], t[1], t[2] ) )
		local pos = t[6] and ( a + MC:Offset( t[1], t[2] ) + Vector( 0, 0, ( t[6] - MC_FLOOR ) * GRID ) )
			or GetGroundPosition( a + MC:Offset( t[1], t[2] ), nil )
		-- facing: given in Minecraft x, z (across the aisle), else toward the spawn
		local face = t[4] and MC:DirToDota( t[4], t[5] ) or ( a - pos ):Normalized()
		t.yaw = math.deg( math.atan2( face.y, face.x ) ) -- where the counter faces
		t.prop = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/villager_" .. t[3] .. ".vmdl",
			origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ),
			angles = string.format( "0 %f 0", t.yaw + 180 ) } ) -- the model looks -X at yaw 0 (checked on screen)
	end
	MC:SendTraders()
end

-- (traders don't turn toward Steve: Dota sends a prop's angles at 30 Hz without smoothing, so they shook while he walked)

function MC:SendTraders()
	-- (with the ground's Minecraft y: under a stall roof the top block is the roof)
	if MC.spawnX then -- Steve's (re)spawn point, on the market square
		MCBridge:Send( string.format( "spawnat %d %d %d", MC.spawnX, MC.heights[ MC.spawnX .. "," .. MC.spawnZ ] or MC_FLOOR, MC.spawnZ ) )
	end
	for _, t in ipairs( TRADERS ) do
		-- (on a half-step column he stands on top of the slab: half blocks)
		local k = math.floor( t[1] ) .. "," .. math.floor( t[2] )
		local y = t[6] or ( MC.halfh[ k ] and MC_FLOOR + MC.halfh[ k ] / 2 ) or MC.heights[ k ] or MC_FLOOR
		MCBridge:Send( string.format( "trader %.2f %.2f %s %.1f", t[1], t[2], t[3], y ) )
	end
end

-- the emeralds a kill gave, rising over the corpse like Dota's gold number, in Minecraft's emerald green
function MC:Popup( pos, n )
	local p = ParticleManager:CreateParticle( "particles/msg_fx/msg_gold.vpcf", PATTACH_WORLDORIGIN, nil )
	ParticleManager:SetParticleControl( p, 0, pos + Vector( 0, 0, 40 ) ) -- head height for a first-person camera
	ParticleManager:SetParticleControl( p, 1, Vector( 0, n, 0 ) ) -- "+" then the number
	ParticleManager:SetParticleControl( p, 2, Vector( 2.0, #tostring( n ) + 1, 0 ) ) -- seconds, digits
	ParticleManager:SetParticleControl( p, 3, Vector( 85, 255, 85 ) ) -- Minecraft's green (55FF55)
	ParticleManager:ReleaseParticleIndex( p )
end

-- Steve's kills drop Minecraft loot: emeralds (the shop currency) by the unit's gold bounty, food, and from neutrals the
-- crafting materials that fit them (Dota's shops have nothing to mine; the jungle is the "mine")
EMERALD_GOLD = 25 -- gold bounty per emerald
NEUTRAL_LOOT = { -- unit name part -> Minecraft item, count (first match wins; ancients before their small kin)
	{ "black_dragon", "diamond", 2 }, { "black_drake", "diamond", 1 }, { "thunderhide", "diamond", 1 }, { "prowler", "diamond", 1 },
	{ "granite_golem", "diamond", 1 }, { "rock_golem", "iron_ingot", 2 }, { "frostbitten", "diamond", 1 },
	{ "harpy", "feather", 4 }, { "wildkin", "feather", 4 }, { "wolf", "leather", 2 }, { "centaur", "leather", 3 },
	{ "hellbear", "leather", 3 }, { "kobold", "string", 2 }, { "satyr", "string", 3 }, { "gnoll", "flint", 3 },
	{ "troll", "flint", 2 }, { "ogre", "iron_ingot", 1 }, { "golem", "iron_ingot", 2 }, { "ghost", "gunpowder", 2 },
	{ "fel_beast", "gunpowder", 2 }, { "warpine", "oak_log", 6 },
}
-- gold that isn't a kill (a bounty rune) as emeralds, with the same carried-over remainder
function MC:Emeralds( gold )
	MC.goldLeft = ( MC.goldLeft or 0 ) + gold
	local n = math.floor( MC.goldLeft / EMERALD_GOLD )
	MC.goldLeft = MC.goldLeft - n * EMERALD_GOLD
	if n > 0 then
		MCBridge:Send( string.format( "loot %d %d", n, gold ) )
		MCBridge:Send( string.format( "msg +%d изумр. (руна богатства)", n ) )
	end
end

function MC:LootFor( dead )
	local gold, name = dead:GetGoldBounty(), dead:GetUnitName()
	local items = {}
	if dead:IsRealHero() then
		gold = 150 + 10 * dead:GetLevel()
		items = { "golden_apple", 1 }
	elseif dead:IsBuilding() then
		gold = dead:IsTower() and 250 or 150
		items = { "golden_apple", 1, "iron_ingot", 3 }
	elseif name:find( "roshan" ) then -- the Aegis: a totem, plus the rare stuff
		items = { "totem_of_undying", 1, "netherite_ingot", 1, "diamond", 3 }
	elseif dead:IsNeutralUnitType() or dead:GetTeamNumber() == DOTA_TEAM_NEUTRALS then
		-- raw meat, cooked if it died burning (as in Minecraft)
		items = { ( dead.mc_burnUntil or 0 ) > GameRules:GetGameTime() and "cooked_beef" or "beef", RandomInt( 1, 2 ) }
		for _, l in ipairs( NEUTRAL_LOOT ) do
			if name:find( l[1] ) then table.insert( items, l[2] ) table.insert( items, l[3] ) break end
		end
		if #items == 2 then table.insert( items, "leather" ) table.insert( items, 1 ) end -- unknown neutral
	elseif name:find( "siege" ) then
		items = { "gunpowder", 2 }
	elseif RandomInt( 1, 2 ) == 1 then
		items = { "bread", 1 }
	end
	-- (Tormentor: gems and its "shard": two more hearts for good)
	if name:find( "miniboss" ) then
		items = { "diamond", 4, "emerald", 6, "enchanted_golden_apple", 1 }
		MCBridge:Send( "shard" )
	end
	-- every unit pays its own bounty, like gold in Dota: what doesn't make a whole emerald waits for the next kill
	MC.goldLeft = ( MC.goldLeft or 0 ) + gold
	local emeralds = math.floor( MC.goldLeft / EMERALD_GOLD )
	MC.goldLeft = MC.goldLeft - emeralds * EMERALD_GOLD
	local line = string.format( "loot %d %d", emeralds, gold )
	for i = 1, #items, 2 do line = line .. " " .. items[i] .. " " .. items[i + 1] end
	return line
end

-- mining cracks (stage 0..9; anything else removes them): a slightly bigger cracked shell over the block
function MC:Crack( bx, by, bz, stage )
	if MC.crack and not MC.crack:IsNull() then MC.crack:RemoveSelf() end
	MC.crack = nil
	if stage < 0 or stage > 9 then return end
	-- a tree's log column being chopped: the cracks wrap the Dota tree's own trunk (tools/gen_tree_crack.py)
	local tree = MC.treeAt and MC.treeAt[ bx .. "," .. bz ]
	if tree and not tree:IsNull() and tree:IsStanding() then
		local p = tree:GetAbsOrigin()
		MC.crack = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/tree_crack_" .. stage .. ".vmdl",
			origin = string.format( "%f %f %f", p.x, p.y, GetGroundHeight( p, nil ) ) } )
		return
	end
	if not MC.props[ bx .. "," .. by .. "," .. bz ] then return end
	local pos = MC:BlockPos( bx, by, bz ) - Vector( 0, 0, 0.5 )
	MC.crack = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/crack_" .. stage .. ".vmdl",
		origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ), angles = string.format( "0 %f 0", GRID_ROT ) } )
	MC.crack:SetModelScale( ( GRID + 1 ) / 128 ) -- (the crack cube is 128 units: on the block, a hair bigger)
	MC.crack:SetModelScale( GRID / 128 * 1.02 )
end

-- cracks on a block other than the one Steve mines (MC:Crack): a Dota hero's blows, a falling build's (stage -1: none)
MC.cracks = {}
function MC:CrackAt( bx, by, bz, stage )
	local key = bx .. "," .. by .. "," .. bz
	local c = MC.cracks[ key ]
	if c and not c:IsNull() then c:RemoveSelf() end
	MC.cracks[ key ] = nil
	if stage < 0 or stage > 9 or not MC.props[ key ] then return end
	local pos = MC:BlockPos( bx, by, bz ) - Vector( 0, 0, 0.5 )
	MC.cracks[ key ] = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/crack_" .. stage .. ".vmdl",
		origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ), angles = string.format( "0 %f 0", GRID_ROT ) } )
	MC.cracks[ key ]:SetModelScale( ( GRID + 1 ) / 128 )
end

function MC:HideBlock( bx, by, bz )
	local key = bx .. "," .. by .. "," .. bz
	MC:CrackAt( bx, by, bz, -1 )
	MCWorld:Unward( bx, by, bz )
	local p = MC.props[ key ]
	if p and not p:IsNull() then p:RemoveSelf() end
	MC.props[ key ] = nil
end

-- a block vanished in Minecraft: remove it here without drops
function MC:RemoveBlock( bx, bz )
	local b = MC.cells[ bx .. "," .. bz ]
	if b and not b:IsNull() and b:IsAlive() then
		b.mc_silent = true
		b:ForceKill( false )
	end
end

function MC:ToolOf( hero )
	local tier, power = 0, 1
	for slot = 0, 5 do
		local item = hero:GetItemInSlot( slot )
		local p = item and PICKAXES[ item:GetAbilityName() ]
		if p and p[1] > tier then tier, power = p[1], p[2] end
	end
	if MC:IsSteve( hero ) then power = power * 2 end
	return tier, power
end

-- remember what each unit was explicitly told to attack (to tell clicks from auto-attacks)
function MC:OrderFilter( f )
	-- a glyph only from a real player (Dota's team AI spammed it)
	if f.order_type == DOTA_UNIT_ORDER_GLYPH and ( f.issuer_player_id_const < 0 or PlayerResource:IsFakeClient( f.issuer_player_id_const ) ) then return false end
	for _, idx in pairs( f.units ) do
		local u = EntIndexToHScript( idx )
		if u and u.mc_player and not MC.allowOrder then return false end -- Steve moves and attacks from Minecraft only
	end
	-- an order on Steve's stand-in is an order on Steve (MCBridge:Puppet)
	local tgt = f.entindex_target and f.entindex_target > 0 and EntIndexToHScript( f.entindex_target )
	if tgt and tgt.mc_puppet and MCBridge.steve and not MCBridge.steve:IsNull() then f.entindex_target = MCBridge.steve:entindex() end
	for _, idx in pairs( f.units ) do
		EntIndexToHScript( idx ).mc_ordered = f.order_type == DOTA_UNIT_ORDER_ATTACK_TARGET and f.entindex_target or nil
	end
	return true
end

function MC:DamageFilter( f )
	if not f.entindex_victim_const or not f.entindex_attacker_const then return true end
	local victim = EntIndexToHScript( f.entindex_victim_const )
	if victim.mc_player then
		MCBridge:OnSteveDamaged( victim, f.damage, f.entindex_attacker_const )
		return false
	end
	-- Steve's stand-in: an attack on it hits Steve (spells' splash reaches Steve himself, so that is dropped)
	if victim.mc_puppet then
		if not f.entindex_inflictor_const and MCBridge.steve and not MCBridge.steve:IsNull() then
			MCBridge:OnSteveDamaged( MCBridge.steve, f.damage, f.entindex_attacker_const )
		end
		return false
	end
	local attackerUnit = EntIndexToHScript( f.entindex_attacker_const )
	if attackerUnit and attackerUnit.mc_attack then -- Steve's deny: a real Dota attack carrying the Minecraft hit
		f.damage = attackerUnit.mc_attack
		attackerUnit.mc_attack = nil
		return true
	end
	-- a mob creep's attack lands: its Minecraft sound (MC:MobSound)
	if attackerUnit and attackerUnit.mc_mob and not f.entindex_inflictor_const then
		MC:MobSound( attackerUnit, "attack" )
	end
	if victim.mc_mob and attackerUnit and attackerUnit.mc_player then MC:MobSound( victim, "hurt" ) end
	local def = victim.mc_block
	if not def then return true end
	if attackerUnit and attackerUnit.IsBuilding and attackerUnit:IsBuilding() then return false end -- fountains/towers don't mine

	local attacker = EntIndexToHScript( f.entindex_attacker_const )
	if not attacker or attacker.mc_player then return false end -- (Steve breaks blocks in Minecraft)
	local owner = attacker.GetOwner and attacker:GetOwner()
	local hero = attacker:IsRealHero() and attacker or ( owner and owner.IsRealHero and owner:IsRealHero() and owner ) or nil
	if not hero and not attacker:IsHero() and attacker:GetTeamNumber() ~= DOTA_TEAM_BADGUYS then return false end -- (lane creeps don't)
	f.damage = 1 -- a hit per blow, attack or spell, whatever its damage
	victim.mc_mined = true
	local m = victim:FindModifierByName( "modifier_mc_block" )
	if m and m:GetStackCount() < 2 then m:SetStackCount( m:GetStackCount() + 2 ) end -- (its bar shows the breaking)
	local bx, bz = victim.mc_cell:match( "^(%-?%d+),(%-?%d+)$" )
	local by = victim.mc_y or MC.heights[ victim.mc_cell ] or MC_FLOOR
	local stage = math.min( 9, math.floor( 10 * ( 1 - ( victim:GetHealth() - 1 ) / math.max( 1, victim:GetMaxHealth() ) ) ) )
	MC:CrackAt( tonumber( bx ), by, tonumber( bz ), stage )
	MCBridge:Send( string.format( "crack %s %d %s %d", bx, by, bz, stage ) )
	return true
end

function MC:OnKilled( e )
	local dead = EntIndexToHScript( e.entindex_killed )
	local def = dead and dead.mc_block
	local killer = e.entindex_attacker and EntIndexToHScript( e.entindex_attacker )
	if dead and dead.mc_mob then MC:MobSound( dead, "death" ) MC:MobDeath( dead ) end
	if dead and dead.mc_walls then -- a destroyed building: its walls go
		for _, w in ipairs( dead.mc_walls ) do MCBridge:Send( string.format( "unblock %d %d %d", w[1], w[2], w[3] ) ) end
		dead.mc_walls = nil
	end
	if not def then -- Steve's kills give Minecraft experience and loot
		if killer and killer.mc_player and dead and not dead:IsNull() and dead:GetTeamNumber() == killer:GetTeamNumber() then
			print( "[mc] Steve denied " .. dead:GetUnitName() ) -- a real attack did it, so Dota shows the "!" and cuts the XP itself
		end
		if killer and killer.mc_player and dead and not dead:IsNull() and dead:GetTeamNumber() ~= killer:GetTeamNumber() then -- denies give nothing
			local loot = MC:LootFor( dead )
			if dead:GetUnitName():find( "roshan" ) then -- Steve's Roshan: Minecraft's totem only, no Aegis (or cheese) in Dota
				local at = dead:GetAbsOrigin()
				GameRules:GetGameModeEntity():SetContextThink( "mc_noaegis", function()
					for _, d in ipairs( Entities:FindAllByClassnameWithin( "dota_item_drop", at, 800 ) ) do
						local it = d:GetContainedItem()
						if it and not it:IsNull() then it:RemoveSelf() end
						d:RemoveSelf()
					end
				end, 0.1 )
			end
			print( "[mc] Steve killed " .. dead:GetUnitName() .. ": " .. loot )
			MCBridge:Send( loot )
			local emeralds = tonumber( loot:match( "^loot (%d+)" ) ) or 0
			if emeralds > 0 then
				MC:Popup( dead:GetAbsOrigin(), emeralds )
				EmitSoundOnLocationWithCaster( dead:GetAbsOrigin(), "General.Coins", killer ) -- Dota's gold sound
			end
		end
		return
	end
	MC.cells[ dead.mc_cell ] = nil
	dead:AddNoDraw()
	if dead.mc_silent then return end
	local bx, bz = dead.mc_cell:match( "^(%-?%d+),(%-?%d+)$" )
	bx, bz = tonumber( bx ), tonumber( bz )
	local by = dead.mc_y or MC.heights[ dead.mc_cell ] or MC_FLOOR
	MC:HideBlock( bx, by, bz )
	MCBridge:Send( string.format( "unblock %d %d %d", bx, by, bz ) )
	MC:ColumnChanged( bx, bz ) -- (what stood on it comes down in Minecraft, Sync.collapse, and Dota hears of each)
	if killer and killer.IsRealHero and killer:IsRealHero() then
		killer:AddExperience( def.xp, DOTA_ModifyXP_Unspecified, false, true )
	end
end

-- each Dota script file has its own environment; share these with abilities and mc_bridge.lua
_G.Precache, _G.Activate = Precache, Activate -- (addon_game_mode.lua hands them to Dota)
_G.CALIBRATE = CALIBRATE
_G.EMERALD_GOLD, _G.TRADERS, _G.XP_TABLE = EMERALD_GOLD, TRADERS, XP_TABLE
_G.SIGN_MODELS = SIGN_MODELS
_G.GRID_ROT = GRID_ROT
_G.MC, _G.BLOCKS, _G.PICKAXES, _G.GRID, _G.STEVE, _G.FROM_MC, _G.MC_FLOOR = MC, BLOCKS, PICKAXES, GRID, STEVE, FROM_MC, MC_FLOOR

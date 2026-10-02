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
TERRAIN_R = 220 -- max cells around the anchor mirrored into Minecraft (the map's own size usually ends it first)
MC_FLOOR = 0 -- Minecraft y where feet stand on flat ground (the world is a superflat whose top layer is y -1)

require( "mc_bridge" )
LinkLuaModifier( "modifier_mc_block", "modifier_mc_block", LUA_MODIFIER_MOTION_NONE )

function Precache( context )
	for _, m in ipairs({
		"models/mc/stone.vmdl", "models/mc/cobblestone.vmdl", "models/mc/log.vmdl", "models/mc/coal_ore.vmdl",
		"models/mc/iron_ore.vmdl", "models/mc/diamond_ore.vmdl", "models/mc/crafting_table.vmdl",
		"models/mc/dirt.vmdl", "models/mc/sand.vmdl", "models/mc/planks.vmdl",
		"models/mc/crack_0.vmdl", "models/mc/crack_1.vmdl", "models/mc/crack_2.vmdl", "models/mc/crack_3.vmdl", "models/mc/crack_4.vmdl",
		"models/mc/crack_5.vmdl", "models/mc/crack_6.vmdl", "models/mc/crack_7.vmdl", "models/mc/crack_8.vmdl", "models/mc/crack_9.vmdl",
		"models/heroes/undying/undying_minion.vmdl",
		"models/creeps/neutral_creeps/n_creep_troll_skeleton/n_creep_skeleton_melee.vmdl",
	}) do PrecacheResource( "model", m, context ) end
	PrecacheResource( "particle", "particles/units/heroes/hero_clinkz/clinkz_base_attack.vpcf", context )
end

function Activate()
	GameRules.MC = MC
	MC:Init()
end

MC = {}

function MC:Init()
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, 4 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, 0 )
	GameRules:SetSameHeroSelectionEnabled( true )
	GameRules:SetHeroSelectionTime( 30 )
	GameRules:SetStrategyTime( 0 )
	GameRules:SetShowcaseTime( 0 )
	GameRules:SetPreGameTime( 5 )

	local mode = GameRules:GetGameModeEntity()
	GameRules:SetCustomGameSetupAutoLaunchDelay( 0 ) -- one team anyway: skip the team-select screen
	if GameRules:IsCheatMode() or IsInToolsMode() then -- dev runs: no hero pick, no pre-game wait
		mode:SetCustomGameForceHero( STEVE )
		GameRules:SetPreGameTime( 0 )
	end
	-- always noon, like Minecraft's side (time locked there too): Dota's night lighting turns the blocks blue
	mode:SetDaynightCycleDisabled( true )
	GameRules:SetTimeOfDay( 0.5 )
	mode:SetDamageFilter( Dynamic_Wrap( MC, "DamageFilter" ), MC )
	mode:SetExecuteOrderFilter( Dynamic_Wrap( MC, "OrderFilter" ), MC )

	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( MC, "OnSpawned" ), MC )
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
function MC:OnState()
	if GameRules:State_Get() >= DOTA_GAMERULES_STATE_PRE_GAME then GameRules:SetTimeOfDay( 0.5 ) end -- the clock starts at dawn
	if GameRules:State_Get() ~= DOTA_GAMERULES_STATE_STRATEGY_TIME and GameRules:State_Get() ~= DOTA_GAMERULES_STATE_PRE_GAME then return end
	for pid = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
		local player = PlayerResource:IsValidPlayerID( pid ) and PlayerResource:GetPlayer( pid )
		if player and not PlayerResource:HasSelectedHero( pid ) then
			player:SetSelectedHero( STEVE )
		end
	end
end

function MC:OnSpawned( e )
	local hero = EntIndexToHScript( e.entindex )
	if not hero:IsRealHero() or hero.mc_ready then return end
	hero.mc_ready = true
	-- npc_spawned fires while the hero is still at (0,0,0); wait a frame for the real position
	hero:SetContextThink( "mc_setup", function() MC:SetupHero( hero ) end, FrameTime() )
end

function MC:SetupHero( hero )
	if hero:GetUnitName() == STEVE then hero:SetIdleAcquire( false ) end -- no auto-attack in Minecraft

	local place = hero:FindAbilityByName( "mc_place_block" )
	if place then place:SetLevel( 1 ) end

	if not MC.world_done then
		MC.world_done = true
		MC.anchor = hero:GetAbsOrigin() -- Minecraft (0,0) maps here
		-- Dota's own camera controls would fight Minecraft's (launch args alone get overridden by the user's config)
		SendToConsole( "dota_camera_edgemove 0; dota_camera_speed 0; dota_camera_lock 0; dota_camera_fov_min 90; dota_camera_fov_max 90; dota_camera_z_interp_speed 100000; fps_max 60" )
		MC:SendTerrain()
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
function MC:CellOf( pos )
	return math.floor( ( pos.x - MC.anchor.x ) / GRID ), math.floor( -( pos.y - MC.anchor.y ) / GRID )
end

function MC:CellPos( bx, bz )
	return GetGroundPosition( MC.anchor + Vector( ( bx + 0.5 ) * GRID, -( bz + 0.5 ) * GRID, 0 ), nil )
end

MC.cells = {} -- "bx,bz" -> block unit
MC.heights = {} -- "bx,bz" -> Minecraft y of the ground surface there

-- ground height in half blocks above MC_FLOOR (Minecraft rebuilds it with full blocks plus slabs)
function MC:HalfHeightAt( z ) return math.floor( ( z - MC.anchor.z ) / ( GRID / 2 ) + 0.5 ) end
function MC:HeightAt( z ) return MC_FLOOR + math.floor( MC:HalfHeightAt( z ) / 2 ) end

-- Minecraft's invisible floor follows Dota's terrain (1-block steps; autojump takes them)
function MC:SendTerrain()
	-- the Dota map in cells; outside it (and wherever Dota reports garbage heights) Minecraft gets bottomless void
	local a = MC.anchor
	local x1, x2 = math.floor( ( GetWorldMinX() - a.x ) / GRID ), math.floor( ( GetWorldMaxX() - a.x ) / GRID )
	local z1, z2 = math.floor( -( GetWorldMaxY() - a.y ) / GRID ), math.floor( -( GetWorldMinY() - a.y ) / GRID )
	local R = math.min( TERRAIN_R, math.max( -x1, x2, -z1, z2 ) + 6 ) -- a void strip past the map edge, then the border
	MCBridge:Send( string.format( "border %d", 2 * R + 1 ) )
	print( string.format( "[mc] terrain R=%d, map cells x %d..%d z %d..%d", R, x1, x2, z1, z2 ) )
	local function outside( bx, bz )
		return bx < x1 or bx > x2 or bz < z1 or bz > z2 or math.abs( MC:CellPos( bx, bz ).z - a.z ) > 1500
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
	for bx = -R, R do
		for bz = -R, R do
			if outside( bx, bz ) then
				MCBridge:Send( string.format( "void %d %d", bx, bz ) )
			else
				local h = hh( bx, bz )
				-- lowest neighbour: this column's side wall is exposed down to there and must be magenta too
				local low = math.min( h, hh( bx + 1, bz ), hh( bx - 1, bz ), hh( bx, bz + 1 ), hh( bx, bz - 1 ) )
				MC.heights[ bx .. "," .. bz ] = MC_FLOOR + math.floor( h / 2 )
				if h ~= 0 or low ~= 0 then MCBridge:Send( string.format( "h %d %d %d %d", bx, bz, h, low ) ) end
			end
		end
	end
end

-- fromMC: the block came from Minecraft, so don't echo it back
function MC:SpawnBlock( name, pos, fromMC )
	local def = BLOCKS[ name ]
	local bx, bz = MC:CellOf( pos )
	local key = bx .. "," .. bz
	if MC.cells[ key ] and not MC.cells[ key ]:IsNull() then return MC.cells[ key ] end
	local b = CreateUnitByName( name, MC:CellPos( bx, bz ), false, nil, nil, DOTA_TEAM_NEUTRALS )
	b.mc_block, b.mc_cell = def, key
	MC.cells[ key ] = b
	b:AddNewModifier( b, nil, "modifier_mc_block", {} )
	b:SetHullRadius( GRID * 0.375 ) -- neighbours' hulls overlap: Dota heroes can't squeeze between blocks
	if not CALIBRATE then b:AddNoDraw() end -- ponytail: Minecraft draws the block; Dota keeps only the collision (Dota-only players would see nothing)
	if not fromMC then MCBridge:Send( string.format( "block %d %d %d %s", bx, MC.heights[ key ] or MC_FLOOR, bz, def.mc ) ) end
	return b
end

-- Hybrid: Dota draws Minecraft's blocks (any height) as props, so they sit exactly on Dota's map
MC.props = {} -- "x,y,z" -> prop_dynamic
MODELS = { oak_log = "log", oak_planks = "planks", stone = "stone", cobblestone = "cobblestone", dirt = "dirt", sand = "sand",
	coal_ore = "coal_ore", iron_ore = "iron_ore", diamond_ore = "diamond_ore", crafting_table = "crafting_table" }

function MC:ShowBlock( bx, by, bz, kind )
	local key = bx .. "," .. by .. "," .. bz
	MC:HideBlock( bx, by, bz )
	local pos = MC.anchor + Vector( ( bx + 0.5 ) * GRID, -( bz + 0.5 ) * GRID, ( by - MC_FLOOR ) * GRID )
	local p = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/" .. ( MODELS[ kind ] or "cobblestone" ) .. ".vmdl",
		origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ) } )
	p:SetModelScale( GRID / 128 ) -- the cube model is 128 units
	MC.props[ key ] = p
end

-- mining cracks (stage 0..9; anything else removes them): a slightly bigger cracked shell over the block
function MC:Crack( bx, by, bz, stage )
	if MC.crack and not MC.crack:IsNull() then MC.crack:RemoveSelf() end
	MC.crack = nil
	if stage < 0 or stage > 9 or not MC.props[ bx .. "," .. by .. "," .. bz ] then return end
	local pos = MC.anchor + Vector( ( bx + 0.5 ) * GRID, -( bz + 0.5 ) * GRID, ( by - MC_FLOOR ) * GRID - 1 )
	MC.crack = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/crack_" .. stage .. ".vmdl",
		origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ) } )
	MC.crack:SetModelScale( GRID / 128 * 1.02 )
end

function MC:HideBlock( bx, by, bz )
	local key = bx .. "," .. by .. "," .. bz
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
	if hero:GetUnitName() == STEVE then power = power * 2 end
	return tier, power
end

-- remember what each unit was explicitly told to attack (to tell clicks from auto-attacks)
function MC:OrderFilter( f )
	for _, idx in pairs( f.units ) do
		EntIndexToHScript( idx ).mc_ordered = f.order_type == DOTA_UNIT_ORDER_ATTACK_TARGET and f.entindex_target or nil
	end
	return true
end

function MC:DamageFilter( f )
	if not f.entindex_victim_const or not f.entindex_attacker_const then return true end
	local victim = EntIndexToHScript( f.entindex_victim_const )
	if victim.mc_player then
		MCBridge:OnSteveDamaged( victim, f.damage )
		return false
	end
	local def = victim.mc_block
	if not def then return true end

	local attacker = EntIndexToHScript( f.entindex_attacker_const )
	local hero = attacker:IsRealHero() and attacker or attacker:GetOwner()
	if not hero or not hero.IsRealHero or not hero:IsRealHero() then return false end

	local tier, power = MC:ToolOf( hero )
	if tier < def.tier then
		if attacker.mc_ordered == victim:entindex() and ( not hero.mc_warned or GameRules:GetGameTime() - hero.mc_warned > 3 ) then
			hero.mc_warned = GameRules:GetGameTime()
			GameRules:SendCustomMessage( "#mc_need_better_pickaxe", hero:GetPlayerID(), 0 )
		end
		return false
	end
	f.damage = power
	victim:RemoveModifierByName( "modifier_mc_block" ) -- health bar becomes the mining progress
	return true
end

function MC:OnKilled( e )
	local dead = EntIndexToHScript( e.entindex_killed )
	local def = dead and dead.mc_block
	local killer = e.entindex_attacker and EntIndexToHScript( e.entindex_attacker )
	if not def then -- Steve's kills give Minecraft experience (loot only from neutrals, later)
		if killer and killer.mc_player and dead and not dead:IsNull() and dead:GetTeamNumber() ~= killer:GetTeamNumber() then -- denies give nothing
			MCBridge:Send( string.format( "xp %d", math.max( 1, math.floor( dead:GetDeathXP() / 10 ) ) ) )
		end
		return
	end
	MC.cells[ dead.mc_cell ] = nil
	dead:AddNoDraw()
	if dead.mc_silent then return end
	local bx, bz = MC:CellOf( dead:GetAbsOrigin() )
	local by = dead.mc_y or MC.heights[ dead.mc_cell ] or MC_FLOOR
	MC:HideBlock( bx, by, bz )
	MCBridge:Send( string.format( "unblock %d %d %d", bx, by, bz ) )
	local item = CreateItem( def.drop, nil, nil )
	CreateItemOnPositionSync( dead:GetAbsOrigin(), item )
	if killer and killer.IsRealHero and killer:IsRealHero() then
		killer:AddExperience( def.xp, DOTA_ModifyXP_Unspecified, false, true )
	end
end

-- each Dota script file has its own environment; share these with abilities and mc_bridge.lua
_G.CALIBRATE = CALIBRATE
_G.MC, _G.BLOCKS, _G.PICKAXES, _G.GRID, _G.STEVE, _G.FROM_MC, _G.MC_FLOOR = MC, BLOCKS, PICKAXES, GRID, STEVE, FROM_MC, MC_FLOOR

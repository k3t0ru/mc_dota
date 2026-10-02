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
TERRAIN_R = 40 -- cells around the anchor whose height/walkability is mirrored into Minecraft
MC_FLOOR = -60 -- Minecraft y of the block layer standing on the floor

require( "mc_bridge" )
LinkLuaModifier( "modifier_mc_block", "modifier_mc_block", LUA_MODIFIER_MOTION_NONE )

function Precache( context )
	for _, m in ipairs({
		"models/mc/stone.vmdl", "models/mc/cobblestone.vmdl", "models/mc/log.vmdl", "models/mc/coal_ore.vmdl",
		"models/mc/iron_ore.vmdl", "models/mc/diamond_ore.vmdl", "models/mc/crafting_table.vmdl",
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

function MC:HeightAt( z ) return MC_FLOOR + math.floor( ( z - MC.anchor.z ) / GRID + 0.5 ) end

-- Minecraft's invisible floor follows Dota's terrain; where Dota can't be walked (trees, cliffs) it gets a wall
function MC:SendTerrain()
	for bx = -TERRAIN_R, TERRAIN_R do
		for bz = -TERRAIN_R, TERRAIN_R do
			local pos = MC:CellPos( bx, bz )
			local y = MC:HeightAt( pos.z )
			MC.heights[ bx .. "," .. bz ] = y
			if not GridNav:IsTraversable( pos ) or GridNav:IsNearbyTree( pos, 40, true ) then y = y + 3 end
			if y ~= MC_FLOOR then MCBridge:Send( string.format( "h %d %d %d", bx, bz, y ) ) end
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
	b:AddNoDraw() -- ponytail: Minecraft draws the block; Dota keeps only the collision (Dota-only players would see nothing)
	if not fromMC then MCBridge:Send( string.format( "block %d %d %d %s", bx, MC_FLOOR, bz, def.mc ) ) end
	return b
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
	if not def then return end
	MC.cells[ dead.mc_cell ] = nil
	dead:AddNoDraw()
	if dead.mc_silent then return end
	local bx, bz = MC:CellOf( dead:GetAbsOrigin() )
	MCBridge:Send( string.format( "unblock %d %d %d", bx, MC_FLOOR, bz ) )
	local item = CreateItem( def.drop, nil, nil )
	CreateItemOnPositionSync( dead:GetAbsOrigin(), item )
	local killer = e.entindex_attacker and EntIndexToHScript( e.entindex_attacker )
	if killer and killer.IsRealHero and killer:IsRealHero() then
		killer:AddExperience( def.xp, DOTA_ModifyXP_Unspecified, false, true )
	end
end

-- each Dota script file has its own environment; share these with abilities and mc_bridge.lua
_G.MC, _G.BLOCKS, _G.PICKAXES, _G.GRID, _G.STEVE, _G.FROM_MC, _G.MC_FLOOR = MC, BLOCKS, PICKAXES, GRID, STEVE, FROM_MC, MC_FLOOR

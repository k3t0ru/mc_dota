-- Minecraft x Dota: mining, crafting, night mobs.

-- tier = pickaxe tier needed, hp = hits at power 1, drop = item, xp = hero xp on break
BLOCKS = {
	npc_mc_block_log     = { tier = 0, hp = 3,  drop = "item_mc_log",         xp = 5 },
	npc_mc_block_stone   = { tier = 1, hp = 4,  drop = "item_mc_cobblestone", xp = 5 },
	npc_mc_block_coal    = { tier = 1, hp = 4,  drop = "item_mc_coal",        xp = 10 },
	npc_mc_block_iron    = { tier = 2, hp = 6,  drop = "item_mc_iron",        xp = 20 },
	npc_mc_block_diamond = { tier = 3, hp = 10, drop = "item_mc_diamond",     xp = 50 },
}
BLOCKS.npc_mc_block_cobble = BLOCKS.npc_mc_block_stone -- player-placed

-- pickaxe item -> { tier, power }
PICKAXES = {
	item_mc_pickaxe_wood    = { 1, 2 },
	item_mc_pickaxe_stone   = { 2, 3 },
	item_mc_pickaxe_iron    = { 3, 4 },
	item_mc_pickaxe_diamond = { 4, 6 },
}

STEVE = "npc_dota_hero_kunkka" -- ponytail: Steve overrides Kunkka's slot; own hero needs a model from Workshop Tools
GRID = 128
NIGHT_MOBS = { "npc_mc_zombie", "npc_mc_zombie", "npc_mc_skeleton" }

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

	-- every player gets a personal crafting table next to them
	local table = CreateUnitByName( "npc_mc_crafting_table", hero:GetAbsOrigin() + hero:GetForwardVector() * 200, true, hero, hero, hero:GetTeam() )
	table:SetControllableByPlayer( hero:GetPlayerID(), true )
	table:SetOwner( hero )
	table:AddNewModifier( table, nil, "modifier_invulnerable", {} )
	hero.mc_table = table
	print( "[mc] table", table:GetAbsOrigin(), "hero", hero:GetAbsOrigin() )
	for i = 0, table:GetAbilityCount() - 1 do
		local a = table:GetAbilityByIndex( i )
		if a then a:SetLevel( 1 ) end
	end
	local place = hero:FindAbilityByName( "mc_place_block" )
	if place then place:SetLevel( 1 ) end

	if not MC.world_done then
		MC.world_done = true
		MC.anchor = hero:GetAbsOrigin() -- Minecraft (0,0) maps here
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
		timer:SetContextThink( "mc_night", safe( function() return MC:NightThink() end ), 5 )
		timer:SetContextThink( "mc_bridge", safe( function() return MCBridge:Tick() end ), 1 )
		MC:GenerateWorld( hero:GetAbsOrigin() )
	end
end

function MC:SpawnBlock( name, pos )
	local def = BLOCKS[ name ]
	local b = CreateUnitByName( name, pos, false, nil, nil, DOTA_TEAM_NEUTRALS )
	b.mc_block = def
	b:AddNewModifier( b, nil, "modifier_mc_block", {} )
	b:SetForwardVector( Vector( 0, 1, 0 ) )
	return b
end

-- ponytail: random scatter around spawn, rarer ores further out; real caves/biomes come with our own map
function MC:GenerateWorld( center )
	local placed = 0
	for _ = 1, 600 do
		if placed >= 140 then break end
		local d = RandomFloat( 450, 2600 )
		local pos = center + RandomVector( d )
		pos = Vector( math.floor( pos.x / GRID + 0.5 ) * GRID, math.floor( pos.y / GRID + 0.5 ) * GRID, 0 )
		pos = GetGroundPosition( pos, nil )
		if GridNav:IsTraversable( pos ) and not GridNav:IsBlocked( pos ) and #FindUnitsInRadius( DOTA_TEAM_BADGUYS, pos, nil, 90,
			DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL, DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER, false ) == 0 then
			local r, f = RandomFloat( 0, 1 ), d / 2600
			local name = "npc_mc_block_stone"
			if r < 0.25 then name = "npc_mc_block_log"
			elseif r < 0.35 then name = "npc_mc_block_coal"
			elseif r < 0.35 + 0.15 * f then name = "npc_mc_block_iron"
			elseif r < 0.35 + 0.15 * f + 0.06 * f then name = "npc_mc_block_diamond" end
			MC:SpawnBlock( name, pos )
			placed = placed + 1
		end
	end
	print( "[mc] world blocks: " .. placed )
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
	local item = CreateItem( def.drop, nil, nil )
	CreateItemOnPositionSync( dead:GetAbsOrigin(), item )
	local killer = e.entindex_attacker and EntIndexToHScript( e.entindex_attacker )
	if killer and killer.IsRealHero and killer:IsRealHero() then
		killer:AddExperience( def.xp, DOTA_ModifyXP_Unspecified, false, true )
	end
	dead:AddNoDraw()
end

-- night: mobs come for the players; dawn: they burn
function MC:NightThink()
	if GameRules:State_Get() ~= DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then return 5 end
	MC.mobs = MC.mobs or {}
	local alive = {}
	for _, m in ipairs( MC.mobs ) do
		if not m:IsNull() and m:IsAlive() then
			if GameRules:IsDaytime() then m:ForceKill( false ) else table.insert( alive, m ) end
		end
	end
	MC.mobs = alive
	if GameRules:IsDaytime() then return 5 end

	local heroes = HeroList:GetAllHeroes()
	for _, hero in ipairs( heroes ) do
		if hero:IsAlive() and #MC.mobs < 6 * #heroes then
			local pos = hero:GetAbsOrigin() + RandomVector( RandomFloat( 900, 1300 ) )
			if GridNav:IsTraversable( pos ) then
				local level = math.floor( hero:GetLevel() / 3 )
				local mob = CreateUnitByName( NIGHT_MOBS[ RandomInt( 1, #NIGHT_MOBS ) ], pos, true, nil, nil, DOTA_TEAM_BADGUYS )
				mob:CreatureLevelUp( level )
				ExecuteOrderFromTable( { UnitIndex = mob:entindex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = hero:GetAbsOrigin() } )
				table.insert( MC.mobs, mob )
			end
		end
	end
	return 8
end

-- each Dota script file has its own environment; share these with abilities and mc_bridge.lua
_G.MC, _G.BLOCKS, _G.PICKAXES, _G.GRID, _G.STEVE = MC, BLOCKS, PICKAXES, GRID, STEVE

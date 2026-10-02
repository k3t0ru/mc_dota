-- Minecraft x Dota: mining, crafting, night mobs.

-- tier = pickaxe tier needed, hp = hits at power 1, drop = item, xp = hero xp on break
BLOCKS = {
	npc_mc_block_log     = { tier = 0, hp = 3,  drop = "item_mc_log",         xp = 5,  color = { 140, 100, 60 } },
	npc_mc_block_stone   = { tier = 1, hp = 4,  drop = "item_mc_cobblestone", xp = 5,  color = { 150, 150, 150 } },
	npc_mc_block_coal    = { tier = 1, hp = 4,  drop = "item_mc_coal",        xp = 10, color = { 40, 40, 40 } },
	npc_mc_block_iron    = { tier = 2, hp = 6,  drop = "item_mc_iron",        xp = 20, color = { 220, 170, 130 } },
	npc_mc_block_diamond = { tier = 3, hp = 10, drop = "item_mc_diamond",     xp = 50, color = { 80, 230, 230 } },
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

function Precache( context )
	for _, m in ipairs({
		"models/props_rock/riveredge_rock006a.vmdl",
		"models/events/dark_carnival/crate_drop_minigame/crate_drop_crate.vmdl",
		"models/props_structures/shopkeeper_table001.vmdl",
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
	mode:SetThink( "NightThink", MC, "mc_night", 5 )

	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( MC, "OnSpawned" ), MC )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( MC, "OnKilled" ), MC )
	print( "[mc] loaded" )
end

function MC:OnSpawned( e )
	local hero = EntIndexToHScript( e.entindex )
	if not hero:IsRealHero() or hero.mc_ready then return end
	hero.mc_ready = true

	-- every player gets a personal crafting table next to them
	local table = CreateUnitByName( "npc_mc_crafting_table", hero:GetAbsOrigin() + RandomVector( 250 ), true, hero, hero, hero:GetTeam() )
	table:SetControllableByPlayer( hero:GetPlayerID(), true )
	table:SetOwner( hero )
	table:AddNewModifier( table, nil, "modifier_invulnerable", {} )
	hero.mc_table = table
	for i = 0, table:GetAbilityCount() - 1 do
		local a = table:GetAbilityByIndex( i )
		if a then a:SetLevel( 1 ) end
	end
	local place = hero:FindAbilityByName( "mc_place_block" )
	if place then place:SetLevel( 1 ) end

	if not MC.world_done then
		MC.world_done = true
		MC:GenerateWorld( hero:GetAbsOrigin() )
	end
end

function MC:SpawnBlock( name, pos )
	local def = BLOCKS[ name ]
	local b = CreateUnitByName( name, pos, false, nil, nil, DOTA_TEAM_BADGUYS )
	b.mc_block = def
	b:SetRenderColor( def.color[1], def.color[2], def.color[3] )
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

function MC:DamageFilter( f )
	if not f.entindex_victim_const or not f.entindex_attacker_const then return true end
	local victim = EntIndexToHScript( f.entindex_victim_const )
	local def = victim.mc_block
	if not def then return true end

	local attacker = EntIndexToHScript( f.entindex_attacker_const )
	local hero = attacker:IsRealHero() and attacker or attacker:GetOwner()
	if not hero or not hero.IsRealHero or not hero:IsRealHero() then return false end

	local tier, power = MC:ToolOf( hero )
	if tier < def.tier then
		if not hero.mc_warned or GameRules:GetGameTime() - hero.mc_warned > 3 then
			hero.mc_warned = GameRules:GetGameTime()
			GameRules:SendCustomMessage( "#mc_need_better_pickaxe", hero:GetPlayerID(), 0 )
		end
		return false
	end
	f.damage = power
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

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
require( "addon_init" ) -- Lua modifiers (the client loads addon_init.lua by itself)

function Precache( context )
	for _, m in ipairs({
		"models/mc/stone.vmdl", "models/mc/cobblestone.vmdl", "models/mc/log.vmdl", "models/mc/coal_ore.vmdl",
		"models/mc/iron_ore.vmdl", "models/mc/diamond_ore.vmdl", "models/mc/crafting_table.vmdl",
		"models/mc/dirt.vmdl", "models/mc/sand.vmdl", "models/mc/planks.vmdl", "models/mc/spruce_planks.vmdl",
		"models/mc/red_wool.vmdl", "models/mc/white_wool.vmdl", "models/mc/blue_wool.vmdl",
		"models/mc/crack_0.vmdl", "models/mc/crack_1.vmdl", "models/mc/crack_2.vmdl", "models/mc/crack_3.vmdl", "models/mc/crack_4.vmdl",
		"models/mc/crack_5.vmdl", "models/mc/crack_6.vmdl", "models/mc/crack_7.vmdl", "models/mc/crack_8.vmdl", "models/mc/crack_9.vmdl",
		"models/mc/villager_fletcher.vmdl", "models/mc/villager_librarian.vmdl", "models/mc/villager_toolsmith.vmdl", "models/mc/villager_weaponsmith.vmdl", "models/mc/villager_mason.vmdl",
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
	-- a deny gives the denier nothing (Dota hands out XP for the killing attack)
	mode:SetModifyExperienceFilter( function( _, f ) return not ( MCBridge.steve and MCBridge.steve.mc_denying ) end, MC )
	mode:SetModifyGoldFilter( function( _, f ) return not ( MCBridge.steve and MCBridge.steve.mc_denying ) end, MC )
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
	if hero:GetUnitName() == STEVE then hero:SetIdleAcquire( false ) end -- no auto-attack in Minecraft

	local place = hero:FindAbilityByName( "mc_place_block" )
	if place then place:SetLevel( 1 ) end

	if not MC.world_done then
		MC.world_done = true
		MC.anchor = hero:GetAbsOrigin() -- Minecraft (0,0) maps here
		-- Dota's own camera controls would fight Minecraft's (launch args alone get overridden by the user's config)
		SendToConsole( "dota_camera_edgemove 0; dota_camera_speed 0; dota_camera_lock 0; dota_camera_fov_min 90; dota_camera_fov_max 90; dota_camera_z_interp_speed 100000; snd_mute_losefocus 0; snd_musicvolume 0" ) -- Dota's sound plays with Minecraft holding focus; music is Minecraft's
		MC:SendTerrain()
		MC:SpawnTraders()
		-- Panorama's camera playback delay: Minecraft's overlay waits as long (see fpcam.js)
		CustomGameEventManager:RegisterListener( "mc_delay", function( _, e ) MCBridge:Send( "delay " .. math.floor( tonumber( e.d ) or 0 ) ) end )
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
MC.halfh = {} -- "bx,bz" -> the same in half blocks (odd = a slab on top)

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
	-- the world bounds are far bigger than the visible map; past its edge (a rim, then no terrain at all) Dota reports
	-- heights ~16000 below: that is where Minecraft gets its void
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
MODELS = { spruce_planks = "spruce_planks", red_wool = "red_wool", white_wool = "white_wool", blue_wool = "blue_wool",
	oak_log = "log", oak_planks = "planks", stone = "stone", cobblestone = "cobblestone", dirt = "dirt", sand = "sand",
	coal_ore = "coal_ore", iron_ore = "iron_ore", diamond_ore = "diamond_ore", crafting_table = "crafting_table" }

-- Where Dota draws a Minecraft block: at its Minecraft height, so walls and roofs stay level and match what the player
-- walks on. (Drawing each block from Dota's real ground under its cell broke roofs into steps; on a slope a block is
-- off by at most a quarter block, Minecraft's terrain being half-block steps of Dota's ground.)
function MC:BlockPos( bx, by, bz )
	return MC.anchor + Vector( ( bx + 0.5 ) * GRID, -( bz + 0.5 ) * GRID, ( by - MC_FLOOR ) * GRID )
end

function MC:ShowBlock( bx, by, bz, kind )
	local key = bx .. "," .. by .. "," .. bz
	MC:HideBlock( bx, by, bz )
	local pos = MC:BlockPos( bx, by, bz )
	local p = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/" .. ( MODELS[ kind ] or "cobblestone" ) .. ".vmdl",
		origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ) } )
	p:SetModelScale( GRID / 128 ) -- the cube model is 128 units
	p.mc_kind = kind
	MC.props[ key ] = p
end

-- What Dota units can do with a Minecraft column at their height: like a Minecraft player they step up ONE block
-- (walk on top of it), two stacked blocks are a wall. Returns: block at ground level, block one above.
function MC:Column( bx, bz )
	local g = MC.heights[ bx .. "," .. bz ] or MC_FLOOR
	return MC.props[ bx .. "," .. g .. "," .. bz ], MC.props[ bx .. "," .. ( g + 1 ) .. "," .. bz ], g
end

-- a Minecraft block appeared/vanished in this column: keep its Dota block unit (mining target, and a wall when 2 high)
function MC:ColumnChanged( bx, bz )
	local low, high, g = MC:Column( bx, bz )
	if not low and not high then MC:RemoveBlock( bx, bz ) return end
	local b = MC.cells[ bx .. "," .. bz ]
	if not b or b:IsNull() or not b:IsAlive() then
		local top = low or high
		b = MC:SpawnBlock( FROM_MC[ top.mc_kind ] or "npc_mc_block_cobble", MC:CellPos( bx, bz ), true )
	end
	b.mc_y = low and g or g + 1 -- what a Dota hero mines out of this column
	b.mc_protected = MC.protected[ bx .. "," .. bz ]
	local m = b:FindModifierByName( "modifier_mc_block" )
	if m then m:SetStackCount( ( low and not high ) and 1 or 0 ) end -- 1 = walkable: no collision
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
function MC:PlaceBlock( x, y, z, kind )
	MC.protected[ x .. "," .. z ] = true
	MCBridge:Send( string.format( "block %d %d %d %s", x, y, z, kind ) )
	MC:ShowBlock( x, y, z, kind )
	MC:ColumnChanged( x, z )
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
	for _, e in ipairs( Entities:FindAllByClassname( "ent_dota_shop" ) ) do
		if ( e:GetAbsOrigin() - fountain ):Length2D() < 1600 then e:AddEffects( EF_NODRAW ) end
	end
	-- Where the market goes: the open, walkable ground closest to the fountain (the fountain sits in a corner of the
	-- map behind walls and cliffs, so "both sides of it" put a stall on rocks). Tried: both grid orientations, centres
	-- up to 12 cells from the fountain; both stalls (5 x 3) and the aisle between them must be walkable, off the spawn.
	local function walkable( x, z )
		local p = a + Vector( ( x + 0.5 ) * GRID, -( z + 0.5 ) * GRID, 0 )
		return GridNav:IsTraversable( p ) and not GridNav:IsBlocked( p ) and not GridNav:IsNearbyTree( p, 40, true )
	end
	local spawnX, spawnZ = 0, 0 -- Steve respawns at Minecraft 0,0: never wall that in
	local function free( x, z ) return math.abs( x - spawnX ) > 1 or math.abs( z - spawnZ ) > 1 end
	local U, V, mx, mz, bestCost
	for _, o in ipairs( { { { 1, 0 }, { 0, 1 } }, { { 0, 1 }, { 1, 0 } } } ) do
		for ox = -12, 12 do for oz = -12, 12 do
			local ok, x0, z0 = true, cx + ox, cz + oz
			for u = -3, 3 do
				for v = -5, 5 do
					local x, z = x0 + u * o[1][1] + v * o[2][1], z0 + u * o[1][2] + v * o[2][2]
					local stall = math.abs( v ) >= 3 and math.abs( u ) <= 2
					if ( math.abs( v ) <= 5 and math.abs( u ) <= 2 ) and not walkable( x, z ) then ok = false end
					if stall and not free( x, z ) then ok = false end
				end
				if not ok then break end
			end
			local cost = ox * ox + oz * oz
			if ok and ( not bestCost or cost < bestCost ) then U, V, mx, mz, bestCost = o[1], o[2], x0, z0, cost end
		end end
	end
	if not U then U, V, mx, mz = { 1, 0 }, { 0, 1 }, cx + 6, cz end -- nowhere fits: just east of the fountain
	print( string.format( "[mc] market centre %d,%d (fountain %d,%d), aisle along %d,%d", mx, mz, cx, cz, U[1], U[2] ) )
	local function cell( u, v ) return mx + u * U[1] + v * V[1], mz + u * U[2] + v * V[2] end
	local function ground( x, z ) return MC.heights[ x .. "," .. z ] or MC_FLOOR end
	-- Two market stalls (after Dio Rods' "Market Stall") facing each other across an aisle, two traders in each,
	-- told apart by their awnings. Local frame: du along the stall (U), dv across it, +dv = the open front.
	local STALLS = {
		{ v = -4, front = 1, awning = "red_wool", traders = { "fletcher", "mason" } },
		{ v = 4, front = -1, awning = "blue_wool", traders = { "librarian", "toolsmith" } },
	}
	-- the fountain itself between them: Minecraft has nothing there, so the player walked into its basin; invisible
	-- barriers (not drawn by Dota: only Minecraft gets them) keep him out
	for du = -3, 3 do for dv = -3, 3 do
		if du * du + dv * dv <= 10 then
			local x, z = cx + du, cz + dv
			if free( x, z ) then
				local g = ground( x, z )
				for y = g, g + 2 do MCBridge:Send( string.format( "block %d %d %d barrier", x, y, z ) ) end
			end
		end
	end end
	for _, st in ipairs( STALLS ) do
		local function at( du, dv ) return cell( du, st.v + st.front * dv ) end
		local base = -1000 -- the stall stands level on its highest ground; lower columns get a spruce footing
		for du = -2, 2 do for dv = -1, 2 do base = math.max( base, ground( at( du, dv ) ) ) end end
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
			table.insert( TRADERS, { x + 0.5, z + 0.5, prof, st.front * V[1], st.front * V[2], base } )
		end
	end
	-- Dota's shops are trigger_shop volumes (no API tells their type): the secret shop is taken as the nearest one that
	-- is well away from the spawn (the fountain shop is at the spawn); a map with a single shop uses that one
	local best, bestD, any
	for _, e in ipairs( Entities:FindAllByClassname( "trigger_shop" ) ) do
		local x, z = MC:CellOf( e:GetAbsOrigin() )
		local d = math.sqrt( x * x + z * z )
		any = any or { x, z }
		if d > 30 and ( not bestD or d < bestD ) then best, bestD = { x, z }, d end
	end
	local secret = best or any or { 20, 0 }
	table.insert( TRADERS, { secret[1] + 2.5, secret[2] + 0.5, "weaponsmith" } )
	for _, t in ipairs( TRADERS ) do
		print( string.format( "[mc] trader %s at %.1f, %.1f", t[3], t[1], t[2] ) )
		local pos = t[6] and ( a + Vector( t[1] * GRID, -t[2] * GRID, ( t[6] - MC_FLOOR ) * GRID ) )
			or GetGroundPosition( a + Vector( t[1] * GRID, -t[2] * GRID, 0 ), nil )
		-- facing: given in Minecraft x, z (across the aisle), else toward the spawn
		local face = t[4] and Vector( t[4], -t[5], 0 ) or ( a - pos ):Normalized()
		t.yaw = math.deg( math.atan2( face.y, face.x ) ) -- where the counter faces
		t.prop = SpawnEntityFromTableSynchronous( "prop_dynamic", { model = "models/mc/villager_" .. t[3] .. ".vmdl",
			origin = string.format( "%f %f %f", pos.x, pos.y, pos.z ),
			angles = string.format( "0 %f 0", t.yaw + 180 ) } ) -- the model looks -X at yaw 0 (checked on screen)
	end
	MC:SendTraders()
end

-- traders look at Steve when he's close, like Minecraft villagers do (at most 80 degrees off their counter)
function MC:TradersLook( steve )
	for _, t in ipairs( TRADERS ) do
		if t.prop and not t.prop:IsNull() then
			local d = steve and steve:GetAbsOrigin() - t.prop:GetAbsOrigin()
			local yaw = t.yaw
			if d and d:Length2D() < 10 * GRID and d:Length2D() > 1 then
				local off = ( math.deg( math.atan2( d.y, d.x ) ) - t.yaw + 540 ) % 360 - 180
				yaw = t.yaw + math.max( -80, math.min( 80, off ) )
			end
			t.prop:SetAngles( 0, yaw + 180, 0 )
		end
	end
end

function MC:SendTraders()
	-- (with the ground's Minecraft y: under a stall roof the top block is the roof)
	for _, t in ipairs( TRADERS ) do
		local y = t[6] or MC.heights[ math.floor( t[1] ) .. "," .. math.floor( t[2] ) ] or MC_FLOOR
		MCBridge:Send( string.format( "trader %.2f %.2f %s %d", t[1], t[2], t[3], y ) )
	end
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
		items = { "cooked_beef", RandomInt( 1, 2 ) }
		for _, l in ipairs( NEUTRAL_LOOT ) do
			if name:find( l[1] ) then table.insert( items, l[2] ) table.insert( items, l[3] ) break end
		end
		if #items == 2 then table.insert( items, "leather" ) table.insert( items, 1 ) end -- unknown neutral
	elseif name:find( "siege" ) then
		items = { "gunpowder", 2 }
	elseif RandomInt( 1, 2 ) == 1 then
		items = { "bread", 1 }
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
	if stage < 0 or stage > 9 or not MC.props[ bx .. "," .. by .. "," .. bz ] then return end
	local pos = MC:BlockPos( bx, by, bz ) - Vector( 0, 0, 1 )
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
		MCBridge:OnSteveDamaged( victim, f.damage, f.entindex_attacker_const )
		return false
	end
	local attackerUnit = EntIndexToHScript( f.entindex_attacker_const )
	if attackerUnit and attackerUnit.mc_attack then -- Steve's deny: a real Dota attack carrying the Minecraft hit
		f.damage = attackerUnit.mc_attack
		attackerUnit.mc_attack = nil
		return true
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
	if not def then -- Steve's kills give Minecraft experience and loot
		if killer and killer.mc_player and dead and not dead:IsNull() and dead:GetTeamNumber() == killer:GetTeamNumber() then
			print( "[mc] Steve denied " .. dead:GetUnitName() ) -- a real attack did it, so Dota shows the "!" and cuts the XP itself
		end
		if killer and killer.mc_player and dead and not dead:IsNull() and dead:GetTeamNumber() ~= killer:GetTeamNumber() then -- denies give nothing
			MCBridge:Send( string.format( "xp %d", math.max( 1, math.floor( dead:GetDeathXP() / 10 ) ) ) )
			local loot = MC:LootFor( dead )
			print( "[mc] Steve killed " .. dead:GetUnitName() .. ": " .. loot )
			MCBridge:Send( loot )
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
_G.EMERALD_GOLD, _G.TRADERS = EMERALD_GOLD, TRADERS
_G.MC, _G.BLOCKS, _G.PICKAXES, _G.GRID, _G.STEVE, _G.FROM_MC, _G.MC_FLOOR = MC, BLOCKS, PICKAXES, GRID, STEVE, FROM_MC, MC_FLOOR

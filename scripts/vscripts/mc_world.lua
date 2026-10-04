-- Steve and Dota's map objects. Minecraft's right click ("use") acts on what is right in front of him: runes (picked
-- up, their effect becomes a Minecraft effect), outposts and watchers (captured by standing next to them), lotus pools
-- (golden carrots), twin gates (a channel, then the other gate). A swing at a tree with nothing else in reach chops it.
-- Torches are observer wards, soul torches sentry wards (MC:ShowBlock / MC:HideBlock call in here).
MCWorld = MCWorld or {}

USE_RANGE = 220 -- Dota units in front of Steve an object must be within
CAPTURE_TIME = { outpost = 3, lantern = 1.5, gate = 3 } -- seconds standing by it
GATE_COOLDOWN = 30
LOTUS_EVERY, LOTUS_MAX = 180, 6 -- a pool grows a lotus every 3 minutes, up to 6 (Dota's)
TREE_HITS = 3 -- swings to chop a tree

-- Dota's rune effects as Minecraft effects: effect, amplifier (the duration is the Dota modifier's)
RUNE_EFFECTS = {
	modifier_rune_haste = { "speed", 2 }, modifier_rune_doubledamage = { "strength", 1 },
	modifier_rune_regen = { "regeneration", 2 }, modifier_rune_invis = { "invisibility", 0 },
	modifier_rune_arcane = { "haste", 1 }, modifier_rune_shield = { "absorption", 2 },
}

local function steve() local s = MCBridge.steve return s and not s:IsNull() and s:IsAlive() and s or nil end

local function say( text ) MCBridge:Send( "msg " .. text ) end

-- the object of a kind nearest the point a step in front of Steve
local function inFront( list )
	local s = steve()
	if not s then return nil end
	local front = s:GetAbsOrigin() + s:GetForwardVector() * 80
	local best, bd
	for _, e in ipairs( list ) do
		if e and not e:IsNull() then
			local d = ( e:GetAbsOrigin() - front ):Length2D()
			if d <= USE_RANGE + ( e.GetHullRadius and e:GetHullRadius() or 0 ) and ( not bd or d < bd ) then best, bd = e, d end
		end
	end
	return best
end

local function byName( part )
	local out = {}
	for _, u in ipairs( FindUnitsInRadius( DOTA_TEAM_NEUTRALS, Vector( 0, 0, 0 ), nil, 30000, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_ALL, DOTA_UNIT_TARGET_FLAG_INVULNERABLE + DOTA_UNIT_TARGET_FLAG_OUT_OF_WORLD, FIND_ANY_ORDER, false ) ) do
		if u:GetUnitName():find( part ) then table.insert( out, u ) end
	end
	return out
end

-- right click in Minecraft
function MCWorld:Use()
	local s = steve()
	if not s or GameRules:GetGameTime() - ( self.usedAt or 0 ) < 0.3 then return end
	self.usedAt = GameRules:GetGameTime()
	local rune = inFront( Entities:FindAllByClassname( "dota_item_rune" ) )
	if rune then return self:Rune( s, rune ) end
	local pool = inFront( byName( "lotus_pool" ) )
	if pool then return self:Lotus( pool ) end
	local gate = inFront( byName( "twin_gate" ) )
	if gate then return self:StartCapture( gate, "gate" ) end
	local outpost = inFront( byName( "watch_tower" ) )
	if outpost then return self:StartCapture( outpost, "outpost" ) end
	local lantern = inFront( Entities:FindAllByClassname( "npc_dota_lantern" ) )
	if lantern then return self:StartCapture( lantern, "lantern" ) end
end

-- runes: Dota's pickup (its effect on the hero), then the same effect for Minecraft's player
function MCWorld:Rune( s, rune )
	local before = {}
	for _, m in ipairs( s:FindAllModifiers() ) do before[ m ] = true end
	if s.PickupRune then s:PickupRune( rune )
	else -- (no API call in this Dota: the order, let through Steve's order filter)
		MC.allowOrder = true
		ExecuteOrderFromTable( { UnitIndex = s:entindex(), OrderType = DOTA_UNIT_ORDER_PICKUP_RUNE, TargetIndex = rune:entindex() } )
		MC.allowOrder = false
	end
	s:SetContextThink( "mc_rune", function()
		for _, m in ipairs( s:FindAllModifiers() ) do
			local e = not before[ m ] and RUNE_EFFECTS[ m:GetName() ]
			if e then
				local sec = math.max( 1, math.floor( m:GetRemainingTime() > 0 and m:GetRemainingTime() or 30 ) )
				MCBridge:Send( string.format( "buff %s %d %d", e[1], sec, e[2] ) )
			end
		end
	end, 0.1 )
end

-- a lotus pool: every lotus it grew since it was last picked becomes a golden carrot
function MCWorld:Lotus( pool )
	local t = GameRules:GetDOTATime( false, false )
	pool.mc_lotusAt = pool.mc_lotusAt or 0
	local n = math.min( LOTUS_MAX, math.floor( ( t - pool.mc_lotusAt ) / LOTUS_EVERY ) )
	if n <= 0 then say( "Лотусов пока нет" ) return end
	pool.mc_lotusAt = t
	MCBridge:Send( string.format( "loot 0 0 golden_carrot %d", n ) )
end

-- outposts, watchers, twin gates: Steve stands next to it for a moment ("use" starts it, walking off cancels)
function MCWorld:StartCapture( u, kind )
	local s = steve()
	if kind == "gate" and GameRules:GetGameTime() < ( self.gateReady or 0 ) then
		say( string.format( "Портал перезаряжается: %d с", math.ceil( self.gateReady - GameRules:GetGameTime() ) ) )
		return
	end
	if kind ~= "gate" and u:GetTeamNumber() == s:GetTeamNumber() then return end
	self.capture = { unit = u, kind = kind, done = GameRules:GetGameTime() + CAPTURE_TIME[ kind ] }
	say( kind == "gate" and "Портал..." or "Захват..." )
end

function MCWorld:Think()
	local s = steve()
	local c = self.capture
	if c then
		if not s or c.unit:IsNull() or ( c.unit:GetAbsOrigin() - s:GetAbsOrigin() ):Length2D() > USE_RANGE + 200 then
			self.capture = nil
			say( "Прервано" )
		elseif GameRules:GetGameTime() >= c.done then
			self.capture = nil
			if c.kind == "gate" then self:Gate( s, c.unit )
			else
				c.unit:SetTeam( s:GetTeamNumber() )
				c.unit:SetOwner( s )
				say( c.kind == "outpost" and "Аванпост захвачен" or "Смотритель захвачен" )
			end
		end
	end
	-- wards whose Dota unit died (an enemy killed it): their torch goes too
	for key, w in pairs( MC.wards or {} ) do
		if w.unit:IsNull() or not w.unit:IsAlive() then
			MC.wards[ key ] = nil
			MCBridge:Send( string.format( "unblock %d %d %d", w.x, w.y, w.z ) )
		end
	end
end

-- through a twin gate: to the other one, a little in front of it (toward the map's middle)
function MCWorld:Gate( s, from )
	local to
	for _, g in ipairs( byName( "twin_gate" ) ) do if g ~= from then to = g end end
	if not to then return end
	self.gateReady = GameRules:GetGameTime() + GATE_COOLDOWN
	local p = to:GetAbsOrigin()
	p = p + ( Vector( 0, 0, 0 ) - p ):Normalized() * 250
	local bx, bz = MC:CellOf( p )
	local y = MC.heights[ bx .. "," .. bz ] or MC_FLOOR
	MCBridge:Send( string.format( "tp %d %d %d", bx, y, bz ) )
end

-- a swing with nothing in reach: a tree in front gets chopped (TREE_HITS swings), giving logs
function MCWorld:Chop()
	local s = steve()
	if not s then return end
	local front = s:GetAbsOrigin() + s:GetForwardVector() * 100
	local best, bd
	for _, t in ipairs( GridNav:GetAllTreesAroundPoint( front, 120, true ) ) do
		if t:IsStanding() then
			local d = ( t:GetAbsOrigin() - front ):Length2D()
			if not bd or d < bd then best, bd = t, d end
		end
	end
	if not best then return end
	best.mc_hits = ( best.mc_hits or 0 ) + 1
	if best.mc_hits < TREE_HITS then return end
	best.mc_hits = 0
	best:CutDown( s:GetTeamNumber() )
	MCBridge:Send( "loot 0 0 oak_log 2" )
end

-- torches: wards. kind = "observer" or "sentry" (MC.wards: "x,y,z" -> { unit, x, y, z })
function MCWorld:Ward( bx, by, bz, kind )
	MC.wards = MC.wards or {}
	local s = steve()
	if not s then return end
	local key = bx .. "," .. by .. "," .. bz
	if MC.wards[ key ] then return end
	local pos = MC:BlockPos( bx, by, bz )
	local u = CreateUnitByName( kind == "sentry" and "npc_dota_sentry_wards" or "npc_dota_observer_wards", pos, false, s, s, s:GetTeamNumber() )
	if not u then return end
	u:AddNoDraw() -- the torch is what you see
	u:AddNewModifier( u, nil, "modifier_kill", { duration = kind == "sentry" and 420 or 360 } )
	if kind == "sentry" then u:AddNewModifier( u, nil, "modifier_mc_truesight", {} ) end
	MC.wards[ key ] = { unit = u, x = bx, y = by, z = bz }
end

function MCWorld:Unward( bx, by, bz )
	if not MC.wards then return end
	local key = bx .. "," .. by .. "," .. bz
	local w = MC.wards[ key ]
	if not w then return end
	MC.wards[ key ] = nil
	if not w.unit:IsNull() and w.unit:IsAlive() then w.unit:ForceKill( false ) end
end

WARD_KINDS = { torch = "observer", wall_torch = "observer", soul_torch = "sentry", soul_wall_torch = "sentry" }

_G.MCWorld = MCWorld

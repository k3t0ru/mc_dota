-- Steve and Dota's map objects. Minecraft's right click ("use") acts on what is right in front of him: runes (picked
-- up, their effect becomes a Minecraft effect), outposts and watchers (captured by standing next to them), lotus pools
-- (golden carrots), twin gates (a channel, then the other gate). A swing at a tree with nothing else in reach chops it.
-- Torches are observer wards, soul torches sentry wards (MC:ShowBlock / MC:HideBlock call in here).
MCWorld = MCWorld or {}

USE_RANGE = 220 -- Dota units in front of Steve an object must be within
CAPTURE_TIME = { outpost = 3, lantern = 1.5, gate = 3.5 } -- seconds standing by it (gate: Dota's channel)
CAPTURE_VISION = { outpost = 900, lantern = 1100 } -- what a captured one shows around it

-- Dota's rune effects as Minecraft effects: effect, amplifier (the duration is the Dota modifier's)
-- (double damage is Lua's: MCBridge's swing x2; illusions become Minecraft's resistance: Kunkka's illusions served no one)
RUNE_EFFECTS = {
	modifier_rune_haste = { "speed", 3 }, -- Dota's max speed: ~1.8x
	modifier_rune_regen = { "regeneration", 3 }, modifier_rune_invis = { "invisibility", 0 },
	modifier_rune_arcane = { "haste", 1 }, modifier_rune_shield = { "absorption", 2 }, -- ~half his health as a shield
	modifier_rune_doubledamage = { "glowing", 0 }, -- (just a sign it's on; the damage is Lua's)
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
	local gate = inFront( byName( "twin_gate" ) )
	if gate then return self:StartCapture( gate, "gate" ) end
	local outpost = inFront( byName( "watch_tower" ) )
	if outpost then return self:StartCapture( outpost, "outpost" ) end
	local lantern = inFront( Entities:FindAllByClassname( "npc_dota_lantern" ) )
	if lantern then return self:StartCapture( lantern, "lantern" ) end
end

-- runes: Dota's pickup (its effect on the hero; RuneEffects mirrors it into Minecraft)
function MCWorld:Rune( s, rune )
	local ok, kind = pcall( function() return rune:GetRuneType() end )
	if s.PickupRune then s:PickupRune( rune )
	else -- (no API call in this Dota: the order, let through Steve's order filter)
		MC.allowOrder = true
		ExecuteOrderFromTable( { UnitIndex = s:entindex(), OrderType = DOTA_UNIT_ORDER_PICKUP_RUNE, TargetIndex = rune:entindex() } )
		MC.allowOrder = false
	end
	if ok and kind == DOTA_RUNE_WATER then MCBridge:Send( "buff instant_health 1 1" ) end
	-- the illusion rune's Kunkkas (nobody could lead them): gone; Steve gets Minecraft's resistance for as long instead
	s:SetContextThink( "mc_illusions", function()
		local any = false
		for _, u in ipairs( FindUnitsInRadius( s:GetTeamNumber(), s:GetAbsOrigin(), nil, 2000, DOTA_UNIT_TARGET_TEAM_FRIENDLY,
			DOTA_UNIT_TARGET_HERO, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false ) ) do
			if u:IsIllusion() and u:GetPlayerOwnerID() == s:GetPlayerOwnerID() then u:RemoveSelf() any = true end
		end
		if any then MCBridge:Send( "buff resistance 75 1" ) end
	end, 0.2 )
end

-- lotuses: Kunkka picks them up standing in a pool (Dota's own); each one becomes a golden carrot
LOTUS_ITEMS = { item_famango = 1, item_great_famango = 2, item_greater_famango = 3 }
function MCWorld:Lotuses( s )
	for slot = 0, 16 do
		local it = s:GetItemInSlot( slot )
		local n = it and LOTUS_ITEMS[ it:GetAbilityName() ]
		if n then
			n = n * math.max( 1, it:GetCurrentCharges() )
			s:RemoveItem( it )
			MCBridge:Send( string.format( "loot 0 0 golden_carrot %d", n ) )
		end
	end
end

-- outposts, watchers, twin gates: Steve stands next to it for a moment ("use" starts it, walking off cancels)
function MCWorld:StartCapture( u, kind )
	local s = steve()
	if kind ~= "gate" and u:GetTeamNumber() == s:GetTeamNumber() then return end
	if kind == "gate" then -- Dota's sound and look of a portal channel
		EmitSoundOn( "Portal.Loop_Appear", s )
		self.gateFx = ParticleManager:CreateParticle( "particles/items2_fx/teleport_start.vpcf", PATTACH_ABSORIGIN, s )
	end
	self.capture = { unit = u, kind = kind, done = GameRules:GetGameTime() + CAPTURE_TIME[ kind ] }
	say( kind == "gate" and "Портал..." or "Захват..." )
end

function MCWorld:Think()
	local s = steve()
	local c = self.capture
	if c then
		if not s or c.unit:IsNull() or ( c.unit:GetAbsOrigin() - s:GetAbsOrigin() ):Length2D() > USE_RANGE + 200 then
			self.capture = nil
			self:GateFxEnd( s )
			say( "Прервано" )
		elseif GameRules:GetGameTime() >= c.done then
			self.capture = nil
			if c.kind == "gate" then self:Gate( s, c.unit )
			else
				c.unit:SetTeam( s:GetTeamNumber() )
				c.unit:SetOwner( s )
				AddFOWViewer( s:GetTeamNumber(), c.unit:GetAbsOrigin(), CAPTURE_VISION[ c.kind ], 99999, false ) -- it sees for us
				say( c.kind == "outpost" and "Аванпост захвачен" or "Смотритель захвачен" )
			end
		end
	end
	if s then self:Lotuses( s ) self:RuneEffects( s ) end
	self:TreesBack()
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
	self:GateFxEnd( s )
	if not to then return end
	local p = to:GetAbsOrigin()
	p = p + ( Vector( 0, 0, 0 ) - p ):Normalized() * 250
	local bx, bz = MC:CellOf( p )
	local y = MC.heights[ bx .. "," .. bz ] or MC_FLOOR
	MCBridge:Send( string.format( "tp %d %d %d", bx, y, bz ) )
	EmitSoundOnLocationWithCaster( p, "Portal.Hero_Appear", s )
	local fx = ParticleManager:CreateParticle( "particles/items2_fx/teleport_end.vpcf", PATTACH_WORLDORIGIN, nil )
	ParticleManager:SetParticleControl( fx, 0, p )
	ParticleManager:SetParticleControl( fx, 1, p )
	ParticleManager:ReleaseParticleIndex( fx )
end

function MCWorld:GateFxEnd( s )
	if s then StopSoundOn( "Portal.Loop_Appear", s ) end
	if self.gateFx then
		ParticleManager:DestroyParticle( self.gateFx, false )
		ParticleManager:ReleaseParticleIndex( self.gateFx )
		self.gateFx = nil
	end
end

-- Dota's trees in Minecraft: an invisible hitbox exactly at each tree (Trees.java), chopped like Minecraft wood
-- ("chop <id>" from Minecraft); "tree <id> <x> <y> <z>" in Minecraft's coordinates
function MCWorld:TreeLine( t )
	local a, p = MC.anchor, t:GetAbsOrigin()
	local x, z = ( p.x - a.x ) / GRID, -( p.y - a.y ) / GRID
	local bx, bz = math.floor( x ), math.floor( z )
	local h = MC.halfh[ bx .. "," .. bz ]
	local y = h and MC_FLOOR + h / 2 or ( MC.heights[ bx .. "," .. bz ] or MC_FLOOR )
	return string.format( "tree %d %.3f %.2f %.3f", t:GetEntityIndex(), x, y, z )
end

function MCWorld:SendTrees()
	self.cut = {}
	local n = 0
	for _, t in ipairs( GridNav:GetAllTreesAroundPoint( Vector( 0, 0, 0 ), 30000, true ) ) do
		if t:IsStanding() then
			MCBridge:Send( self:TreeLine( t ) )
			n = n + 1
		end
	end
	print( "[mc] trees sent: " .. n )
	ListenToGameEvent( "tree_cut", function( e ) -- cut in Dota (a tango, a quelling blade...): its logs go too
		local p = Vector( e.tree_x, e.tree_y, 0 )
		for _, t in ipairs( GridNav:GetAllTreesAroundPoint( p, 40, true ) ) do
			MCBridge:Send( "untree " .. t:GetEntityIndex() )
			self.cut[ t ] = true
		end
	end, nil )
end

-- Minecraft chopped tree <id>: Dota cuts it
function MCWorld:Chop( id )
	local s = steve()
	local t = EntIndexToHScript( id )
	if t and not t:IsNull() and t:IsStanding() then
		t:CutDown( s and s:GetTeamNumber() or DOTA_TEAM_GOODGUYS )
		self.cut[ t ] = true
	end
end

-- Dota grows its trees back after a while: so does Minecraft
function MCWorld:TreesBack()
	if GameRules:GetGameTime() - ( self.treesAt or 0 ) < 3 then return end
	self.treesAt = GameRules:GetGameTime()
	for t in pairs( self.cut or {} ) do
		if t:IsNull() then self.cut[ t ] = nil
		elseif t:IsStanding() then
			self.cut[ t ] = nil
			MCBridge:Send( self:TreeLine( t ) )
		end
	end
end

-- a swing at a rune in front breaks it: picked up, like a click
function MCWorld:SwingRune()
	local s = steve()
	local rune = s and inFront( Entities:FindAllByClassname( "dota_item_rune" ) )
	if rune then self:Rune( s, rune ) return true end
	return false
end

-- runes' effects follow Dota's: a Minecraft effect while the Dota modifier lasts (and cleared when it ends early:
-- the regeneration rune stops when he's hit, invisibility when he attacks)
function MCWorld:RuneEffects( s )
	self.buffs = self.buffs or {}
	local now = {}
	for _, m in ipairs( s:FindAllModifiers() ) do
		local e = RUNE_EFFECTS[ m:GetName() ]
		if e then
			now[ m:GetName() ] = true
			if not self.buffs[ m:GetName() ] then
				local sec = math.max( 1, math.floor( m:GetRemainingTime() > 0 and m:GetRemainingTime() or 30 ) )
				MCBridge:Send( string.format( "buff %s %d %d", e[1], sec, e[2] ) )
			end
		end
	end
	for name in pairs( self.buffs ) do
		if not now[ name ] then MCBridge:Send( "unbuff " .. RUNE_EFFECTS[ name ][1] ) end
	end
	self.buffs = now
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
	-- on a tower of 4+ blocks it sees like a ward on a cliff
	if by - ( MC.heights[ bx .. "," .. bz ] or MC_FLOOR ) >= 4 then u:AddNewModifier( u, nil, "modifier_mc_highground", {} ) end
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

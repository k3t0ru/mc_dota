-- Steve and Dota's map objects. Minecraft's right click ("use") acts on what is right in front of him: runes (picked
-- up, their effect becomes a Minecraft effect), outposts and watchers (captured by standing next to them), lotus pools
-- (golden carrots), twin gates (a channel, then the other gate). A swing at a tree with nothing else in reach chops it.
-- Torches are observer wards, soul torches sentry wards (MC:ShowBlock / MC:HideBlock call in here).
MCWorld = MCWorld or {}

USE_RANGE = 220 -- Dota units in front of Steve an object must be within
CAPTURE_TIME = { outpost = 3, lantern = 1.5, gate = 3.5 } -- seconds standing by it (gate: Dota's channel)
CAPTURE_VISION = { outpost = 900, lantern = 1100 } -- what a captured one shows around it

-- Dota's rune effects as Minecraft effects: effect, amplifier (the duration is the Dota modifier's)
-- (double damage is Lua's: MCBridge's swing x2; the illusion rune does nothing: Kunkka's illusions served no one)
RUNE_EFFECTS = { -- our own Minecraft effects (RuneEffects.java): the rune's name, icon and what it does
	modifier_rune_haste = { "mcdota:rune_haste", 0 }, modifier_rune_doubledamage = { "mcdota:rune_double_damage", 0 },
	modifier_rune_regen = { "mcdota:rune_regen", 0 }, modifier_rune_invis = { "mcdota:rune_invis", 0 },
	modifier_rune_arcane = { "mcdota:rune_arcane", 0 }, modifier_rune_shield = { "mcdota:rune_shield", 0 },
}
-- what Minecraft's player reads when he takes one
RUNE_NAMES = {
	modifier_rune_haste = "Руна ускорения", modifier_rune_doubledamage = "Руна двойного урона", modifier_rune_regen = "Руна регенерации",
	modifier_rune_invis = "Руна невидимости", modifier_rune_arcane = "Руна волшебства", modifier_rune_shield = "Руна щита",
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

-- the rune Steve looks at: in reach and within ~20 degrees of where he faces
local function runeAimed()
	local s = steve()
	if not s then return nil end
	local best, bd
	for _, r in ipairs( Entities:FindAllByClassname( "dota_item_rune" ) ) do
		local d = r:GetAbsOrigin() - s:GetAbsOrigin()
		d.z = 0
		local len = d:Length2D()
		if len <= 200 and ( len < 60 or d:Normalized():Dot( s:GetForwardVector() ) > 0.94 ) and ( not bd or len < bd ) then best, bd = r, len end
	end
	return best
end

-- right click in Minecraft
function MCWorld:Use()
	local s = steve()
	if not s or GameRules:GetGameTime() - ( self.usedAt or 0 ) < 0.3 then return end
	self.usedAt = GameRules:GetGameTime()
	local rune = runeAimed()
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
	local water = ( ok and kind == DOTA_RUNE_WATER ) or ( rune:GetModelName() or "" ):find( "water" )
	if s.PickupRune then s:PickupRune( rune )
	else -- (no API call in this Dota: the order, let through Steve's order filter; then a stop, so an order that
		-- didn't reach doesn't wait to pick it up later when he walks by)
		MC.allowOrder = true
		ExecuteOrderFromTable( { UnitIndex = s:entindex(), OrderType = DOTA_UNIT_ORDER_PICKUP_RUNE, TargetIndex = rune:entindex() } )
		MC.allowOrder = false
		s:SetContextThink( "mc_runestop", function()
			MC.allowOrder = true
			ExecuteOrderFromTable( { UnitIndex = s:entindex(), OrderType = DOTA_UNIT_ORDER_STOP } )
			MC.allowOrder = false
		end, 0.15 )
	end
	if water then -- (no modifier: a moment's heal)
		MCBridge:Send( "buff instant_health 1 1" )
		MCBridge:Send( "msg Руна воды" )
	end
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
	if s then self:Lotuses( s ) self:RuneEffects( s ) self:NoIllusions( s ) end
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
	EmitSoundOnLocationWithCaster( p, "Portal.Hero_Appear", s ) -- (no arrival effect: it showed after he was there)
end

function MCWorld:GateFxEnd( s )
	if s then StopSoundOn( "Portal.Loop_Appear", s ) end
	if self.gateFx then
		ParticleManager:DestroyParticle( self.gateFx, false )
		ParticleManager:ReleaseParticleIndex( self.gateFx )
		self.gateFx = nil
	end
end

-- Dota's trees in Minecraft: magenta log columns (Sync "tree"), chopped like Minecraft wood ("chop" from Minecraft)
function MCWorld:SendTrees()
	self.cut = {}
	MC.treeAt = {} -- "bx,bz" -> the Dota tree on that column (cracks go on its trunk: MC:Crack)
	local n = 0
	for _, t in ipairs( GridNav:GetAllTreesAroundPoint( Vector( 0, 0, 0 ), 30000, true ) ) do
		if t:IsStanding() then
			local bx, bz = MC:CellOf( t:GetAbsOrigin() )
			MCBridge:Send( string.format( "tree %d %d", bx, bz ) )
			MC.treeAt[ bx .. "," .. bz ] = t
			n = n + 1
		end
	end
	print( "[mc] trees sent: " .. n )
	ListenToGameEvent( "tree_cut", function( e ) -- cut in Dota (a tango, a quelling blade...): its logs go too
		local p = Vector( e.tree_x, e.tree_y, 0 )
		local bx, bz = MC:CellOf( p )
		MCBridge:Send( string.format( "untree %d %d", bx, bz ) )
		for _, t in ipairs( GridNav:GetAllTreesAroundPoint( p, 40, true ) ) do self.cut[ t ] = true end
	end, nil )
end

-- Minecraft chopped the column at x, z: Dota cuts its tree
function MCWorld:Chop( bx, bz )
	local s = steve()
	local p = MC:CellPos( bx, bz )
	local best, bd
	for _, t in ipairs( GridNav:GetAllTreesAroundPoint( p, GRID, true ) ) do
		if t:IsStanding() then
			local d = ( t:GetAbsOrigin() - p ):Length2D()
			if not bd or d < bd then best, bd = t, d end
		end
	end
	if best then
		best:CutDown( s and s:GetTeamNumber() or DOTA_TEAM_GOODGUYS )
		self.cut[ best ] = true
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
			local bx, bz = MC:CellOf( t:GetAbsOrigin() )
			MCBridge:Send( string.format( "tree %d %d", bx, bz ) )
			MC.treeAt[ bx .. "," .. bz ] = t
		end
	end
end

-- a swing at a rune in front breaks it: picked up, like a click
function MCWorld:SwingRune()
	local s = steve()
	local rune = s and runeAimed()
	if rune then self:Rune( s, rune ) return true end
	return false
end

-- the illusion rune's Kunkkas (nobody could lead them): gone as soon as they appear; the rune does nothing, and says so
function MCWorld:NoIllusions( s )
	local any = false
	for _, h in ipairs( HeroList:GetAllHeroes() ) do
		if h:IsIllusion() and h:GetPlayerOwnerID() == s:GetPlayerOwnerID() then h:RemoveSelf() any = true end
	end
	if any and GameRules:GetGameTime() - ( self.illusionSaid or -10 ) > 3 then
		self.illusionSaid = GameRules:GetGameTime()
		MCBridge:Send( "msg Странно, похоже эта руна никак не подействовала..." )
	end
end

-- runes' effects follow Dota's: a Minecraft effect while the Dota modifier lasts (and cleared when it ends early:
-- the regeneration rune stops when he's hit, invisibility when he attacks)
function MCWorld:RuneEffects( s )
	self.buffs = self.buffs or {}
	local now = {}
	for _, m in ipairs( s:FindAllModifiers() ) do
		local e = RUNE_EFFECTS[ m:GetName() ] or ( RUNE_NAMES[ m:GetName() ] and {} )
		if e then
			now[ m:GetName() ] = true
			if not self.buffs[ m:GetName() ] then
				if RUNE_NAMES[ m:GetName() ] then MCBridge:Send( "msg " .. RUNE_NAMES[ m:GetName() ] ) end
				local sec = math.max( 1, math.floor( m:GetRemainingTime() > 0 and m:GetRemainingTime() or 30 ) )
				if e[1] then MCBridge:Send( string.format( "buff %s %d %d", e[1], sec, e[2] ) ) end
			end
		end
	end
	for name in pairs( self.buffs ) do
		if not now[ name ] and RUNE_EFFECTS[ name ] then MCBridge:Send( "unbuff " .. RUNE_EFFECTS[ name ][1] ) end
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
	u:AddNewModifier( u, nil, "modifier_invisible", {} ) -- (enemies need true sight, like for Dota's wards)
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

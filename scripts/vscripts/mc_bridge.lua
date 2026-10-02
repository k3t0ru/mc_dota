-- Exchange with Minecraft through bridge/bridge.py (protocol at the top of that file). Coordinates on the wire are
-- Minecraft blocks: 1 block = GRID (64) Dota units, MC (0,0) = MC.anchor. The Minecraft player drives the Steve hero;
-- Dota heroes get invisible stand-ins in Minecraft so swords can hit them; blocks exist on both sides.
BRIDGE_URL = "http://127.0.0.1:27100/sync"
DMG_TO_DOTA = 10  -- 1 MC hp of damage to a hero stand-in = 10 Dota damage
DOTA_TO_MC = 0.02 -- 1 Dota damage to Steve = 0.02 MC hp (a 50-damage hit = half a heart)

MCBridge = { out = { "reset" }, busy = false, sentAt = 0 } -- a new Dota game starts Minecraft's arena from scratch

function MCBridge:Send( line ) table.insert( self.out, line ) end

local function to_mc( p ) return ( p.x - MC.anchor.x ) / GRID, -( p.y - MC.anchor.y ) / GRID end
local function to_dota( x, z ) return GetGroundPosition( MC.anchor + Vector( x * GRID, -z * GRID, 0 ), nil ) end

function MCBridge:Tick()
	if not MC.anchor then return 0.1 end
	if self.busy and GameRules:GetGameTime() - self.sentAt < 2 then return FrameTime() end -- a request to a dead bridge never answers
	self.sentAt = GameRules:GetGameTime()

	local a = MC.anchor
	local lines = { string.format( "anchor %.1f %.1f %.1f", a.x, a.y, a.z ) }
	-- every living Dota unit near Steve gets a stand-in in Minecraft (heroes, creeps, neutrals)
	local center = self.steve and self.steve:GetAbsOrigin() or MC.anchor
	for _, h in ipairs( FindUnitsInRadius( DOTA_TEAM_GOODGUYS, center, nil, 2500, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false ) ) do
		if h:IsAlive() and not h.mc_player and not h.mc_block and not h:IsInvulnerable() then
			local p = h:GetAbsOrigin()
			local x, z = to_mc( p )
			table.insert( lines, string.format( "hero %d %s %.2f %.2f %d %d %d", h:entindex(),
				( h:GetUnitName():gsub( "npc_dota_hero_", "" ):gsub( "npc_dota_", "" ) ), x, z, h:GetHealth(), h:GetMaxHealth(), MC:HeightAt( p.z ) ) )
		end
	end
	for _, l in ipairs( self.out ) do table.insert( lines, l ) end
	local sent = self.out
	self.out = {}

	self.busy = true
	local req = CreateHTTPRequestScriptVM( "POST", BRIDGE_URL )
	req:SetHTTPRequestAbsoluteTimeoutMS( 1000 )
	req:SetHTTPRequestRawPostBody( "text/plain", table.concat( lines, "\n" ) )
	req:Send( function( res )
		self.busy = false
		if res.StatusCode ~= 200 then
			for _, l in ipairs( sent ) do table.insert( self.out, l ) end -- keep block updates for the next try
			if not self.warned then self.warned = true print( "[mc] bridge offline: " .. tostring( res.StatusCode ) ) end
			return
		end
		if self.warned ~= false then self.warned = false print( "[mc] bridge online" ) end
		self:Apply( res.Body or "" )
	end )
	return FrameTime()
end

function MCBridge:Apply( body )
	for line in body:gmatch( "[^\n]+" ) do
		local name, x, z, hp, max, yaw = line:match( "^steve (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)" )
		if name then self:MoveSteve( name, to_dota( tonumber( x ), tonumber( z ) ), tonumber( hp ) / tonumber( max ), math.rad( tonumber( yaw ) ) ) end

		local id, amount = line:match( "^hit (%d+) (%S+)" )
		local hero = id and EntIndexToHScript( tonumber( id ) )
		if hero and hero:IsAlive() then
			ApplyDamage( { victim = hero, attacker = self.steve or hero, damage = tonumber( amount ) * DMG_TO_DOTA, damage_type = DAMAGE_TYPE_PURE } )
		end

		local bx, by, bz, kind = line:match( "^mcblock (%S+) (%S+) (%S+) (%S+)" )
		if bx then
			bx, by, bz = tonumber( bx ), tonumber( by ), tonumber( bz )
			MC:ShowBlock( bx, by, bz, kind ) -- hybrid: Dota draws every Minecraft block, nailed to its world
			local ground = MC.heights[ bx .. "," .. bz ] or MC_FLOOR
			if by >= ground and by <= ground + 1 then -- blocks at a hero's height block Dota pathing
				MC:SpawnBlock( FROM_MC[ kind ] or "npc_mc_block_cobble", MC:CellPos( bx, bz ), true ).mc_y = by
			end
		end
		local rx, ry, rz = line:match( "^mcbreak (%S+) (%S+) (%S+)" )
		if rx then
			rx, ry, rz = tonumber( rx ), tonumber( ry ), tonumber( rz )
			MC:HideBlock( rx, ry, rz )
			local ground = MC.heights[ rx .. "," .. rz ] or MC_FLOOR
			if ry >= ground and ry <= ground + 1 then MC:RemoveBlock( rx, rz ) end
		end

		local lx, ly, yawc, pitch, dist, lz, sent = line:match( "^cam (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)" )
		if lx and self.steve and GameRules:GetGameTime() - ( self.eyeLog or 0 ) > 2 then -- debug: eye height over real ground
			self.eyeLog = GameRules:GetGameTime()
			local p = self.steve:GetAbsOrigin()
			local eyeZ = tonumber( lz ) + tonumber( dist ) * math.sin( math.rad( tonumber( pitch ) ) )
			print( string.format( "[mc] eye %.0f above Dota ground (ground %.0f, anchor %.0f, cell %s)", eyeZ - GetGroundHeight( p, nil ), GetGroundHeight( p, nil ), MC.anchor.z, MC:CellOf( p ) .. "," .. select( 2, MC:CellOf( p ) ) ) )
		end
		if lx then -- Panorama wants the look-at height above the ground under it
			local off = tonumber( lz ) - GetGroundHeight( Vector( tonumber( lx ), tonumber( ly ), 0 ), nil )
			CustomGameEventManager:Send_ServerToAllClients( "mc_cam", { v = table.concat( { lx, ly, yawc, pitch, dist, string.format( "%.1f", off ), sent, lz }, " " ) } )
		end
	end
end

-- the Minecraft player drives the first Steve hero; Minecraft owns its health
function MCBridge:MoveSteve( name, pos, frac, yaw )
	local u = self.steve
	if not u or u:IsNull() then
		for _, h in ipairs( HeroList:GetAllHeroes() ) do
			if h:GetUnitName() == STEVE then u = h break end
		end
		if not u then return end
		self.steve = u
		u.mc_player = name
		u:SetCustomHealthLabel( name, 120, 255, 120 )
		u:AddNoDraw() -- ponytail: the camera sits inside him; for PvP give other players a visible blocky Steve instead
	end
	if not u:IsAlive() then return end
	u:SetAbsOrigin( pos )
	u:SetForwardVector( Vector( -math.sin( yaw ), -math.cos( yaw ), 0 ) )
	u:SetHealth( math.max( 1, frac * u:GetMaxHealth() ) )
end

-- Dota hits Steve: Minecraft owns his health, so the hit goes there
function MCBridge:OnSteveDamaged( victim, damage )
	self:Send( string.format( "dmg %.2f", damage * DOTA_TO_MC ) )
end

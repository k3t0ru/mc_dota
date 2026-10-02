-- Sync with real Minecraft through bridge/bridge.py: Minecraft players appear as Steve units, Dota heroes as
-- stand-ins in Minecraft, hits go both ways. 1 Minecraft block = 64 Dota units, MC (0,0) = MC.anchor.
BRIDGE_URL = "http://127.0.0.1:27100/sync"
MC_SCALE = 64
DMG_TO_DOTA = 10  -- 1 MC hp of damage to a hero stand-in = 10 Dota damage
STEVE_HP = 1000   -- Dota health of a Steve unit at 20 MC hp

MCBridge = { steves = {}, dmg = {}, busy = false }

local function to_mc( p ) return ( p.x - MC.anchor.x ) / MC_SCALE, -( p.y - MC.anchor.y ) / MC_SCALE end
local function to_dota( x, z ) return GetGroundPosition( MC.anchor + Vector( x * MC_SCALE, -z * MC_SCALE, 0 ), nil ) end

function MCBridge:Tick()
	if not MC.anchor then return 0.1 end
	if self.busy and GameRules:GetGameTime() - self.sentAt < 2 then return FrameTime() end -- a request to a dead bridge never answers
	self.sentAt = GameRules:GetGameTime()
	local a = MC.anchor
	local lines = { string.format( "anchor %.1f %.1f %.1f", a.x, a.y, a.z ) }
	for _, h in ipairs( HeroList:GetAllHeroes() ) do
		if h:IsAlive() and h:GetUnitName() ~= STEVE then
			local x, z = to_mc( h:GetAbsOrigin() )
			table.insert( lines, string.format( "hero %d %s %.2f %.2f %d %d", h:entindex(),
				( h:GetUnitName():gsub( "npc_dota_hero_", "" ) ), x, z, h:GetHealth(), h:GetMaxHealth() ) )
		end
	end
	for name, amount in pairs( self.dmg ) do table.insert( lines, string.format( "dmg %s %.2f", name, amount ) ) end
	self.dmg = {}

	self.busy = true
	local req = CreateHTTPRequestScriptVM( "POST", BRIDGE_URL )
	req:SetHTTPRequestAbsoluteTimeoutMS( 1000 )
	req:SetHTTPRequestRawPostBody( "text/plain", table.concat( lines, "\n" ) )
	req:Send( function( res )
		self.busy = false
		if res.StatusCode ~= 200 then
			if not self.warned then self.warned = true print( "[mc] bridge offline: " .. tostring( res.StatusCode ) ) end
			return
		end
		if self.warned ~= false then self.warned = false print( "[mc] bridge online" ) end
		self:Apply( res.Body or "" )
	end )
	return FrameTime()
end

function MCBridge:Apply( body )
	local seen = {}
	for line in body:gmatch( "[^\n]+" ) do
		local name, x, z, hp, max, yaw = line:match( "^steve (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)" )
		if name then
			seen[ name ] = true
			self:MoveSteve( name, to_dota( tonumber( x ), tonumber( z ) ), tonumber( hp ) / tonumber( max ), math.rad( tonumber( yaw ) ) )
		end
		local cam = line:match( "^cam (.+)" )
		if cam then CustomGameEventManager:Send_ServerToAllClients( "mc_cam", { v = cam } ) end
		local id, amount = line:match( "^hit (%d+) (%S+)" )
		local hero = id and EntIndexToHScript( tonumber( id ) )
		if hero and hero:IsAlive() then
			local attacker = next( self.steves ) and select( 2, next( self.steves ) ) or hero
			ApplyDamage( { victim = hero, attacker = attacker, damage = tonumber( amount ) * DMG_TO_DOTA, damage_type = DAMAGE_TYPE_PURE } )
		end
	end
	for name, unit in pairs( self.steves ) do -- player left Minecraft
		if not seen[ name ] then
			if not unit:IsNull() then unit:RemoveSelf() end
			self.steves[ name ] = nil
		end
	end
end

function MCBridge:MoveSteve( name, pos, frac, yaw )
	local u = self.steves[ name ]
	if frac <= 0 then -- dead in Minecraft
		if u and not u:IsNull() and u:IsAlive() then u:ForceKill( false ) end
		return
	end
	if not u or u:IsNull() or not u:IsAlive() then
		u = CreateUnitByName( "npc_mc_steve_proxy", pos, true, nil, nil, DOTA_TEAM_BADGUYS )
		u.mc_player = name
		u:SetCustomHealthLabel( name, 120, 255, 120 )
		self.steves[ name ] = u
	end
	if ( u:GetAbsOrigin() - pos ):Length2D() > 400 then
		FindClearSpaceForUnit( u, pos, true )
	else
		u:MoveToPosition( pos )
	end
	u:SetForwardVector( Vector( -math.sin( yaw ), -math.cos( yaw ), 0 ) )
	u:SetHealth( math.max( 1, frac * u:GetMaxHealth() ) )
end

-- Dota hits a Steve: don't touch the unit (Minecraft owns its health), send the hit to Minecraft instead
function MCBridge:OnSteveDamaged( victim, damage )
	self.dmg[ victim.mc_player ] = ( self.dmg[ victim.mc_player ] or 0 ) + damage * 20 / STEVE_HP
end

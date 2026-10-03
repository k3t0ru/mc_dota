-- Exchange with Minecraft through bridge/bridge.py (protocol at the top of that file). Coordinates on the wire are
-- Minecraft blocks: 1 block = GRID (64) Dota units, MC (0,0) = MC.anchor. The Minecraft player drives the Steve hero;
-- Dota heroes get invisible stand-ins in Minecraft so swords can hit them; blocks exist on both sides.
BRIDGE_URL = "http://127.0.0.1:27100/sync"
DMG_TO_DOTA = 10  -- 1 MC hp of damage to a hero stand-in = 10 Dota damage
DOTA_TO_MC = 0.02 -- 1 Dota damage to Steve = 0.02 MC hp (a 50-damage hit = half a heart)

MCBridge = { out = { "reset" }, inflight = 0, sentAt = 0, seq = 0, applied = 0 } -- a new Dota game starts Minecraft's arena from scratch

function MCBridge:Send( line ) table.insert( self.out, line ) end

local function to_mc( p ) return ( p.x - MC.anchor.x ) / GRID, -( p.y - MC.anchor.y ) / GRID end
local function to_dota( x, z ) return GetGroundPosition( MC.anchor + Vector( x * GRID, -z * GRID, 0 ), nil ) end

function MCBridge:Tick()
	if not MC.anchor then return 0.1 end
	-- one request per tick without waiting for the previous answer (waiting halved the camera's pose rate to ~10 Hz);
	-- a few may be in flight, more means the bridge is gone (a request to a dead bridge never answers)
	if self.inflight >= 4 and GameRules:GetGameTime() - self.sentAt < 2 then return FrameTime() end
	if self.inflight >= 4 then self.inflight = 0 end
	self.sentAt = GameRules:GetGameTime()

	local a = MC.anchor
	local lines = { string.format( "anchor %.1f %.1f %.1f", a.x, a.y, a.z ) }
	-- every living Dota unit near Steve gets a stand-in in Minecraft (heroes, creeps, neutrals)
	local center = self.steve and self.steve:GetAbsOrigin() or MC.anchor
	-- (towers and other buildings too, so Minecraft weapons can hit them; invulnerable ones only once Dota opens them up)
	for _, h in ipairs( FindUnitsInRadius( DOTA_TEAM_GOODGUYS, center, nil, 2500, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false ) ) do
		if h:IsAlive() and not h.mc_player and not h.mc_block and not h:IsInvulnerable() then
			local p = h:GetAbsOrigin()
			local x, z = to_mc( p )
			local lift = h:IsBuilding() and 0 or MC:LiftUnit( h ) -- standing on a 1-high Minecraft block
			-- last field: 1 = Steve's team (Minecraft's target bar shows allies, and when they can be denied)
			local ally = self.steve and h:GetTeamNumber() == self.steve:GetTeamNumber() and 1 or 0
			table.insert( lines, string.format( "hero %d %s %.2f %.2f %d %d %d %d", h:entindex(),
				( h:GetUnitName():gsub( "npc_dota_hero_", "" ):gsub( "npc_dota_", "" ) ), x, z, h:GetHealth(), h:GetMaxHealth(), MC:HeightAt( p.z ) + lift, ally ) )
		end
	end
	-- trader spots again now and then: a restarted Minecraft client forgets them
	if GameRules:GetGameTime() - ( self.tradersAt or -100 ) > 5 then self.tradersAt = GameRules:GetGameTime(); MC:SendTraders() end
	-- Steve's level (counted by MC:SteveXP from the hero XP Dota hands out) is his Minecraft max health
	-- (with the way to the next level: "lvl <level> <xp into it> <xp it takes>": Minecraft's XP bar shows it)
	if MC.steveLevel then
		local lvl = MC.steveLevel
		local from, to = XP_TABLE[ lvl ], XP_TABLE[ lvl + 1 ]
		local line = string.format( "lvl %d %d %d", lvl, MC.steveXPTotal - from, to and to - from or 0 )
		if line ~= self.sentLevel then
			self.sentLevel = line
			self:Send( line )
		end
	end
	MC:BossBar( self.steve )
	for _, l in ipairs( self.out ) do table.insert( lines, l ) end
	local sent = self.out
	self.out = {}

	self.inflight = self.inflight + 1
	self.seq = self.seq + 1
	local seq = self.seq
	local req = CreateHTTPRequestScriptVM( "POST", BRIDGE_URL )
	req:SetHTTPRequestAbsoluteTimeoutMS( 1000 )
	req:SetHTTPRequestRawPostBody( "text/plain", table.concat( lines, "\n" ) )
	req:Send( function( res )
		self.inflight = math.max( 0, self.inflight - 1 )
		if res.StatusCode ~= 200 then
			for _, l in ipairs( sent ) do table.insert( self.out, l ) end -- keep block updates for the next try
			if not self.warned then self.warned = true print( "[mc] bridge offline: " .. tostring( res.StatusCode ) ) end
			return
		end
		if self.warned ~= false then self.warned = false print( "[mc] bridge online" ) end
		local stale = seq < self.applied -- answers can overtake each other: an older one must not move Steve back
		self.applied = math.max( self.applied, seq )
		self:Apply( res.Body or "", stale )
	end )
	return FrameTime()
end

function MCBridge:Apply( body, stale )
	-- a swing at an ally (a deny) first: its sweep's hit lines may come earlier in the same batch
	if body:find( "swing " ) and self.aim and not self.aim:IsNull() and self.steve
		and self.aim:GetTeamNumber() == self.steve:GetTeamNumber() then self.denySwingAt = GameRules:GetGameTime() end
	for line in body:gmatch( "[^\n]+" ) do
		local name, x, z, hp, max, yaw, my = line:match( "^steve (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) ?(%S*)" )
		if name and not stale then
			self:MoveSteve( name, to_dota( tonumber( x ), tonumber( z ) ), tonumber( hp ) / tonumber( max ), math.rad( tonumber( yaw ) ) )
			self:HighGround( tonumber( x ), tonumber( z ), tonumber( my ) )
		end

		local id, amount, direct = line:match( "^hit (%d+) (%S+) ?(%S*)" ) -- arrows, sweeps: through the stand-ins
		-- (no splash right after a swing at an ally: a deny is a single hit, the sword's sweep must not hit the enemies around)
		local denying = GameRules:GetGameTime() - ( self.denySwingAt or -1 ) < 0.4
		if id and not ( denying and direct == "0" ) then self:HitUnit( EntIndexToHScript( tonumber( id ) ), tonumber( amount ), direct ~= "0" ) end
		local dev = line:match( "^dev (.+)" ) -- testing (bridge /dota): a console command, only with cheats on
		if dev and ( GameRules:IsCheatMode() or IsInToolsMode() ) then
			local name, dist = dev:match( "^testunit (%S+) (%S+)" ) -- a stunned unit in front of Steve, to aim at
			if name and self.steve then
				local team = name:find( "goodguys" ) and DOTA_TEAM_GOODGUYS or DOTA_TEAM_BADGUYS
				local u = CreateUnitByName( name, self.steve:GetAbsOrigin() + self.steve:GetForwardVector() * tonumber( dist ), false, nil, nil, team )
				u:AddNewModifier( u, nil, "modifier_stunned", { duration = 60 } )
				print( string.format( "[mc] test unit %s #%d hp %d at %s (steve %s)", name, u:entindex(), u:GetHealth(), tostring( u:GetAbsOrigin() ), tostring( self.steve:GetAbsOrigin() ) ) )
			else
				SendToServerConsole( dev )
			end
		end
		local swing, crit, sweep = line:match( "^swing (%S+) ?(%S*) ?(%S*)" ) -- a melee swing: whatever Dota highlights under the crosshair
		if swing and self.aim and not self.aim:IsNull() and GameRules:GetGameTime() - ( self.aimAt or 0 ) <= 0.6
			and self.steve and self.steve:IsAlive() then
			local reach = MELEE_REACH * GRID + self.aim:GetHullRadius()
			local d = ( self.aim:GetAbsOrigin() - self.steve:GetAbsOrigin() ):Length2D()
			if self.aim:GetTeamNumber() == self.steve:GetTeamNumber() then self.denySwingAt = GameRules:GetGameTime() end
			if d <= reach then self:Swing( self.aim, tonumber( swing ), crit == "1", tonumber( sweep ) or 0 ) end
		end

		local bx, by, bz, kind, solid, state = line:match( "^mcblock (%S+) (%S+) (%S+) (%S+) ?(%S*) ?(%S*)" )
		if bx then
			bx, by, bz = tonumber( bx ), tonumber( by ), tonumber( bz )
			MC:ShowBlock( bx, by, bz, kind, solid ~= "0", state ) -- hybrid: Dota draws every Minecraft block, nailed to its world
			MC:ColumnChanged( bx, bz )
		end
		local rx, ry, rz = line:match( "^mcbreak (%S+) (%S+) (%S+)" )
		if rx then
			rx, ry, rz = tonumber( rx ), tonumber( ry ), tonumber( rz )
			MC:HideBlock( rx, ry, rz )
			MC:ColumnChanged( rx, rz )
		end

		local lost = line:match( "^died (%S+)" ) -- the Minecraft player died: so does his Dota hero (the killer gets the bounty)
		if lost and self.steve and self.steve:IsAlive() then
			local killer = self.lastAttacker and not self.lastAttacker:IsNull() and self.lastAttacker or self.steve
			self.steve.mc_dead = true
			self.steve:Kill( nil, killer )
			if self.steve:IsAlive() then self.steve:ForceKill( false ) end -- no attacker (the void, /kill): Kill by himself does nothing
			-- (the respawn time is 0 until the next frame)
			local steve = self.steve
			steve:SetContextThink( "mc_dead", function()
				print( string.format( "[mc] Steve died: respawn in %.1f s", steve:GetTimeUntilRespawn() ) )
				self:Send( string.format( "dead %d %s", math.ceil( steve:GetTimeUntilRespawn() ), lost ) )
			end, 0.1 )
		end

		local cx, cy, cz, stage = line:match( "^crack (%S+) (%S+) (%S+) (%S+)" )
		if cx then MC:Crack( tonumber( cx ), tonumber( cy ), tonumber( cz ), tonumber( stage ) ) end

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

-- a Minecraft hit on a Dota unit. Allies can only be denied like in Dota: creeps below half health, towers below 10%,
-- heroes never, and only with a direct hit (a sword's sweep and other splash never touch allies).
MELEE_REACH = 3.5 -- blocks from Steve to the target's edge (Minecraft's reach is 3)
-- a melee swing Dota landed: the hit, Minecraft's crit/sweep effects on it, and the sweep's splash around it (enemies
-- within a block of the target; never during a deny)
function MCBridge:Swing( target, amount, crit, sweep )
	local denying = self.steve and target:GetTeamNumber() == self.steve:GetTeamNumber()
	self:HitUnit( target, amount, true )
	self:Send( string.format( "fx %s %d", crit and "crit" or "hit", target:entindex() ) )
	if sweep > 0 and not denying and self.steve then
		local around = FindUnitsInRadius( self.steve:GetTeamNumber(), target:GetAbsOrigin(), nil, GRID + target:GetHullRadius(),
			DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false )
		for _, u in ipairs( around ) do if u ~= target then self:HitUnit( u, sweep, false ) end end
		self:Send( string.format( "fx sweep %d", target:entindex() ) )
	end
end

-- standing 3+ blocks above the ground (a tower of blocks, flying on elytra) sees like from a cliff: flying vision
function MCBridge:HighGround( x, z, y )
	local u = self.steve
	if not u or u:IsNull() or not y or not x then return end
	local g = MC.heights[ math.floor( x ) .. "," .. math.floor( z ) ] or MC_FLOOR
	local high = y - g >= 3
	if high and not u:HasModifier( "modifier_mc_highground" ) then u:AddNewModifier( u, nil, "modifier_mc_highground", {} )
	elseif not high and u:HasModifier( "modifier_mc_highground" ) then u:RemoveModifierByName( "modifier_mc_highground" ) end
end

function MCBridge:HitUnit( hero, amount, direct )
	if not hero or hero:IsNull() or not hero:IsAlive() or not hero.GetTeamNumber or hero.mc_player or hero.mc_block then return end
	local ally = self.steve and hero:GetTeamNumber() == self.steve:GetTeamNumber()
	local deniable = ally and direct and not hero:IsHero() and hero:GetHealthPercent() < ( hero:IsTower() and 10 or 50 )
	if hero:IsInvulnerable() or ( ally and not deniable ) then return end
	if ally and self.steve then
		-- a deny must be an ATTACK, or Dota doesn't count it (no "!", the enemy keeps full XP); DamageFilter swaps in the hit
		self.steve.mc_attack = amount * DMG_TO_DOTA
		self.steve.mc_denying = true -- XP/gold filters: a deny gives the denier nothing
		self.steve:PerformAttack( hero, true, false, true, true, false, false, true )
		self.steve.mc_attack, self.steve.mc_denying = nil, nil
	else
		ApplyDamage( { victim = hero, attacker = self.steve or hero, damage = amount * DMG_TO_DOTA, damage_type = DAMAGE_TYPE_PURE } )
		if hero:IsBuilding() then MC.bossUnit, MC.bossUntil = hero, GameRules:GetGameTime() + 5 end
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
	u:AddNoDraw() -- (again every time: a respawn shows the model)
	u:SetAbsOrigin( pos )
	u:SetForwardVector( Vector( -math.sin( yaw ), -math.cos( yaw ), 0 ) )
	u:SetHealth( math.max( 1, frac * u:GetMaxHealth() ) )
end

-- Dota hits Steve: Minecraft owns his health, so the hit goes there
-- (the attacker's stand-in is named, so a raised Minecraft shield facing it blocks the hit)
function MCBridge:OnSteveDamaged( victim, damage, attacker )
	local unit = attacker and EntIndexToHScript( attacker )
	if unit and unit.GetUnitName then self.lastAttacker = unit end -- credited if Steve dies
	local amount = damage * DOTA_TO_MC
	if amount < 0.01 then return end
	self:Send( string.format( "dmg %.2f %d", amount, attacker or -1 ) )
end

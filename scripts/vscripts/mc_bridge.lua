-- Exchange with Minecraft through bridge/bridge.py (protocol at the top of that file). Coordinates on the wire are
-- Minecraft blocks: 1 block = GRID (64) Dota units, MC (0,0) = MC.anchor. The Minecraft player drives the Steve hero;
-- Dota heroes get invisible stand-ins in Minecraft so swords can hit them; blocks exist on both sides.
BRIDGE_URL = "http://127.0.0.1:27100/sync"
DMG_TO_DOTA = 10  -- 1 MC hp of damage to a hero stand-in = 10 Dota damage

-- Melee in Dota damage: a full swing does 6 x weapon^1.6 (wooden sword 4 -> 55, a level 1 hero; stone 5 -> 79, iron 6 ->
-- 105, diamond 7 -> 135, netherite 8 -> 167), x (1 + 0.55 per Sharpness level): netherite + Sharpness V ~ 626 (Roshan in
-- ~10 s like a 6-slotted level 30 carry), iron + V ~ 394. Physical: the target's armour counts (a tower takes ~40% less).
-- A swing's cooldown/crit keep their share. Returns the factor for the swing's Minecraft numbers (HitUnit x DMG_TO_DOTA).
function MeleeScale( full, base, sharp )
	if not full or full <= 0 then return 1 end
	base = base and base > 0 and base or full
	return 6 * base ^ 1.6 * ( 1 + 0.55 * ( sharp or 0 ) ) / ( full * DMG_TO_DOTA )
end
TNT_MULT = 3.5 -- Minecraft's TNT (up to ~56 at the blast, less further off) x 10 x this: kills a creep standing next to it
DOTA_TO_MC = 0.02 -- 1 Dota damage to Steve = 0.02 MC hp (a 50-damage hit = half a heart)

MCBridge = { out = { "reset" }, inflight = 0, sentAt = 0, seq = 0, applied = 0 } -- a new Dota game starts Minecraft's arena from scratch

function MCBridge:Send( line ) table.insert( self.out, line ) end

local function to_mc( p ) return MC:ToMC( p ) end
local function to_dota( x, z ) return GetGroundPosition( MC.anchor + MC:Offset( x, z ), nil ) end

-- Steve's stand-in glides toward him every tick: half the way (his poses come in bursts: set straight, it jerked)
function MCBridge:PuppetGlide()
	local p, g = self.puppet, self.puppetGoal
	if not p or p:IsNull() or not g then return end
	local at = p:GetAbsOrigin()
	if ( g - at ):Length() > 400 then p:SetAbsOrigin( g ) else p:SetAbsOrigin( at + ( g - at ) * 0.5 ) end
end

function MCBridge:Projectile( id, kind, x, y, z, vx, vz )
	if not MC.anchor then return end
	self.projs = self.projs or {}
	local p = MC.anchor + MC:Offset( x, z )
	p.z = MC.anchor.z + ( y - MC_FLOOR ) * GRID
	local fx = self.projs[ id ]
	if not fx then
		fx = ParticleManager:CreateParticleForTeam( "particles/mc/steve/proj_" .. kind .. ".vpcf", PATTACH_WORLDORIGIN, nil, DOTA_TEAM_BADGUYS )
		self.projs[ id ] = fx
	end
	ParticleManager:SetParticleControl( fx, 0, p )
	if math.abs( vx ) + math.abs( vz ) > 0.01 then ParticleManager:SetParticleControlForward( fx, 0, MC:DirToDota( vx, vz ) ) end
end

function MCBridge:Blast( kind, x, y, z )
	if not MC.anchor then return end
	local p = to_dota( x, z )
	p.z = MC.anchor.z + ( y - MC_FLOOR ) * GRID
	local fx = ParticleManager:CreateParticle( kind == "smash" and "particles/units/heroes/hero_earthshaker/earthshaker_aftershock.vpcf"
		or "particles/units/heroes/hero_brewmaster/brewmaster_cyclone.vpcf", PATTACH_WORLDORIGIN, nil )
	ParticleManager:SetParticleControl( fx, 0, p )
	ParticleManager:SetParticleControl( fx, 1, Vector( 350, 350, 350 ) )
	-- (a wind charge's gust: a cyclone for a moment)
	local timer = Entities:FindByName( nil, "mc_timer" )
	if kind == "wind" and timer then
		timer:SetContextThink( "mc_gust" .. fx, function() ParticleManager:DestroyParticle( fx, false ) ParticleManager:ReleaseParticleIndex( fx ) end, 0.6 )
	else
		ParticleManager:ReleaseParticleIndex( fx )
	end
	local radius, dist = kind == "smash" and 3.5 * GRID or 2.5 * GRID, kind == "smash" and 160 or 280
	for _, u in ipairs( FindUnitsInRadius( DOTA_TEAM_GOODGUYS, p, nil, radius, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false ) ) do
		if not u.mc_player and not u.mc_puppet and not u.mc_block and not u:IsBuilding() and u:IsAlive() then
			u:AddNewModifier( self.steve or u, nil, "modifier_knockback", { center_x = p.x, center_y = p.y, center_z = p.z,
				duration = 0.4, knockback_duration = 0.4, knockback_distance = dist, knockback_height = 60, should_stun = 0 } )
		end
	end
end

function MCBridge:Tick()
	self:PuppetGlide()
	if not MC.anchor then return 0.1 end
	-- one request per tick without waiting for the previous answer (waiting halved the camera's pose rate to ~10 Hz);
	-- a few may be in flight, more means the bridge is gone (a request to a dead bridge never answers)
	if self.inflight >= 4 and GameRules:GetGameTime() - self.sentAt < 2 then return FrameTime() end
	if self.inflight >= 4 then self.inflight = 0 end
	self.sentAt = GameRules:GetGameTime()

	local a = MC.anchor
	local lines = { string.format( "anchor %.1f %.1f %.1f %.3f", a.x, a.y, a.z, GRID_ROT ) } -- (the bridge turns the camera too)
	-- every living Dota unit near Steve gets a stand-in in Minecraft (heroes, creeps, neutrals)
	local center = self.steve and self.steve:GetAbsOrigin() or MC.anchor
	-- (towers and other buildings too, so Minecraft weapons can hit them; invulnerable ones only once Dota opens them up)
	for _, h in ipairs( FindUnitsInRadius( DOTA_TEAM_GOODGUYS, center, nil, 2500, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_BUILDING, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false ) ) do
		if h:IsAlive() and not h.mc_player and not h.mc_puppet and not h.mc_block and not h:IsInvulnerable() then
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
		local from, to = MC:XPFor( lvl ), MC:XPFor( lvl + 1 )
		local line = string.format( "lvl %d %d %d", lvl, MC.steveXPTotal - from, to - from )
		if line ~= self.sentLevel then
			self.sentLevel = line
			self:Send( line )
		end
	end
	MC:BossBar( self.steve )
	MCWorld:Think()
	-- cobwebs hold units like in Minecraft (90% slower while inside)
	for p in pairs( MC.cobwebs ) do
		if p:IsNull() then MC.cobwebs[ p ] = nil
		else
			for _, u in ipairs( FindUnitsInRadius( DOTA_TEAM_NEUTRALS, p:GetAbsOrigin(), nil, GRID * 0.6, DOTA_UNIT_TARGET_TEAM_BOTH,
				DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false ) ) do
				if not u.mc_player and not u.mc_puppet and not u.mc_block then u:AddNewModifier( u, nil, "modifier_mc_potion", { duration = 0.3, kind = "web", level = 6 } ) end
			end
		end
	end
	-- our fountain heals Steve (Minecraft owns his health and hunger): twice a second while he is in its aura
	local s = self.steve
	if s and not s:IsNull() and s:IsAlive() and s:HasModifier( "modifier_fountain_aura_buff" )
		and GameRules:GetGameTime() - ( self.fountainAt or 0 ) >= 0.5 then
		self.fountainAt = GameRules:GetGameTime()
		self:Send( "fountain" )
	end
	-- Dota's clock for Minecraft's (shown while Steve carries a clock: ClockHud)
	local t = math.floor( GameRules:GetDOTATime( false, true ) )
	if t ~= self.sentTime then
		self.sentTime = t
		self:Send( string.format( "time %d %d", t, GameRules:IsDaytime() and 1 or 0 ) )
	end
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
	if body:find( "swing" ) and GameRules:GetGameTime() - ( self.swingAt or -10 ) > 0.45 then -- (Dire's view of his swing:
		self.swingAt = GameRules:GetGameTime()                    -- once per swing, a repeat restarted it)
	end
	if body:find( "swing " ) and self.aim and not self.aim:IsNull() and self.steve
		and self.aim:GetTeamNumber() == self.steve:GetTeamNumber() then self.denySwingAt = GameRules:GetGameTime() end
	for line in body:gmatch( "[^\n]+" ) do
		local name, x, z, hp, max, yaw, my, pose, elytra, held = line:match( "^steve (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) ?(%S*) ?(%S*) ?(%S*) ?(%S*)" )
		if name and not stale then
			-- how Dota's players see him (MCBridge:Puppet): Minecraft's pose, an elytra worn, the item in his hand
			self.pose, self.elytra, self.held = pose ~= "" and pose or "stand", elytra == "1", held
			self:MoveSteve( name, to_dota( tonumber( x ), tonumber( z ) ), tonumber( hp ) / tonumber( max ), math.rad( tonumber( yaw ) ), tonumber( my ) )
			self:HighGround( tonumber( x ), tonumber( z ), tonumber( my ) )
		end

		local id, amount, direct, kind = line:match( "^hit (%d+) (%S+) ?(%S*) ?(%S*)" ) -- arrows, sweeps: through the stand-ins
		if id and kind == "fire" then -- burning: a neutral dying now drops cooked meat
			local u = EntIndexToHScript( tonumber( id ) )
			if u and not u:IsNull() then self:Burn( u, 1.5 ) end
		end
		-- (no splash right after a swing at an ally: a deny is a single hit, the sword's sweep must not hit the enemies around)
		local denying = GameRules:GetGameTime() - ( self.denySwingAt or -1 ) < 0.4
		if id and not ( denying and direct == "0" ) then self:HitUnit( EntIndexToHScript( tonumber( id ) ), tonumber( amount ), direct ~= "0", kind ) end
		-- a splash potion's lasting effect on a Dota unit (Minecraft's stand-in got it): Dota's version of it
		local eid, ekind, elvl, esec = line:match( "^eff (%d+) (%S+) (%S+) (%S+)" )
		if eid then
			local u = EntIndexToHScript( tonumber( eid ) )
			if u and not u:IsNull() and u:IsAlive() then
				u:AddNewModifier( self.steve or u, nil, "modifier_mc_potion", { duration = tonumber( esec ), kind = ekind, level = tonumber( elvl ) } )
			end
		end
		local dev = line:match( "^dev (.+)" ) -- testing (bridge /dota): a console command, only with cheats on
		if dev and ( GameRules:IsCheatMode() or IsInToolsMode() ) then
			local name, dist, free = dev:match( "^testunit (%S+) (%S+) ?(%S*)" ) -- a stunned unit in front of Steve, to aim at ("free": not stunned)
			if name and self.steve then
				local team = name:find( "goodguys" ) and DOTA_TEAM_GOODGUYS or DOTA_TEAM_BADGUYS
				local u = CreateUnitByName( name, self.steve:GetAbsOrigin() + self.steve:GetForwardVector() * tonumber( dist ), false, nil, nil, team )
				if free ~= "free" then u:AddNewModifier( u, nil, "modifier_stunned", { duration = 60 } ) end
				print( string.format( "[mc] test unit %s #%d hp %d at %s (steve %s)", name, u:entindex(), u:GetHealth(), tostring( u:GetAbsOrigin() ), tostring( self.steve:GetAbsOrigin() ) ) )
			elseif dev:match( "^steveinfo" ) and self.steve then -- why don't enemies attack Steve?
				local u = self.steve
				local mods = {}
				for _, m in ipairs( u:FindAllModifiers() ) do table.insert( mods, m:GetName() ) end
				print( string.format( "[mc] steve alive %s pos %s team %d invuln %s attackimmune %s nodraw %s untargetable %s mods %s",
					tostring( u:IsAlive() ), tostring( u:GetAbsOrigin() ), u:GetTeamNumber(), tostring( u:IsInvulnerable() ),
					tostring( u:IsAttackImmune() ), tostring( u.IsNoDraw and u:IsNoDraw() ), tostring( u.IsUntargetable and u:IsUntargetable() ),
					table.concat( mods, "," ) ) )
				local id = tonumber( dev:match( "^steveinfo (%d+)" ) or "" )
				local n = id and EntIndexToHScript( id )
				if n and not n:IsNull() then
					local tgt = n:GetAttackTarget()
					print( string.format( "[mc] unit %d at %s target %s aggro %s", id, tostring( n:GetAbsOrigin() ), tgt and tgt:GetUnitName() or "none", tostring( n:GetAggroTarget() and n:GetAggroTarget():GetUnitName() ) ) )
				end
			elseif dev == "towers" then
				for _, t in ipairs( Entities:FindAllByClassname( "npc_dota_tower" ) ) do
					local o = t:GetAbsOrigin()
					print( string.format( "[mc] tower %s team %d at %d %d (mc %d %d)", t:GetUnitName(), t:GetTeamNumber(), o.x, o.y,
						MC:CellOf( o ) ) )
				end
			elseif dev:match( "^nodraw " ) and self.steve then -- does Dota's AI ignore a hero it doesn't draw?
				self.nodrawOff = dev == "nodraw 0"
				if self.nodrawOff then self.steve:RemoveEffects( EF_NODRAW ) end
			elseif dev:match( "^lua " ) then -- run a line of Lua (tests: spawning runes, wards...)
				local f, err = ( loadstring or load )( dev:sub( 5 ) )
				if f then local ok, e = pcall( f ) if not ok then print( "[mc] lua error: " .. tostring( e ) ) end
				else print( "[mc] lua syntax: " .. tostring( err ) ) end
			elseif dev == "classes" then -- every entity class on the map, with a count (looking for the sky/fog)
				local c, e = {}, Entities:First()
				while e do c[ e:GetClassname() ] = ( c[ e:GetClassname() ] or 0 ) + 1 e = Entities:Next( e ) end
				local t = {}
				for k, n in pairs( c ) do table.insert( t, k .. "=" .. n ) end
				table.sort( t )
				print( "[mc] classes " .. table.concat( t, " " ) )
			elseif dev == "props" then -- the map's own dynamic props and world layers
				local seen = {}
				for _, e in ipairs( Entities:FindAllByClassname( "prop_dynamic" ) ) do
					local m = e:GetModelName() or ""
					if not m:find( "^models/mc" ) and not seen[ m ] then seen[ m ] = true print( "[mc] prop " .. m ) end
				end
				for _, e in ipairs( Entities:FindAllByClassname( "info_world_layer" ) ) do print( "[mc] layer " .. ( e:GetName() or "?" ) ) end
				for _, e in ipairs( Entities:FindAllByClassname( "env_fog_controller" ) ) do print( "[mc] fog " .. ( e:GetName() or "?" ) ) end
			elseif dev == "dumpedge" then -- entities with models out at the map's edge (what Steve sees on the horizon)
				local e, n, seen = Entities:First(), 0, {}
				while e and n < 60 do
					local o = e:GetAbsOrigin()
					local m = e.GetModelName and e:GetModelName() or ""
					if m ~= "" and ( math.abs( o.x ) > 7000 or math.abs( o.y ) > 7000 ) and not seen[ m ] then
						seen[ m ] = true
						n = n + 1
						print( string.format( "[mc] edge %s %s %d %d %d", e:GetClassname(), m, o.x, o.y, o.z ) )
					end
					e = Entities:Next( e )
				end
			elseif dev:match( "^client " ) then -- the host's client console (camera/render settings live there)
				SendToConsole( dev:sub( 8 ) )
			else
				SendToServerConsole( dev )
			end
		end
		if line == "use" then MCWorld:Use() end
		if line == "light" and self.aim and not self.aim:IsNull() and self.aim:IsAlive() and self.steve
			and GameRules:GetGameTime() - ( self.aimAt or 0 ) <= 0.6
			and ( self.aim:GetAbsOrigin() - self.steve:GetAbsOrigin() ):Length2D() <= MELEE_REACH * GRID + self.aim:GetHullRadius() then
			self:Send( string.format( "fx burn %d 8", self.aim:entindex() ) ) -- flint and steel on a unit: 8 s of fire
			self:Burn( self.aim, 8 )
		end
		local swing, crit, sweep, full, fire, wbase, sharp = line:match( "^swing (%S+) ?(%S*) ?(%S*) ?(%S*) ?(%S*) ?(%S*) ?(%S*)" ) -- a melee swing: whatever Dota highlights under the crosshair
		if swing and MCWorld:SwingRune() then swing = nil end -- (a rune in front: the swing breaks it)
		if swing and self.steve and self.steve:IsAlive() then
			local a = self.aim
			local aimed = a and not a:IsNull() and a:IsAlive() and GameRules:GetGameTime() - ( self.aimAt or 0 ) <= 0.6
				and ( a:GetAbsOrigin() - self.steve:GetAbsOrigin() ):Length2D() <= MELEE_REACH * GRID + a:GetHullRadius()
				and self:Hittable( a )
			if not aimed then self.aim = self:InFront() end
		end
		if swing and self.aim and not self.aim:IsNull() and self.steve and self.steve:IsAlive() then
			local reach = MELEE_REACH * GRID + self.aim:GetHullRadius()
			local d = ( self.aim:GetAbsOrigin() - self.steve:GetAbsOrigin() ):Length2D()
			if self.aim:GetTeamNumber() == self.steve:GetTeamNumber() then self.denySwingAt = GameRules:GetGameTime() end
			local k = MeleeScale( tonumber( full ), tonumber( wbase ), tonumber( sharp ) )
			if self.steve:HasModifier( "modifier_rune_doubledamage" ) then k = k * 2 end -- the double damage rune
			if d <= reach then self:Swing( self.aim, tonumber( swing ) * k, crit == "1", ( tonumber( sweep ) or 0 ) * k, tonumber( fire ) or 0 )
			end
		end
		if swing and self.steve and self.steve:HasModifier( "modifier_rune_invis" ) then -- attacking breaks invisibility
			self.steve:RemoveModifierByName( "modifier_rune_invis" )
		end
		-- TNT went off in Minecraft: Dota shows (and plays) the blast, for everyone
		local tx, ty, tz = line:match( "^boom (%S+) (%S+) (%S+)" )
		if tx then
			local p = MC.anchor + MC:Offset( tonumber( tx ), tonumber( tz ) ) + Vector( 0, 0, ( tonumber( ty ) - MC_FLOOR ) * GRID )
			local fx = ParticleManager:CreateParticle( "particles/units/heroes/hero_techies/techies_land_mine_explode.vpcf", PATTACH_WORLDORIGIN, nil )
			ParticleManager:SetParticleControl( fx, 0, p )
			ParticleManager:SetParticleControl( fx, 1, Vector( 400, 0, 0 ) )
			ParticleManager:ReleaseParticleIndex( fx )
			EmitSoundOnLocationWithCaster( p, "Hero_Techies.LandMine.Detonate", self.steve )
		end
		local cbx, cbz = line:match( "^chop (%S+) (%S+)" )
		if cbx then MCWorld:Chop( tonumber( cbx ), tonumber( cbz ) ) end

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
		-- a mace's smash, a wind charge's burst: Dota's look of it, and the units around knocked away (Minecraft's own
		-- knockback, on Dota's side)
		-- Steve's projectiles in flight (wind charges, ender pearls, arrows): their Minecraft look for Dire's players
		local pid, pkind, px_, py_, pz_, pvx, pvz = line:match( "^proj (%d+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)" )
		if pid then self:Projectile( pid, pkind, tonumber( px_ ), tonumber( py_ ), tonumber( pz_ ), tonumber( pvx ), tonumber( pvz ) ) end
		local pend = line:match( "^projend (%d+)" )
		if pend and self.projs and self.projs[ pend ] then
			ParticleManager:DestroyParticle( self.projs[ pend ], true )
			ParticleManager:ReleaseParticleIndex( self.projs[ pend ] )
			self.projs[ pend ] = nil
		end
		local kk, kx, ky, kz = line:match( "^(%a+) (%S+) (%S+) (%S+)" )
		if kk == "smash" or kk == "wind" then self:Blast( kk, tonumber( kx ), tonumber( ky ), tonumber( kz ) ) end
		local fx_, fy_, fz_, fs_ = line:match( "^fcrack (%S+) (%S+) (%S+) (%S+)" ) -- a falling build's block cracking (Sync.fallTick)
		if fx_ then MC:CrackAt( tonumber( fx_ ), tonumber( fy_ ), tonumber( fz_ ), tonumber( fs_ ) ) end

		local lx, ly, yawc, pitch, dist, lz, sent = line:match( "^cam (%S+) (%S+) (%S+) (%S+) (%S+) (%S+) (%S+)" )
		if lx and self.steve and GameRules:GetGameTime() - ( self.eyeLog or 0 ) > 2 then -- debug: eye height over real ground
			self.eyeLog = GameRules:GetGameTime()
			local p = self.steve:GetAbsOrigin()
			local eyeZ = tonumber( lz ) + tonumber( dist ) * math.sin( math.rad( tonumber( pitch ) ) )
			print( string.format( "[mc] eye %.0f above Dota ground (ground %.0f, anchor %.0f, cell %s)", eyeZ - GetGroundHeight( p, nil ), GetGroundHeight( p, nil ), MC.anchor.z, MC:CellOf( p ) .. "," .. select( 2, MC:CellOf( p ) ) ) )
		end
		if lx then -- Panorama wants the look-at height above the ground under it
			-- (MCBridge:SmoothEye, Dota's ground under the eye, jerked on cliffs and ledges: Minecraft's eye with smoothed
			-- step-ups instead, CameraSender)
			local off = lz - GetGroundHeight( Vector( tonumber( lx ), tonumber( ly ), 0 ), nil )
			local pl = self.steve and PlayerResource:GetPlayer( self.steve:GetPlayerOwnerID() ) -- (Steve's client only)
			if pl then CustomGameEventManager:Send_ServerToPlayer( pl, "mc_cam", { v = table.concat( { lx, ly, yawc, pitch, dist, string.format( "%.1f", off ), sent, lz }, " " ) } ) end
		end
	end
end

-- Minecraft's ground is half-block steps of Dota's slopes: walking across one, Steve's eye jumped half a block at
-- every step, and with it Dota's whole picture (most visible on tall things nearby: the traders, the stalls). Dota's
-- camera takes its height from Dota's own smooth ground instead, plus how high Steve's feet are above Minecraft's
-- ground (jumps, blocks, falling off a cliff stay as they are). Returns the look-at height to use.
function MCBridge:SmoothEye( lx, ly, yawc, pitch, dist, lz )
	local a = MC.anchor
	if not a then return lz end
	local t, p = math.rad( 180 - yawc ), math.rad( pitch ) -- Minecraft's yaw (the bridge: Dota yaw = 180 - MC yaw)
	local ex, ey = lx + dist * math.cos( p ) * math.sin( t ), ly + dist * math.cos( p ) * math.cos( t )
	local ez = lz + dist * math.sin( p )
	-- Minecraft's ground under the feet: the highest column the player's footprint (0.3 blocks around) stands on
	local ground
	for _, o in ipairs( { { -0.3, -0.3 }, { 0.3, -0.3 }, { -0.3, 0.3 }, { 0.3, 0.3 } } ) do
		local bx, bz = math.floor( ( ex - a.x ) / GRID + o[1] ), math.floor( -( ey - a.y ) / GRID + o[2] )
		local h = MC.halfh[ bx .. "," .. bz ]
		if h then ground = math.max( ground or -1e9, MC_FLOOR + h / 2 ) end
	end
	if not ground then return lz end
	local above = ( ez - a.z ) / GRID - 1.62 - ground -- feet over Minecraft's ground (0 when standing on it)
	if above < -0.6 then return lz end
	-- Dota's ground averaged around the eye: its little bumps (paving, rocks, the fountain's steps) shook the camera
	local g = 0
	for dx = -96, 96, 48 do for dy = -96, 96, 48 do g = g + GetGroundHeight( Vector( ex + dx, ey + dy, 0 ), nil ) end end
	local want = g / 25 + ( 1.62 + math.max( 0, above ) ) * GRID
	return lz + ( want - ez )
end

-- a Minecraft hit on a Dota unit. Allies can only be denied like in Dota: creeps below half health, towers below 10%,
-- heroes never, and only with a direct hit (a sword's sweep and other splash never touch allies).
MELEE_REACH = 3 -- blocks from Steve to the target's edge: Minecraft's reach for hitting an entity
-- a melee swing Dota landed: the hit, Minecraft's crit/sweep effects on it, and the sweep's splash around it (enemies
-- within a block of the target; never during a deny)
function MCBridge:Swing( target, amount, crit, sweep, fire )
	local denying = self.steve and target:GetTeamNumber() == self.steve:GetTeamNumber()
	self.critNow = crit
	self:HitUnit( target, amount, true )
	self.critNow = nil
	self:Send( string.format( "fx %s %d", crit and "crit" or "hit", target:entindex() ) )
	if ( fire or 0 ) > 0 and not denying and not target:IsNull() and target:IsAlive() then -- Fire Aspect
		self:Send( string.format( "fx burn %d %d", target:entindex(), fire ) )
		self:Burn( target, fire )
	end
	if sweep > 0 and not denying and self.steve then
		local around = FindUnitsInRadius( self.steve:GetTeamNumber(), target:GetAbsOrigin(), nil, GRID + target:GetHullRadius(),
			DOTA_UNIT_TARGET_TEAM_ENEMY, DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_NONE, FIND_ANY_ORDER, false )
		for _, u in ipairs( around ) do if u ~= target then self:HitUnit( u, sweep, false ) end end
		self:Send( string.format( "fx sweep %d", target:entindex() ) )
	end
end

-- standing 4+ blocks above the ground (a tower of blocks, flying on elytra) sees like from a cliff: flying vision
function MCBridge:HighGround( x, z, y )
	local u = self.steve
	if not u or u:IsNull() or not y or not x then return end
	local g = MC.heights[ math.floor( x ) .. "," .. math.floor( z ) ] or MC_FLOOR
	local high = y - g >= 4
	if high and not u:HasModifier( "modifier_mc_highground" ) then u:AddNewModifier( u, nil, "modifier_mc_highground", {} )
	elseif not high and u:HasModifier( "modifier_mc_highground" ) then u:RemoveModifierByName( "modifier_mc_highground" ) end
end

function MCBridge:HitUnit( hero, amount, direct, kind )
	if not hero or hero:IsNull() or not hero:IsAlive() or not hero.GetTeamNumber or hero.mc_player or hero.mc_puppet or hero.mc_block then return end
	local ally = self.steve and hero:GetTeamNumber() == self.steve:GetTeamNumber()
	local deniable = ally and direct and not hero:IsHero() and hero:GetHealthPercent() < ( hero:IsTower() and 10 or 50 )
	if hero:IsInvulnerable() or ( ally and not deniable ) then return end
	-- wards break in two hits, whatever the damage (like Dota's)
	if hero:GetUnitName():find( "_wards" ) and not ally then
		hero.mc_hits = ( hero.mc_hits or 0 ) + 1
		if hero.mc_hits >= 2 then hero:Kill( nil, self.steve )
		else hero:SetHealth( math.max( 1, math.ceil( hero:GetMaxHealth() / 2 ) ) ) end -- (its bar shows the hit)
		return
	end
	if ally and self.steve then
		-- a deny must be an ATTACK, or Dota doesn't count it (no "!", the enemy keeps full XP); DamageFilter swaps in the hit
		self.steve.mc_attack = amount * DMG_TO_DOTA
		self.steve.mc_denying = true -- XP/gold filters: a deny gives the denier nothing
		local before = hero:GetHealth()
		self.steve:SetAttackCapability( DOTA_UNIT_CAP_MELEE_ATTACK ) -- (lent for this one attack: MCBridge:MoveSteve)
		self.steve:PerformAttack( hero, true, false, true, true, false, false, true )
		self.steve:SetAttackCapability( DOTA_UNIT_CAP_NO_ATTACK )
		self:Send( string.format( "dmgnum %d %d deny", hero:entindex(), math.floor( math.max( 0, before - hero:GetHealth() ) + 0.5 ) ) )
		self.steve.mc_attack, self.steve.mc_denying = nil, nil
	else
		-- melee and arrows: physical (armour); TNT, potions, fire: magical (magic resistance)
		local magic = kind == "boom" or kind == "magic" or kind == "fire"
		local ev = not magic and hero.GetEvasion and hero:GetEvasion() or 0
		if ev > 1 then ev = ev / 100 end
		if ev > 0 and RandomFloat( 0, 1 ) < ev then
			self:Send( string.format( "dmgnum %d 0 miss", hero:entindex() ) )
			return
		end
		local dealt = ApplyDamage( { victim = hero, attacker = self.steve or hero, damage = amount * DMG_TO_DOTA * ( kind == "boom" and TNT_MULT or 1 ),
			damage_type = magic and DAMAGE_TYPE_MAGICAL or DAMAGE_TYPE_PHYSICAL } )
		-- the number over it, Minecraft style (Progress.damageNumber)
		if dealt and dealt >= 1 then
			self:Send( string.format( "dmgnum %d %d %s", hero:entindex(), math.floor( dealt + 0.5 ), self.critNow and "crit" or "hit" ) )
		end
		if hero:IsBuilding() then MC.bossUnit, MC.bossUntil = hero, GameRules:GetGameTime() + 5 end
	end
end

-- on fire from Minecraft (fire aspect, flint and steel, lava, a burning arrow): the cooked-meat drop, and Dota's look
function MCBridge:Burn( u, seconds )
	if not u or u:IsNull() or not u:IsAlive() then return end
	u.mc_burnUntil = math.max( u.mc_burnUntil or 0, GameRules:GetGameTime() + seconds )
	if not u.mc_block then u:AddNewModifier( self.steve or u, nil, "modifier_mc_burning", { duration = seconds } ) end
end

-- a unit Steve's swing does something to: an enemy, or an ally he may deny
function MCBridge:Hittable( u )
	if u.mc_player or u.mc_puppet or u.mc_block or u:IsInvulnerable() then return false end
	if u:GetTeamNumber() ~= self.steve:GetTeamNumber() then return true end
	return not u:IsHero() and u:GetHealthPercent() < ( u:IsTower() and 10 or 50 )
end

-- the unit nearest the line Steve looks along, within reach (Dota's aim misses models without a skeleton: the mobs)
function MCBridge:InFront()
	local s = self.steve
	local best, bd
	for _, u in ipairs( FindUnitsInRadius( s:GetTeamNumber(), s:GetAbsOrigin(), nil, MELEE_REACH * GRID + 80, DOTA_UNIT_TARGET_TEAM_BOTH,
		DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_NONE, FIND_CLOSEST, false ) ) do
		if u ~= s and self:Hittable( u ) then
			local d = u:GetAbsOrigin() - s:GetAbsOrigin()
			d.z = 0
			local len = d:Length2D()
			if len < 40 or d:Normalized():Dot( s:GetForwardVector() ) > 0.87 then
				if not bd or len < bd then best, bd = u, len end
			end
		end
	end
	return best
end

-- Dota's disables on Steve's hero, for Minecraft: "cc <stun 0/1> <root 0/1> <speed ratio> <disarmed 0/1>"
function MCBridge:Control( u )
	local stun = u:IsStunned() or u:IsFrozen() or u:IsNightmared() or u:HasModifier( "modifier_bane_nightmare" )
		or u:HasModifier( "modifier_bane_fiends_grip" )
	local root = stun or u:IsRooted()
	if not u:IsHexed() then self.normalSpeed = u:GetBaseMoveSpeed() end
	local base = math.max( 1, self.normalSpeed or u:GetBaseMoveSpeed() )
	local ratio = math.min( 1, u:GetIdealSpeed() / base )
	if u:IsHexed() then ratio = math.min( ratio, 140 / base ) end -- (a hex: Dota's 140 speed)
	if u:IsHexed() ~= ( self.wasHexed or false ) then
		self.wasHexed = u:IsHexed()
		print( "[mc] steve hexed " .. tostring( self.wasHexed ) .. " speed ratio " .. ratio )
	end
	local disarmed = stun or u:IsDisarmed() or u:IsHexed()
	local line = string.format( "cc %d %d %.2f %d %d", stun and 1 or 0, root and 1 or 0, ratio, disarmed and 1 or 0, u:IsHexed() and 1 or 0 )
	if line ~= self.ccLine then self.ccLine = line self:Send( line ) end
end

-- Steve as Dire's players see him: a stand-in unit (npc_mc_steve: invisible, Steve's hitbox) following his hero, which
-- draws nothing (his camera sits inside it; NoDraw also hides his selection ring and his buffs' effects from himself).
-- Minecraft's Steve (models/mc/mob_steve.vmdl: idle, run, a swing) is a particle on it shown to Dire only, gone when
-- Dire can't see him (fog of war, invisibility). It stands at his feet's real height (pillars, bridges); the body
-- follows where he looks, smoothed.
function MCBridge:Puppet( u, pos, feetY, yaw, moved )
	local now = GameRules:GetGameTime()
	local p = self.puppet
	if not p or p:IsNull() then
		p = CreateUnitByName( "npc_dota_hero_target_dummy", u:GetAbsOrigin(), false, u, u, u:GetTeamNumber() )
		if not p then return end
		p.mc_puppet = true
		p:SetOriginalModel( "models/mc/steve_ghost.vmdl" )
		p:SetModel( "models/mc/steve_ghost.vmdl" )
		p:SetModelScale( 1 )
		MC:HideAttached( p )
		p:AddNewModifier( p, nil, "modifier_mc_puppet", {} )
		self.puppet, self.modelKind = p, nil
	end
	if moved then self.movedAt = now end
	local alive = u:IsAlive()
	if alive then
		local z = GetGroundHeight( pos, nil )
		if feetY and MC.anchor then z = MC.anchor.z + ( feetY - MC_FLOOR ) * GRID end
		self.puppetGoal = Vector( pos.x, pos.y, z )
		local aloft = z - GetGroundHeight( pos, nil ) > 3 * GRID
		for _, unit in ipairs( { u, p } ) do
			local has = unit:HasModifier( "modifier_mc_aloft" )
			if aloft and not has then unit:AddNewModifier( unit, nil, "modifier_mc_aloft", {} )
			elseif not aloft and has then unit:RemoveModifierByName( "modifier_mc_aloft" ) end
		end
		local d = ( ( yaw - ( self.bodyYaw or yaw ) + math.pi ) % ( 2 * math.pi ) ) - math.pi
		self.bodyYaw = ( self.bodyYaw or yaw ) + d * ( self.bodyYaw and 0.3 or 1 )
		p:SetForwardVector( MC:DirToDota( -math.sin( self.bodyYaw ), math.cos( self.bodyYaw ) ) )
		p:RemoveNoDraw()
	else
		p:AddNoDraw()
	end
	-- (run until it has stood still a moment: poses come in bursts, a flicker between run and idle restarted the model)
	local walking = now - ( self.movedAt or -10 ) < 0.4
	local kind = not ( alive and u:CanBeSeenByAnyOpposingTeam() ) and "" or self.pose == "fly" and "fly" or self.pose == "bow" and "bow"
		or self.pose == "sneak" and ( walking and "sneak_run" or "sneak_idle" )
		or now - ( self.swingAt or -10 ) < 0.28 and "attack" or walking and "run" or "idle"
	if kind ~= "" then
		-- drawing a bow: its string in Minecraft's three steps
		if self.pose == "bow" then self.bowAt = self.bowAt or now else self.bowAt = nil end
		local item = self.held
		if self.pose == "bow" and self.held == "bow" then
			local d = now - self.bowAt
			item = d < 0.25 and "bow_pulling_0" or d < 0.5 and "bow_pulling_1" or "bow_pulling_2"
		end
		local model = ( self.elytra and "steve_elytra" or "steve" ) .. ( MC_HELD and MC_HELD[ item ] and "__" .. item or "" )
		if u:IsHexed() then
			model = u:HasModifier( "modifier_shadow_shaman_voodoo" ) and "chicken" or "pig"
			kind = walking and "run" or "idle"
		end
		kind = model .. "_" .. kind
	end
	if kind == self.modelKind then return end
	self.modelKind = kind
	if self.modelFx then
		ParticleManager:DestroyParticle( self.modelFx, true )
		ParticleManager:ReleaseParticleIndex( self.modelFx )
		self.modelFx = nil
	end
	if kind == "" then return end
	local name = "particles/mc/steve/" .. kind .. ".vpcf"
	self.modelFx = self.steveForAll and ParticleManager:CreateParticle( name, PATTACH_ABSORIGIN_FOLLOW, p ) -- (dev: "lua MCBridge.steveForAll = true")
		or ParticleManager:CreateParticleForTeam( name, PATTACH_ABSORIGIN_FOLLOW, p, DOTA_TEAM_BADGUYS )
end

-- the Minecraft player drives the first Steve hero; Minecraft owns its health
function MCBridge:MoveSteve( name, pos, frac, yaw, feetY )
	local u = self.steve
	if not u or u:IsNull() then
		for _, h in ipairs( HeroList:GetAllHeroes() ) do
			if MC:IsSteve( h ) and h:IsRealHero() then u = h break end
		end
		if not u then return end
		self.steve = u
		u.mc_player = name
		u:SetCustomHealthLabel( name, 120, 255, 120 )
		u:AddNoDraw() -- the camera sits inside him; Dota's players see and click his stand-in (MCBridge:Puppet)
		-- he never attacks on his own (Dota's auto-attack went for the blocks next to him); Minecraft does his fighting
		u:SetIdleAcquire( false )
		u:SetAcquisitionRange( 0 )
		u:SetAttackCapability( DOTA_UNIT_CAP_NO_ATTACK ) -- (Dota's auto attack kept hitting things around him)
	end
	if not u:IsAlive() then self.lastSet = nil self:Puppet( u, pos, feetY, yaw ) return end -- (a respawn moves him: no teleport for Minecraft)
	if not self.nodrawOff then u:AddNoDraw() end -- (again every time: a respawn shows the model)
	self:Control( u )
	self:Puppet( u, pos, feetY, yaw, self.lastSet and ( pos - self.lastSet ):Length2D() > 2 )
	-- pushed, pulled, thrown by a Dota spell: Dota moves him, Minecraft's player follows
	if u:IsCurrentlyHorizontalMotionControlled() or u:IsCurrentlyVerticalMotionControlled() then
		local a, p = MC.anchor, u:GetAbsOrigin()
		local fx, fz = MC:ToMC( p )
		self:Send( string.format( "follow %.2f %.2f", fx, fz ) )
		self.lastSet = p
		return
	end
	if self.lastSet and ( u:GetAbsOrigin() - self.lastSet ):Length2D() > 1000 then
		local bx, bz = MC:CellOf( u:GetAbsOrigin() )
		self:Send( string.format( "tp %d %d %d", bx, MC.heights[ bx .. "," .. bz ] or MC_FLOOR, bz ) )
		self.lastSet = u:GetAbsOrigin()
		MCWorld.capture = nil
		MCWorld:GateFxEnd( u )
		return
	end
	u:SetAbsOrigin( pos )
	self.lastSet = pos
	-- Dota makes a hero at his fountain invulnerable (and moved by SetAbsOrigin he never "walked out": creeps and
	-- towers ignored Steve for minutes after a death). Steve's fountain only heals and feeds him: never invulnerable.
	if u:HasModifier( "modifier_fountain_invulnerability" ) then
		u:RemoveModifierByName( "modifier_fountain_invulnerability" )
	end
	u:SetForwardVector( MC:DirToDota( -math.sin( yaw ), math.cos( yaw ) ) ) -- (Minecraft yaw 0 looks +z)
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

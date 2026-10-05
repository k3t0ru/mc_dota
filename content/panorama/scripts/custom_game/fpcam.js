// Dota's camera follows Steve's eyes in Minecraft. The server relays the bridge's pose as the "mc_cam" event:
// "lookAtX lookAtY yaw pitch distance heightOffset sentMillis" (Dota units; sentMillis = Minecraft's wall clock).
// Poses arrive 35-170 ms late and unevenly, so they are played back on a fixed schedule. Overlay version: each pose belongs to one
// Minecraft frame (same stamp as its picture); every Dota frame shows the newest pose at least PLAYBACK_MS old, NOT an
// interpolation (an in-between pose matches no Minecraft frame, so the layers would always slide a little). The overlay
// picks Minecraft pictures by the same rule (mcdota.delay = PLAYBACK_MS + Dota's extra frame of render latency).
// Hybrid: Dota draws the blocks itself, so poses ARE interpolated (no Minecraft picture to stay in step with): they arrive
// at the server tick rate (<= 30 Hz) while Dota renders at hundreds of fps, and the newest pose alone moves in jumps.
"use strict";
var PLAYBACK_MS = -1; // -1 = auto: just late enough that the next pose has almost always arrived (overlay version: 180)
var AUTO_PCT = 0.95, AUTO_PAD = 8; // auto delay = 90th percentile of the arrival lag + a few ms
var poses = []; // { t, v } sorted by t
var lag = [];
var recent = [], delay = 100; // arrival lags for the auto delay, current delay (eased)
var lastProbe = 0;
// Dota measures the height offset from its own smoothed "camera ground", not the real terrain. Its reference = the look-at
// height it produced minus the offset we gave it; the next offset is exactly wanted - reference (no slow feedback loop,
// which swung up and down when stepping between high and low ground).
var zFix = 0, lastOff = 0, jerkPrev = null;

// calibration: what Dota really does with the pose we asked for
function probe( v ) {
	lastProbe = Date.now();
	var eye = GameUI.GetCameraPosition(), at = GameUI.GetCameraLookAtPosition();
	var yaw = v[2] * Math.PI / 180, fx = -Math.sin( yaw ), fy = Math.cos( yaw ); // unit forward if yaw 0 looks +y
	var pts = [ [ at[0], at[1], at[2] ], [ at[0] + 100 * fy, at[1] - 100 * fx, at[2] ], [ at[0], at[1], at[2] + 100 ] ];
	var scr = pts.map( function( p ) { return Math.round( Game.WorldToScreenX( p[0], p[1], p[2] ) ) + "," + Math.round( Game.WorldToScreenY( p[0], p[1], p[2] ) ); } );
	// Dota's real focal length in pixels -> its vertical field of view, for Minecraft's fov
	var ax = Game.WorldToScreenX( pts[0][0], pts[0][1], pts[0][2] ), rx = Game.WorldToScreenX( pts[1][0], pts[1][1], pts[1][2] );
	var dEye = Math.sqrt( Math.pow( eye[0] - at[0], 2 ) + Math.pow( eye[1] - at[1], 2 ) + Math.pow( eye[2] - at[2], 2 ) );
	if ( ax >= 0 && rx > ax && dEye > 1 ) {
		var focal = ( rx - ax ) * dEye / 100;
		var vfov = 2 * Math.atan( Game.GetScreenHeight() / 2 / focal ) * 180 / Math.PI;
		GameEvents.SendCustomGameEventToServer( "mc_fov", { v: vfov } );
	}
	$.Msg( "[mc] probe want look=" + v[0].toFixed( 1 ) + "," + v[1].toFixed( 1 ) + " yaw=" + v[2].toFixed( 1 ) + " pitch=" + v[3].toFixed( 1 ) + " dist=" + v[4] + " off=" + v[5].toFixed( 1 ) +
		" | eye=" + eye.map( function( n ) { return n.toFixed( 1 ); } ) + " at=" + at.map( function( n ) { return n.toFixed( 1 ); } ) +
		" | screen at,right100,up100=" + scr.join( " " ) + " | want z=" + ( v[7] || 0 ).toFixed( 1 ) + " zFix=" + zFix.toFixed( 1 ) );
}

GameEvents.Subscribe( "mc_cam", function( e ) {
	var v = ( "" + e.v ).split( " " ).map( Number );
	if ( v.length !== 8 || isNaN( v[0] ) ) return;
	if ( poses.length && v[6] <= poses[poses.length - 1].t ) return; // a repeated or older pose
	poses.push( { t: v[6], v: v } );
	if ( poses.length > 60 ) poses.shift();
	var l = Date.now() - v[6];
	lag.push( l );
	recent.push( l );
	if ( recent.length > 40 ) recent.shift();
	if ( lag.length >= 60 ) {
		lag.sort( function( a, b ) { return a - b; } );
		$.Msg( "[mc] camera lag ms: median " + lag[30] + ", min " + lag[0] + ", max " + lag[59] + ", playback delay " + Math.round( delay ) );
		lag = [];
	}
} );

// tell the server (-> bridge -> Minecraft's overlay) how late the camera plays, once a second
var lastDelaySent = 0;
function reportDelay() {
	if ( Date.now() - lastDelaySent < 1000 ) return;
	lastDelaySent = Date.now();
	GameEvents.SendCustomGameEventToServer( "mc_delay", { d: Math.round( PLAYBACK_MS >= 0 ? PLAYBACK_MS : delay ) } );
}

function playbackDelay() {
	if ( PLAYBACK_MS >= 0 ) return PLAYBACK_MS;
	if ( recent.length >= 10 ) {
		var s = recent.slice().sort( function( a, b ) { return a - b; } );
		var want = s[Math.floor( s.length * AUTO_PCT )] + AUTO_PAD;
		delay += ( want - delay ) * 0.02; // ease, a jumping delay is a jumping camera too
	}
	return delay;
}

// smoothness probe: distance the asked-for pose / Dota's real eye cover in each 50 ms bucket (frames are 2-3 ms at high
// fps and Date.now() has 1 ms steps, so per-frame speeds are mostly rounding noise). Even motion = equal buckets;
// "jerk" = mean |bucket - mean| / mean (0 = perfectly even), printed only for buckets where the camera moved.
var sm = { bucket: 0, want: null, eye: null, w: 0, e: 0, y: 0, ws: [], es: [], ys: [], frames: 0, maxDt: 0, last: 0, dts: [] };
function smooth( v ) {
	var now = Date.now(), eye = GameUI.GetCameraPosition().concat( GameUI.GetCameraLookAtPosition() ), bk = Math.floor( now / 50 );
	if ( sm.want ) {
		sm.w += Math.hypot( v[0] - sm.want[0], v[1] - sm.want[1] );
		sm.e += Math.hypot( eye[0] - sm.eye[0], eye[1] - sm.eye[1], eye[2] - sm.eye[2] ) + Math.hypot( eye[3] - sm.eye[3], eye[4] - sm.eye[4], eye[5] - sm.eye[5] ); // eye + look-at (turning moves only the look-at)
		sm.y += Math.abs( v[2] - sm.want[2] );
		sm.frames++; sm.maxDt = Math.max( sm.maxDt, now - sm.last ); sm.dts.push( now - sm.last );
	}
	sm.last = now; sm.want = v.slice(); sm.eye = eye;
	if ( bk === sm.bucket ) return;
	if ( sm.bucket && sm.e > 1 ) { sm.ws.push( sm.w ); sm.es.push( sm.e ); sm.ys.push( sm.y ); }
	sm.bucket = bk; sm.w = sm.e = sm.y = 0;
	if ( sm.es.length >= 40 ) {
		var jerk = function( a ) {
			var m = a.reduce( function( s, x ) { return s + x; }, 0 ) / a.length;
			return m < 1e-3 ? "-" : ( a.reduce( function( s, x ) { return s + Math.abs( x - m ); }, 0 ) / a.length / m ).toFixed( 2 );
		};
		var d = sm.dts.sort( function( x, y ) { return x - y; } ), pc = function( p ) { return d[ Math.floor( ( d.length - 1 ) * p ) ]; };
		$.Msg( "[mc] smooth (50ms buckets): want move " + jerk( sm.ws ) + " yaw " + jerk( sm.ys ) + " | dota camera " + jerk( sm.es ) + " | " + sm.frames + " frames, dt p50 " + pc( 0.5 ) + " p95 " + pc( 0.95 ) + " p99 " + pc( 0.99 ) + " max " + sm.maxDt );
		sm.ws = []; sm.es = []; sm.ys = []; sm.frames = 0; sm.maxDt = 0; sm.dts = [];
	}
}

// the unit under the crosshair (screen centre), as Dota itself sees it: Minecraft's melee swings land on it (the
// invisible stand-ins Minecraft's own crosshair touches lag behind and are shaped differently)
var aimSent = -2, aimAt = 0, aimCheck = 0;
function reportAim() {
	var now = Date.now();
	if ( now - aimCheck < 100 ) return; // picking is a ray cast into the scene: expensive enough to stall frames
	aimCheck = now;
	var me = Players.GetPlayerHeroEntityIndex( Players.GetLocalPlayer() ), aim = -1;
	// the crosshair and a few points around it (one pixel flickered between the unit and nothing)
	var cx = Game.GetScreenWidth() / 2, cy = Game.GetScreenHeight() / 2, r = Game.GetScreenHeight() * 0.015;
	var pts = [ [ 0, 0 ], [ r, 0 ], [ -r, 0 ], [ 0, r ], [ 0, -r ] ];
	for ( var k = 0; k < pts.length && aim < 0; k++ ) {
		var hits = GameUI.FindScreenEntities( [ cx + pts[k][0], cy + pts[k][1] ] ) || [];
		for ( var i = 0; i < hits.length; i++ ) {
			var e = hits[i].entityIndex;
			// (not his own stand-in, owned by him, in front of the camera in third person; not the blocks' units)
			if ( e !== me && e !== puppetEnt && Entities.IsAlive( e ) && !Entities.IsInvulnerable( e ) && Entities.GetPlayerOwnerID( e ) !== Players.GetLocalPlayer()
				&& ( Entities.GetUnitName( e ) || "" ).indexOf( "npc_mc_" ) !== 0 ) { aim = e; break; }
		}
	}
	if ( aim === aimSent && now - aimAt < 500 ) return;
	aimAt = now;
	aimSent = aim;
	GameEvents.SendCustomGameEventToServer( "mc_aim", { e: aim } );
}

// debug: how far Dota's look-at height ends up from what was asked last frame, and how much that error jumps frame
// to frame (vertical jitter of Dota's picture against Minecraft's: the traders "bobbing")
var CG_LOG = false; // debug: Dota's camera ground under the look-at point, every frame
var zHist = [], zJerkSum = 0, zJerkMax = 0, zJerkN = 0, zSmooth = null, zPrevWant = null, zStep = 0, zWant = null, zErr = [], zLog = 0, zGround = 0;
function zStat( lz ) {
	if ( zWant !== null ) zErr.push( lz - zWant );
	zHist.push( lz ); // the camera's own height: its second difference = jerks (0 on a steady glide)
	if ( zHist.length >= 3 ) {
		var j = Math.abs( zHist[zHist.length - 1] - 2 * zHist[zHist.length - 2] + zHist[zHist.length - 3] );
		zJerkSum += j; zJerkMax = Math.max( zJerkMax, j ); zJerkN++;
	}
	if ( zHist.length > 3 ) zHist.shift();
	if ( zWant !== null && zPrevWant !== null ) zStep = Math.max( zStep, Math.abs( zWant - zPrevWant ) );
	zPrevWant = zWant;
	if ( Date.now() - zLog > 3000 && zErr.length > 10 ) {
		var a = 0, d = 0, m = 0;
		for ( var i = 0; i < zErr.length; i++ ) {
			a += Math.abs( zErr[i] );
			m = Math.max( m, Math.abs( zErr[i] ) );
			if ( i ) d += Math.abs( zErr[i] - zErr[i - 1] );
		}
		$.Msg( "[mc] zjitter frames " + zErr.length + " mean|err| " + ( a / zErr.length ).toFixed( 2 ) + " max " + m.toFixed( 1 ) + " mean|d err| " + ( d / ( zErr.length - 1 ) ).toFixed( 2 ) + " max want step " + zStep.toFixed( 1 ) + " | camera jerk mean " + ( zJerkSum / Math.max( 1, zJerkN ) ).toFixed( 2 ) + " max " + zJerkMax.toFixed( 1 ) );
		zJerkSum = 0; zJerkMax = 0; zJerkN = 0;
		zStep = 0;
		zErr = [];
		zLog = Date.now();
	}
}

function frame() {
	var t = Date.now() - playbackDelay();
	reportDelay();
	reportAim();
	var a = null, b = null;
	for ( var i = 0; i < poses.length; i++ ) {
		if ( poses[i].t <= t ) a = poses[i];
		else { b = poses[i]; break; }
	}
	if ( !a ) a = b; // nothing that old yet: the oldest pose
	if ( a ) {
		var v = a.v;
		if ( b && b !== a ) { // in between two Minecraft frames: blend them (yaw is unwrapped, so plain lerp works)
			var k = ( t - a.t ) / ( b.t - a.t );
			v = a.v.map( function( x, j ) { return x + ( b.v[j] - x ) * k; } );
		} else if ( !b && poses.length >= 2 ) {
			// the next pose is late (now and then it arrives after its moment): keep moving the way the last two did,
			// up to 60 ms, instead of stopping dead and then jumping when it comes
			var p0 = poses[poses.length - 2], p1 = poses[poses.length - 1];
			// (two poses a hair apart in time made this a huge step: the camera flew at the floor and back. At most one
			// step's worth, from poses at least 8 ms apart)
			var span = p1.t - p0.t;
			var k2 = span >= 8 ? Math.min( Math.min( t - p1.t, 60 ) / span, 1 ) : 0;
			if ( k2 > 0 ) v = p1.v.map( function( x, j ) { return j === 6 ? x : x + ( x - p0.v[j] ) * k2; } );
		}
		GameUI.SetCameraTarget( -1 );
		GameUI.SetCameraTargetPosition( [ v[0], v[1], 0 ], 0.001 ); // (Dota ignores the z: its camera ground decides) // lerp = transition seconds; called every frame, anything bigger makes the camera trail ("float")
		GameUI.SetCameraYaw( v[2] );
		// looking up: Dota's camera takes 360 - x (a negative pitch is a top-down view); never past straight up/down
		var raw = Math.max( -89.9, Math.min( 89.9, v[3] ) );
		var pitch = raw < 0 ? raw + 360 : raw;
		GameUI.SetCameraPitchMin( pitch );
		GameUI.SetCameraPitchMax( pitch );
		GameUI.SetCameraDistance( v[4] );
		var lzp = GameUI.GetCameraLookAtPosition();
		var lz = lzp[2];
		if ( CG_LOG ) $.Msg( "[mc] cg " + lzp[0].toFixed( 1 ) + " " + lzp[1].toFixed( 1 ) + " " + ( lz - lastOff ).toFixed( 1 ) );
		zStat( lz );
		// Dota's camera ground under last frame's look-at point (the offset shows one frame late: measured exactly);
		// the error left is how much that ground changes in a frame, so Dota smooths it (dota_camera_z_interp_speed)
		var ref = lz - lastOff;
		// the wanted height itself glides over a few frames (Minecraft's steps, Dota's ground under the eye)
		zSmooth = zSmooth === null || Math.abs( v[7] - zSmooth ) > 300 ? v[7] : zSmooth + ( v[7] - zSmooth ) * 0.4;
		lastOff = zSmooth - ref;
		// (never a non-number: once NaN, Dota's camera went nowhere and the screen stayed grey; start over instead.
		// A filter holding back "jumps" of the look-at height did that: the height answers our own offset, so holding it
		// back fed the loop until it ran off)
		if ( !isFinite( lastOff ) || !isFinite( lz ) ) { lastOff = 0; zSmooth = null; }
		zWant = v[7];
		GameUI.SetCameraLookAtPositionHeightOffset( lastOff );
		// diagnostics (the camera dips at the floor now and then): any sudden jump of the pose or the height, in full
		if ( jerkPrev && ( Math.abs( pitch - jerkPrev[0] ) > 25 && Math.abs( pitch - jerkPrev[0] ) < 335 || Math.abs( lastOff - jerkPrev[1] ) > 80
			|| Math.abs( lz - jerkPrev[2] ) > 80 ) )
			$.Msg( "[mc] JERK pitch " + jerkPrev[0].toFixed( 1 ) + "->" + pitch.toFixed( 1 ) + " off " + jerkPrev[1].toFixed( 1 ) + "->" + lastOff.toFixed( 1 ) +
				" lz " + jerkPrev[2].toFixed( 1 ) + "->" + lz.toFixed( 1 ) + " want " + v[7].toFixed( 1 ) + " poses " + poses.length + " t-lag " + ( Date.now() - v[6] ).toFixed( 0 ) );
		jerkPrev = [ pitch, lastOff, lz ];
		if ( Date.now() - lastProbe > 2000 ) probe( v );
		smooth( v );
	}
	$.Schedule( 0, frame );
}
// Dota's tooltips (the cursor sits at the screen's centre: a rune there showed its description): never shown
function hideTooltips() {
	var root = $.GetContextPanel();
	while ( root.GetParent() ) root = root.GetParent();
	var t = root.FindChildTraverse( "Tooltips" );
	if ( t ) t.style.opacity = "0";
	$.Schedule( 1, hideTooltips );
}
// Steve's health bars: Dota's own are off on his screen (dota_hud_healthbars 0: drawn at a fixed size, the far ones
// covered his view), these show the units near him only. (Dota's players keep Dota's bars, at any distance.)
var BAR_RANGE = 1600, bars = {}, barUnits = [], barListAt = 0;
// Steve's own stand-in (MCBridge:Puppet tells which): his crosshair and bars skip it
var puppetEnt = -1;
GameEvents.Subscribe( "mc_puppet", function( e ) { puppetEnt = e.e; } );
function nearBars() {
	var root = $( "#Bars" );
	var me = Players.GetPlayerHeroEntityIndex( Players.GetLocalPlayer() );
	var myTeam = Players.GetTeam( Players.GetLocalPlayer() );
	if ( Date.now() - barListAt > 250 ) { // (the units near him: a few times a second)
		barListAt = Date.now();
		barUnits = [];
		var at = Entities.GetAbsOrigin( me ), all = Entities.GetAllEntities();
		for ( var i = 0; i < all.length; i++ ) {
			var e = all[i];
			if ( e === me || e === puppetEnt || !Entities.IsValidEntity( e ) || !Entities.IsAlive( e ) || !( Entities.GetMaxHealth( e ) > 0 ) ) continue;
			var name = Entities.GetUnitName( e ) || "";
			if ( name === "" || name.indexOf( "npc_mc_" ) === 0 || Entities.NoHealthBar( e ) ) continue; // (blocks, his stand-in)
			var p = Entities.GetAbsOrigin( e );
			if ( at && p && Math.pow( p[0] - at[0], 2 ) + Math.pow( p[1] - at[1], 2 ) < BAR_RANGE * BAR_RANGE ) barUnits.push( e );
		}
	}
	var k = 1080 / Game.GetScreenHeight(), shown = {};
	for ( var j = 0; j < barUnits.length; j++ ) {
		var u = barUnits[j];
		if ( !Entities.IsValidEntity( u ) || !Entities.IsAlive( u ) ) continue;
		var o = Entities.GetAbsOrigin( u ), off = Entities.GetHealthBarOffset( u ) || 200;
		var x = Game.WorldToScreenX( o[0], o[1], o[2] + off ), y = Game.WorldToScreenY( o[0], o[1], o[2] + off );
		if ( !( x >= 0 && y >= 0 ) ) continue; // (behind the camera)
		var b = bars[u];
		if ( !b ) {
			b = $.CreatePanel( "Panel", root, "" );
			b.hittest = false;
			b.style.backgroundColor = "#000000cc";
			b.style.border = "1px solid #000000";
			b.fill = $.CreatePanel( "Panel", b, "" );
			b.fill.style.height = "100%";
			bars[u] = b;
		}
		var w = Entities.IsHero( u ) ? 96 : 64;
		b.style.width = w + "px";
		b.style.height = ( Entities.IsHero( u ) ? 9 : 6 ) + "px";
		b.style.x = ( x * k - w / 2 ) + "px";
		b.style.y = ( y * k ) + "px";
		b.fill.style.width = ( 100 * Entities.GetHealth( u ) / Math.max( 1, Entities.GetMaxHealth( u ) ) ) + "%";
		b.fill.style.backgroundColor = Entities.GetTeamNumber( u ) === myTeam ? "#3fbf3f" : "#d23c32";
		b.visible = true;
		shown[u] = true;
	}
	for ( var id in bars ) if ( !shown[id] ) bars[id].visible = false;
	$.Schedule( 0, nearBars );
}

// Only Steve's client (the Minecraft player, Radiant's only player) is steered from Minecraft; Dire's Dota players keep
// Dota as it is
function start() {
	var hero = Players.GetPlayerHeroEntityIndex( Players.GetLocalPlayer() );
	if ( hero === -1 ) { $.Schedule( 0.5, start ); return; } // no hero yet
	if ( Players.GetTeam( Players.GetLocalPlayer() ) !== DOTATeam_t.DOTA_TEAM_GOODGUYS ) return; // a Dota player
	hideTooltips();
	// Steve's screen is Minecraft's: hide Dota's HUD (top bar, minimap, abilities, inventory, shop, chat...)
	for ( var k in DotaDefaultUIElement_t ) GameUI.SetDefaultUIEnabled( DotaDefaultUIElement_t[k], false );
	frame();
	nearBars();
}
start();

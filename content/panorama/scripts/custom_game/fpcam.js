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
var AUTO_PCT = 0.9, AUTO_PAD = 8; // auto delay = 90th percentile of the arrival lag + a few ms
var poses = []; // { t, v } sorted by t
var lag = [];
var recent = [], delay = 100; // arrival lags for the auto delay, current delay (eased)
var lastProbe = 0;
// Dota measures the height offset from its own smoothed "camera ground", not the real terrain. Its reference = the look-at
// height it produced minus the offset we gave it; the next offset is exactly wanted - reference (no slow feedback loop,
// which swung up and down when stepping between high and low ground).
var zFix = 0, lastOff = 0;

// calibration: what Dota really does with the pose we asked for
function probe( v ) {
	lastProbe = Date.now();
	var eye = GameUI.GetCameraPosition(), at = GameUI.GetCameraLookAtPosition();
	var yaw = v[2] * Math.PI / 180, fx = -Math.sin( yaw ), fy = Math.cos( yaw ); // unit forward if yaw 0 looks +y
	var pts = [ [ at[0], at[1], at[2] ], [ at[0] + 100 * fy, at[1] - 100 * fx, at[2] ], [ at[0], at[1], at[2] + 100 ] ];
	var scr = pts.map( function( p ) { return Math.round( Game.WorldToScreenX( p[0], p[1], p[2] ) ) + "," + Math.round( Game.WorldToScreenY( p[0], p[1], p[2] ) ); } );
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
var sm = { bucket: 0, want: null, eye: null, w: 0, e: 0, y: 0, ws: [], es: [], ys: [], frames: 0, maxDt: 0, last: 0 };
function smooth( v ) {
	var now = Date.now(), eye = GameUI.GetCameraPosition().concat( GameUI.GetCameraLookAtPosition() ), bk = Math.floor( now / 50 );
	if ( sm.want ) {
		sm.w += Math.hypot( v[0] - sm.want[0], v[1] - sm.want[1] );
		sm.e += Math.hypot( eye[0] - sm.eye[0], eye[1] - sm.eye[1], eye[2] - sm.eye[2] ) + Math.hypot( eye[3] - sm.eye[3], eye[4] - sm.eye[4], eye[5] - sm.eye[5] ); // eye + look-at (turning moves only the look-at)
		sm.y += Math.abs( v[2] - sm.want[2] );
		sm.frames++; sm.maxDt = Math.max( sm.maxDt, now - sm.last );
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
		$.Msg( "[mc] smooth (50ms buckets): want move " + jerk( sm.ws ) + " yaw " + jerk( sm.ys ) + " | dota camera " + jerk( sm.es ) + " | " + sm.frames + " frames, max dt " + sm.maxDt );
		sm.ws = []; sm.es = []; sm.ys = []; sm.frames = 0; sm.maxDt = 0;
	}
}

function frame() {
	var t = Date.now() - playbackDelay();
	reportDelay();
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
		}
		GameUI.SetCameraTarget( -1 );
		GameUI.SetCameraTargetPosition( [ v[0], v[1], 0 ], 0.001 ); // lerp = transition seconds; called every frame, anything bigger makes the camera trail ("float")
		GameUI.SetCameraYaw( v[2] );
		GameUI.SetCameraPitchMin( v[3] );
		GameUI.SetCameraPitchMax( v[3] );
		GameUI.SetCameraDistance( v[4] );
		var ref = GameUI.GetCameraLookAtPosition()[2] - lastOff; // Dota's own ground under the look-at point
		lastOff = v[7] - ref;
		zFix = lastOff - v[5];
		GameUI.SetCameraLookAtPositionHeightOffset( lastOff );
		if ( Date.now() - lastProbe > 2000 ) probe( v );
		smooth( v );
	}
	$.Schedule( 0, frame );
}
// Steve's screen is Minecraft's: hide Dota's HUD (top bar, minimap, abilities, inventory, shop, chat...)
for ( var k in DotaDefaultUIElement_t ) GameUI.SetDefaultUIEnabled( DotaDefaultUIElement_t[k], false );
frame();

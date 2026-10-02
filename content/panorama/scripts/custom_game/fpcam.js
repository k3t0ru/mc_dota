// Dota's camera follows Steve's eyes in Minecraft. The server relays the bridge's pose as the "mc_cam" event:
// "lookAtX lookAtY yaw pitch distance heightOffset sentMillis" (Dota units; sentMillis = Minecraft's wall clock).
// Poses arrive 35-170 ms late and unevenly, so they are played back on a fixed schedule. Each pose belongs to one
// Minecraft frame (same stamp as its picture); every Dota frame shows the newest pose at least PLAYBACK_MS old, NOT an
// interpolation (an in-between pose matches no Minecraft frame, so the layers would always slide a little). The overlay
// picks Minecraft pictures by the same rule (mcdota.delay = PLAYBACK_MS + Dota's extra frame of render latency).
"use strict";
var PLAYBACK_MS = 0; // hybrid: Dota draws the blocks itself, so nothing to wait for: always the newest pose (overlay version: 180)
var poses = []; // { t, v } sorted by t
var lag = [];
var lastProbe = 0;
// Dota measures the height offset from its own smoothed "camera ground", not the real terrain, so the look-at point
// ends up too low in hollows and lags over cliffs. Feedback fixes it: nudge the offset by the remaining height error.
var zFix = 0;

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
	poses.push( { t: v[6], v: v } );
	if ( poses.length > 60 ) poses.shift();
	lag.push( Date.now() - v[6] );
	if ( lag.length >= 60 ) {
		lag.sort( function( a, b ) { return a - b; } );
		$.Msg( "[mc] camera lag ms: median " + lag[30] + ", min " + lag[0] + ", max " + lag[59] );
		lag = [];
	}
} );


function frame() {
	var t = Date.now() - PLAYBACK_MS;
	var a = null;
	for ( var i = 0; i < poses.length && poses[i].t <= t; i++ ) a = poses[i];
	if ( a ) {
		var v = a.v;
		GameUI.SetCameraTarget( -1 );
		GameUI.SetCameraTargetPosition( [ v[0], v[1], 0 ], 0.001 ); // lerp = transition seconds; called every frame, anything bigger makes the camera trail ("float")
		GameUI.SetCameraYaw( v[2] );
		GameUI.SetCameraPitchMin( v[3] );
		GameUI.SetCameraPitchMax( v[3] );
		GameUI.SetCameraDistance( v[4] );
		var err = v[7] - GameUI.GetCameraLookAtPosition()[2]; // wanted absolute look-at height minus what Dota did
		if ( Math.abs( err ) < 400 ) zFix += err * 0.5;
		GameUI.SetCameraLookAtPositionHeightOffset( v[5] + zFix );
		if ( Date.now() - lastProbe > 2000 ) probe( v );
	}
	$.Schedule( 0, frame );
}
// Steve's screen is Minecraft's: hide Dota's HUD (top bar, minimap, abilities, inventory, shop, chat...)
for ( var k in DotaDefaultUIElement_t ) GameUI.SetDefaultUIEnabled( DotaDefaultUIElement_t[k], false );
frame();

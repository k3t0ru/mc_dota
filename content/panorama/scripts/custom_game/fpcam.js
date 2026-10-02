// Dota's camera follows Steve's eyes in Minecraft. The server relays the bridge's pose as the "mc_cam" event:
// "lookAtX lookAtY yaw pitch distance heightOffset sentMillis" (Dota units; sentMillis = Minecraft's wall clock).
// Poses arrive 35-170 ms late and unevenly, so they are played back on a fixed schedule: every Dota frame shows the
// pose Minecraft had exactly PLAYBACK_MS ago (interpolated). The overlay delays Minecraft's frames by the same amount
// (mcdota.delay), so both layers show the same instant and nothing swims.
"use strict";
var PLAYBACK_MS = 150; // must cover the worst lag ("[mc] camera lag" in the log)
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

function mix( a, b, f ) { return a + ( b - a ) * f; }
function mixAngle( a, b, f ) { var d = ( ( b - a ) % 360 + 540 ) % 360 - 180; return a + d * f; }

function frame() {
	var t = Date.now() - PLAYBACK_MS;
	var a = null, b = null;
	for ( var i = 0; i < poses.length; i++ ) {
		if ( poses[i].t <= t ) a = poses[i]; else { b = poses[i]; break; }
	}
	if ( a ) {
		var v = a.v;
		if ( b ) {
			var f = ( t - a.t ) / Math.max( 1, b.t - a.t ), w = b.v;
			v = [ mix( v[0], w[0], f ), mix( v[1], w[1], f ), mixAngle( v[2], w[2], f ), mix( v[3], w[3], f ), v[4], mix( v[5], w[5], f ), v[6], mix( v[7], w[7], f ) ];
		}
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
frame();

// Dota's camera follows Steve's eyes in Minecraft. The server relays the bridge's pose as the "mc_cam" event:
// "lookAtX lookAtY yaw pitch distance heightOffset sentMillis" (Dota units; sentMillis = Minecraft's wall clock).
// Poses arrive 35-170 ms late and unevenly, so they are played back on a fixed schedule: every Dota frame shows the
// pose Minecraft had exactly PLAYBACK_MS ago (interpolated). The overlay delays Minecraft's frames by the same amount
// (mcdota.delay), so both layers show the same instant and nothing swims.
"use strict";
var PLAYBACK_MS = 150; // must cover the worst lag ("[mc] camera lag" in the log)
var poses = []; // { t, v } sorted by t
var lag = [];

GameEvents.Subscribe( "mc_cam", function( e ) {
	var v = ( "" + e.v ).split( " " ).map( Number );
	if ( v.length !== 7 || isNaN( v[0] ) ) return;
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
			v = [ mix( v[0], w[0], f ), mix( v[1], w[1], f ), mixAngle( v[2], w[2], f ), mix( v[3], w[3], f ), v[4], mix( v[5], w[5], f ) ];
		}
		GameUI.SetCameraTarget( -1 );
		GameUI.SetCameraTargetPosition( [ v[0], v[1], 0 ], 1 ); // lerp 1 = jump there now (0 creeps after it, the camera "floats")
		GameUI.SetCameraYaw( v[2] );
		GameUI.SetCameraPitchMin( v[3] );
		GameUI.SetCameraPitchMax( v[3] );
		GameUI.SetCameraDistance( v[4] );
		GameUI.SetCameraLookAtPositionHeightOffset( v[5] );
	}
	$.Schedule( 0, frame );
}
frame();

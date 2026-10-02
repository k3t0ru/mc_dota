// Dota's camera follows Steve's eyes in Minecraft. The server relays the bridge's pose as the "mc_cam" event:
// "lookAtX lookAtY yaw pitch distance heightOffset sentMillis" (Dota units; sentMillis = Minecraft's wall clock).
// Poses arrive 35-170 ms late and unevenly, so they are played back on a fixed schedule. Each pose belongs to one
// Minecraft frame (same stamp as its picture); every Dota frame shows the newest pose at least PLAYBACK_MS old, NOT an
// interpolation (an in-between pose matches no Minecraft frame, so the layers would always slide a little). The overlay
// picks Minecraft pictures by the same rule (mcdota.delay = PLAYBACK_MS + Dota's extra frame of render latency).
"use strict";
// Prediction: poses arrive ~100 ms late; extrapolate from the last two (velocity) to Minecraft's present moment.
var LEAD_MS = 33; // Dota puts the camera on screen about one frame after we set it: aim at that moment
var PREDICT_MAX_MS = 200; // never extrapolate further than this (a stale stream would fly off)
var errs = { raw: [], pred: [] }, shown = []; // calibration: how far the shown camera is from the truth that arrives later
var PLAYBACK_MS = 0; // hybrid: Dota draws the blocks itself, so nothing to wait for: always the newest pose (overlay version: 180)
var poses = []; // { t, v } sorted by t
var lag = [];
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
	// truth for moment v[6] just arrived: compare with what was on screen then (shown = predicted, raw = newest known)
	for ( var k = 0; k < shown.length; k++ ) {
		if ( Math.abs( shown[k].t - v[6] ) < 17 ) {
			errs.raw.push( Math.abs( angDiff( shown[k].raw, v[2] ) ) );
			errs.pred.push( Math.abs( angDiff( shown[k].pred, v[2] ) ) );
		}
	}
	shown = shown.filter( function( x ) { return x.t > v[6] - 50; } );
	if ( errs.raw.length >= 60 ) {
		var avg = function( a ) { return ( a.reduce( function( x, y ) { return x + y; }, 0 ) / a.length ).toFixed( 2 ); };
		$.Msg( "[mc] yaw error on screen, deg: without prediction " + avg( errs.raw ) + ", with " + avg( errs.pred ) );
		errs = { raw: [], pred: [] };
	}
	poses.push( { t: v[6], v: v } );
	if ( poses.length > 60 ) poses.shift();
	lag.push( Date.now() - v[6] );
	if ( lag.length >= 60 ) {
		lag.sort( function( a, b ) { return a - b; } );
		$.Msg( "[mc] camera lag ms: median " + lag[30] + ", min " + lag[0] + ", max " + lag[59] );
		lag = [];
	}
} );


function angDiff( a, b ) { return ( ( b - a ) % 360 + 540 ) % 360 - 180; }

// pose at wall-clock time t, extrapolated from the two newest poses A (older) and B
function extrapolate( A, B, t ) {
	var dt = B.t - A.t;
	if ( dt <= 0 || dt > 200 ) return B.v; // gap in the stream: no velocity
	var f = Math.min( t - B.t, PREDICT_MAX_MS ) / dt;
	var a = A.v, b = B.v;
	return [ b[0] + ( b[0] - a[0] ) * f, b[1] + ( b[1] - a[1] ) * f, b[2] + angDiff( a[2], b[2] ) * f,
		Math.max( 3, b[3] + ( b[3] - a[3] ) * f ), b[4], b[5] + ( b[5] - a[5] ) * f, b[6], b[7] + ( b[7] - a[7] ) * f ];
}

function frame() {
	var t = Date.now() - PLAYBACK_MS;
	var a = null;
	for ( var i = 0; i < poses.length && poses[i].t <= t; i++ ) a = poses[i];
	if ( a ) {
		var v = poses.length >= 2 ? extrapolate( poses[poses.length - 2], poses[poses.length - 1], Date.now() + LEAD_MS ) : a.v;
		shown.push( { t: Date.now() + LEAD_MS, raw: poses[poses.length - 1].v[2], pred: v[2] } );
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
	}
	$.Schedule( 0, frame );
}
// Steve's screen is Minecraft's: hide Dota's HUD (top bar, minimap, abilities, inventory, shop, chat...)
for ( var k in DotaDefaultUIElement_t ) GameUI.SetDefaultUIEnabled( DotaDefaultUIElement_t[k], false );
frame();

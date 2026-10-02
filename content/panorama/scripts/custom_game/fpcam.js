// Camera test: can Dota look from a hero's eyes, almost level? Presets cycle every 8 s for screenshots.
"use strict";
var TESTS = [ [ 60, 1134, 0 ], [ 30, 600, 100 ], [ 15, 300, 150 ], [ 5, 150, 150 ], [ 0, 50, 150 ] ];
var i = 0;
function tryCall( name, f ) { try { f(); return name + " ok"; } catch ( e ) { return name + " ERR " + e; } }
function apply() {
	var t = TESTS[ i % TESTS.length ];
	var hero = Players.GetPlayerHeroEntityIndex( Players.GetLocalPlayer() );
	var log = [ "pitch=" + t[0] + " dist=" + t[1] + " h=" + t[2] + " hero=" + hero,
		tryCall( "pitch", function() { GameUI.SetCameraPitchMin( t[0] ); GameUI.SetCameraPitchMax( t[0] ); } ),
		tryCall( "dist", function() { GameUI.SetCameraDistance( t[1] ); } ),
		tryCall( "height", function() { GameUI.SetCameraLookAtPositionHeightOffset( t[2] ); } ),
		tryCall( "target", function() { if ( hero >= 0 ) GameUI.SetCameraTarget( hero ); } ) ];
	$( "#CamInfo" ).text = log.join( "\n" );
	$.Msg( "[mc] cam " + log.join( " | " ) );
}
// presets: 60/1134/0 = stock Dota, 5/150/150 = over-the-shoulder with horizon (verified 2026-10-02)
function next() { apply(); }
next();

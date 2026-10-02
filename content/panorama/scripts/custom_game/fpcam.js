// Dota's camera follows Steve's eyes in Minecraft. The server relays the bridge's pose as the "mc_cam" event:
// "lookAtX lookAtY yaw pitch distance heightOffset" (Dota units). Panorama has no HTTP, hence the relay.
"use strict";
GameEvents.Subscribe( "mc_cam", function( e ) {
	var v = ( "" + e.v ).split( " " ).map( Number );
	if ( v.length !== 6 || isNaN( v[0] ) ) return;
	GameUI.SetCameraTarget( -1 );
	GameUI.SetCameraTargetPosition( [ v[0], v[1], 0 ], 1 ); // lerp 1 = jump there now (0 creeps after it, the camera "floats")
	GameUI.SetCameraYaw( v[2] );
	GameUI.SetCameraPitchMin( v[3] );
	GameUI.SetCameraPitchMax( v[3] );
	GameUI.SetCameraDistance( v[4] );
	GameUI.SetCameraLookAtPositionHeightOffset( v[5] );
} );

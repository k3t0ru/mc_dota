// Hero pick: Steve (Radiant's player, the Minecraft side) plays Kunkka's slot; wherever the pick screen shows
// Kunkka's portrait, show Steve's face instead (Minecraft's own steve.png head, tools/gen_steve.py)
"use strict";
var STEVE_HERO = "npc_dota_hero_kunkka"; // STEVE in addon_game_mode.lua
var FACE = "file://{images}/custom_game/steve_face.png";

function root() {
	var p = $.GetContextPanel();
	while ( p.GetParent() ) p = p.GetParent();
	return p;
}

function steveIt( p ) {
	var type = p.paneltype;
	if ( type === "DOTAHeroImage" || type === "DOTAHeroMovie" ) {
		var name = "";
		try { name = p.heroname || ""; } catch ( e ) {}
		// a picture laid over the portrait (a child draws on top of it, a movie's too)
		var face = p.FindChild( "mcSteveFace" );
		if ( name === STEVE_HERO && !face ) {
			face = $.CreatePanel( "Image", p, "mcSteveFace" );
			face.SetImage( FACE );
			face.SetScaling( "stretch-to-cover-preserve-aspect" );
			face.hittest = false;
			face.style.width = "100%";
			face.style.height = "100%";
		}
		if ( face ) face.visible = name === STEVE_HERO; // (a reused panel showing someone else now)
		return;
	}
	for ( var i = 0; i < p.GetChildCount(); i++ ) steveIt( p.GetChild( i ) );
}

function tick() {
	steveIt( root() );
	// often during the pick; then now and then (the top bar's portraits)
	$.Schedule( Game.GetState() > DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME ? 3 : 0.3, tick );
}
tick();

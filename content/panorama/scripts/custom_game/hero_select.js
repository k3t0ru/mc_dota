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

// (walking all of Dota's HUD took tens of ms: a hitch every few seconds. Now: the pick screen while picking, then only
// the top bar, and never on Steve's own client, whose Dota HUD is hidden and whose camera must not stutter)
function tick() {
	if ( Players.GetTeam( Players.GetLocalPlayer() ) === DOTATeam_t.DOTA_TEAM_GOODGUYS && Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME ) return;
	var picking = Game.GetState() < DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME;
	var r = root();
	var where = picking ? r.FindChildTraverse( "PreGame" ) || r : r.FindChildTraverse( "topbar" );
	if ( where ) steveIt( where );
	$.Schedule( picking ? 0.5 : 5, tick );
}
tick();

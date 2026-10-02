package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.server.MinecraftServer;

// World rules for playing on top of Dota. The world is a diggable superflat (bedrock, stone, dirt) whose top layer is
// podzol at y -1; podzol (and mud-brick slabs for half steps) are retextured pure magenta, so the overlay turns the
// surface into a hole showing Dota's ground, while still hiding Minecraft blocks behind Dota's hills.
public final class Arena {
	public static final int RADIUS = 160; // blocks around MC (0,0) that are synced with Dota; 1 block = 64 Dota units

	private static final String[] RULES = {
		"weather clear", // rain over Dota looks awful: always clear (rendering is also cut in LevelRendererMixin)
		"gamerule doWeatherCycle false", "gamerule advance_weather false", // old and new names; the wrong one just fails
		"gamerule doMobSpawning false", "gamerule spawn_mobs false",
		"time set noon", "gamerule doDaylightCycle false", "gamerule advance_time false", // night would darken the magenta
		"effect give @p minecraft:instant_health 1 10 true", "effect give @p minecraft:saturation 1 20 true", // fresh start
		"tp @p 0.5 0 0.5",
		"kill @e[tag=dota]", // stand-ins saved in the world by an earlier session (they come back invisible)
		// death screens need the mouse, which only works in-game here: respawn at the start right away
		"gamerule keepInventory true", "gamerule keep_inventory true",
		"gamerule doImmediateRespawn true", "gamerule immediate_respawn true", "setworldspawn 0 0 0", "spawnpoint @p 0 0 0", // start where the Dota hero spawns (MC 0,0), not wherever the last session ended
		"attribute @p minecraft:knockback_resistance base set 1", // Dota hits hurt but don't shove the camera around
		// ponytail: test kit while the world starts empty; real progression comes later
		"clear @p", "give @p minecraft:diamond_sword", "give @p minecraft:diamond_pickaxe",
		"give @p minecraft:cobblestone 64", "give @p minecraft:oak_planks 64", "give @p minecraft:oak_log 64",
	};

	public static void ensure(Minecraft mc) {
		MinecraftServer server = mc.getSingleplayerServer();
		if (server == null) return;
		server.execute(() -> {
			for (String c : RULES) server.getCommands().performPrefixedCommand(server.createCommandSourceStack().withSuppressedOutput(), c);
		});
	}
}

package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.server.MinecraftServer;

// World rules for playing on top of Dota. The world is a diggable superflat (bedrock, stone, dirt) whose top layer is
// podzol at y -1; podzol (top AND sides: columns not rebuilt yet, e.g. in half-loaded chunks at the view edge, keep the
// flat default and must not show) and mud-brick slabs for half steps are retextured pure magenta, so the overlay turns the
// surface into a hole showing Dota's ground, while still hiding Minecraft blocks behind Dota's hills.
public final class Arena {
	public static final int RADIUS = 160; // blocks around MC (0,0) that are synced with Dota; 1 block = 64 Dota units

	private static final String[] RULES = {
		"weather clear", // rain over Dota looks awful: always clear (rendering is also cut in LevelRendererMixin)
		"gamerule doWeatherCycle false", "gamerule advance_weather false", // old and new names; the wrong one just fails
		"gamerule doMobSpawning false", "gamerule spawn_mobs false",
		"time set noon", "gamerule doDaylightCycle false", "gamerule advance_time false", // night would darken the magenta
		"effect give @p minecraft:instant_health 1 10 true", "effect give @p minecraft:saturation 1 20 true", // fresh start
		"bossbar remove mcdota:target", // the old target bar (gone)
		// death screens need the mouse, which only works in-game here: respawn at the start right away
		"gamerule keepInventory true", "gamerule keep_inventory true",
		"gamerule doImmediateRespawn true", "gamerule immediate_respawn true", // spawn point and the start position: Progress.joined/spawnAt
		// the starting kit comes with every new Dota match (Progress.newMatch)
	};

	public static void ensure(Minecraft mc) {
		MinecraftServer server = mc.getSingleplayerServer();
		if (server == null) return;
		server.execute(() -> {
			for (String c : RULES) server.getCommands().performPrefixedCommand(server.createCommandSourceStack().withSuppressedOutput(), c);
			Sync.discard(server, "dota"); // stand-ins saved in the world by an earlier session
			Progress.attributes(server); // health by Dota level, sweep, knockback resistance
			Progress.joined(server); // to the spawn point (the market square once Dota sent it)
		});
	}
}

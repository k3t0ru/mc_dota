package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.server.MinecraftServer;

// World rules for playing on top of Dota. The test world itself is a superflat of 4 barrier layers (invisible, solid),
// so Minecraft draws nothing but real blocks, mobs, the hand and the HUD.
public final class Arena {
	public static final int RADIUS = 160; // blocks around MC (0,0) that are synced with Dota; 1 block = 64 Dota units

	private static final String[] RULES = {
		"weather clear", // rain over Dota looks awful: always clear (rendering is also cut in LevelRendererMixin)
		"gamerule doWeatherCycle false", "gamerule advance_weather false", // old and new names; the wrong one just fails
		"gamerule doMobSpawning false", "gamerule spawn_mobs false",
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

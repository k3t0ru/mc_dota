package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.server.MinecraftServer;

// Minecraft's own ground must not hide Dota: the flat world's layers become invisible barrier blocks (still solid).
// Same commands as bridge.py runs on the dedicated server; here for the single-player test world.
public final class Arena {
	public static final int RADIUS = 160; // blocks around MC (0,0); 1 block = 64 Dota units

	public static String[] commands() {
		java.util.List<String> out = new java.util.ArrayList<>();
		out.add(String.format("forceload add %d %d %d %d", -RADIUS, -RADIUS, RADIUS - 1, RADIUS - 1)); // fill needs loaded chunks
		for (int x = -RADIUS; x < RADIUS; x += 24) // /fill is capped at 32768 blocks per call
			out.add(String.format("fill %d -64 %d %d -61 %d minecraft:barrier", x, -RADIUS, x + 23, RADIUS - 1));
		return out.toArray(new String[0]);
	}

	public static void ensure(Minecraft mc) {
		MinecraftServer server = mc.getSingleplayerServer();
		if (server == null) return; // multiplayer: the bridge does it on the server
		server.execute(() -> {
			for (String c : commands()) server.getCommands().performPrefixedCommand(server.createCommandSourceStack().withSuppressedOutput(), c);
		});
	}
}

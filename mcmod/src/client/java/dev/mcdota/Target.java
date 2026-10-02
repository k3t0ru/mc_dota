package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.entity.Entity;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

// The Dota unit under the crosshair (its stand-in is invisible) in Minecraft's boss bar: name and Dota health, red for
// enemies, green for allies, yellow "DENY" once an ally may be finished off (creeps below 50%, towers below 10%).
public final class Target {
	private record Unit(String name, int hp, int max, boolean ally) { }
	private static final Map<String, Unit> units = new ConcurrentHashMap<>(); // stand-in tag -> latest Dota state
	private static String shown = "";

	// server thread: a "hero" line from Dota
	public static void unit(String tag, String name, int hp, int max, boolean ally) { units.put(tag, new Unit(name, hp, max, ally)); }

	private static String pretty(String name) {
		return name.replace("creep_", "").replace("goodguys_", "Radiant ").replace("badguys_", "Dire ").replace("neutral_", "")
			.replace('_', ' ');
	}

	// client thread, every tick
	public static void tick(Minecraft mc) {
		MinecraftServer server = mc.getSingleplayerServer();
		if (server == null || mc.level == null) return;
		Entity look = mc.crosshairPickEntity;
		java.util.UUID id = look == null ? null : look.getUUID();
		server.execute(() -> show(server, id));
	}

	// server thread
	private static void show(MinecraftServer server, java.util.UUID id) {
		Entity e = id == null ? null : server.overworld().getEntity(id);
		Unit u = null;
		if (e != null) for (String t : e.getTags()) if (t.startsWith("dota_")) { u = units.get(t); break; }
		String state;
		if (u == null) state = "";
		else {
			boolean deny = u.ally && !u.name.contains("hero") && u.hp * 100 < u.max * (u.name.contains("tower") ? 10 : 50);
			String color = deny ? "yellow" : u.ally ? "green" : "red";
			state = String.format("{text:\"%s%s  %d / %d\"}|%s|%d|%d", deny ? "DENY  " : "", pretty(u.name), u.hp, u.max, color, u.max, Math.max(0, u.hp));
		}
		if (state.equals(shown)) return;
		if (shown.isEmpty()) Sync.run(server, "bossbar add mcdota:target \"\"", false); // already there after the first time
		shown = state;
		if (state.isEmpty()) { Sync.run(server, "bossbar set mcdota:target visible false", false); return; }
		String[] p = state.split("\\|");
		Sync.run(server, "bossbar set mcdota:target players @a", false);
		Sync.run(server, "bossbar set mcdota:target name " + p[0], false);
		Sync.run(server, "bossbar set mcdota:target color " + p[1], false);
		Sync.run(server, "bossbar set mcdota:target max " + Math.max(1, Integer.parseInt(p[2])), false);
		Sync.run(server, "bossbar set mcdota:target value " + p[3], false);
		Sync.run(server, "bossbar set mcdota:target visible true", false);
	}
}

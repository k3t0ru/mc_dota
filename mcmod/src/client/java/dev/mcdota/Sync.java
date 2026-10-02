package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.level.block.state.BlockState;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentLinkedQueue;

// Exchange with Dota through bridge.py (/mc, protocol in bridge.py) every client tick: our position and health, hits on
// Dota heroes, block changes out; Dota heroes (as invisible stand-ins to hit), damage to us and Dota's blocks in.
public final class Sync {
	private static final HttpClient HTTP = HttpClient.newHttpClient();
	private static final URI BRIDGE = URI.create("http://127.0.0.1:27100/mc");
	private static final float HERO_HP = 1024; // stand-in health; a hit shows up as the drop below this
	private static final ConcurrentLinkedQueue<String> out = new ConcurrentLinkedQueue<>();
	private static final Map<String, String> standIns = new HashMap<>(); // Dota hero id -> stand-in tag
	private static boolean busy, applying;

	// server thread: a block changed somewhere
	public static void blockChanged(BlockPos p, BlockState s) {
		if (applying || Math.abs(p.getX()) >= Arena.RADIUS || Math.abs(p.getZ()) >= Arena.RADIUS || p.getY() < -8 || p.getY() > 40) return;
		if (s.isAir()) out.add(String.format("break %d %d %d", p.getX(), p.getY(), p.getZ()));
		else out.add(String.format("set %d %d %d %s", p.getX(), p.getY(), p.getZ(), BuiltInRegistries.BLOCK.getKey(s.getBlock()).getPath()));
	}

	// client thread, every tick
	public static void tick(Minecraft mc) {
		MinecraftServer server = mc.getSingleplayerServer();
		if (busy || mc.player == null || server == null) return;
		StringBuilder body = new StringBuilder(String.format(Locale.ROOT, "me %s %.2f %.2f %.2f %.1f %.1f %.1f\n",
			mc.player.getName().getString(), mc.player.getX(), mc.player.getY(), mc.player.getZ(),
			mc.player.getYRot(), mc.player.getHealth(), mc.player.getMaxHealth()));
		for (String l; (l = out.poll()) != null; ) body.append(l).append('\n');
		busy = true;
		HTTP.sendAsync(HttpRequest.newBuilder(BRIDGE).POST(HttpRequest.BodyPublishers.ofString(body.toString())).build(),
				HttpResponse.BodyHandlers.ofString())
			.whenComplete((res, err) -> {
				busy = false;
				if (err == null && res.statusCode() == 200) server.execute(() -> apply(server, res.body()));
			});
	}

	private static void run(MinecraftServer server, String cmd) {
		try { // execute directly so failures land in the log instead of vanishing
			server.getCommands().getDispatcher().execute(cmd, server.createCommandSourceStack().withSuppressedOutput());
		} catch (Exception e) {
			org.slf4j.LoggerFactory.getLogger("mcdota").warn("command failed: {} -> {}", cmd, e.getMessage());
		}
	}

	// column x,z gets its ground at hh half blocks above y 0 (a magenta slab for a half step). Everything visible from
	// above is magenta podzol: the top, and the side wall down to the lowest neighbour (otherwise dirt pokes out where
	// Dota's ground drops). Below that it stays dirt/stone, so digging shows real blocks.
	private static void terrain(MinecraftServer server, String x, String z, int hh, int low) {
		hh = Math.max(-100, Math.min(100, hh)); // stay well inside the world (bottom is y -64)
		low = Math.max(-100, Math.min(hh, low));
		int full = Math.floorDiv(hh, 2), bottom = Math.floorDiv(low, 2) - 1; // solid up to full - 1; skin from bottom
		if (full < 0) run(server, String.format("fill %s %d %s %s -1 %s minecraft:air", x, full, z, x, z));
		run(server, String.format("fill %s %d %s %s %d %s minecraft:podzol", x, Math.min(bottom, full - 1), z, x, full - 1, z));
		if (hh % 2 != 0) run(server, String.format("setblock %s %d %s minecraft:mud_brick_slab", x, full, z));
	}

	// server thread
	private static void apply(MinecraftServer server, String body) {
		ServerLevel level = server.overworld();
		Set<String> seen = new HashSet<>();
		applying = true;
		try {
			for (String line : body.split("\n")) {
				String[] p = line.trim().split(" ");
				switch (p[0]) {
					case "hero" -> { // hero <id> <name> <x> <z> <hp> <max> [y]: any Dota unit near Steve
						String tag = "dota_" + p[1];
						String y = p.length > 7 ? p[7] : "0";
						seen.add(tag);
						boolean fresh = standIns.put(p[1], tag) == null;
						if (fresh) run(server, String.format("summon minecraft:husk %s " + y + " %s {NoAI:1b,Silent:1b,"
							+ "PersistenceRequired:1b,DeathLootTable:\"minecraft:empty\",Tags:[\"dota\",\"%s\"],attributes:[{id:\"minecraft:max_health\",base:%d}],"
							+ "Health:%df}", p[3], p[4], tag, (int) HERO_HP, (int) HERO_HP));
						// the Dota unit is what you see (magenta silhouettes came out pink and shaky: Minecraft lights mobs its own way)
						if (fresh) run(server, "effect give @e[tag=" + tag + "] minecraft:invisibility infinite 0 true");
						run(server, String.format("tp @e[tag=%s,limit=1] %s %s %s", tag, p[3], y, p[4]));
					}
					case "dmg" -> run(server, "damage @p " + p[1] + " minecraft:mob_attack");
					case "xp" -> run(server, "xp add @p " + p[1] + " points"); // Steve killed a Dota unit
					case "reset" -> { // new Dota game: flat ground again (dirt under a magenta podzol top) and nothing on it
						int r = 112; // only chunks within view distance are loaded; fill fails on anything else
						for (int x = -r; x < r; x += 4) {
							run(server, String.format("fill %d -8 %d %d -2 %d minecraft:dirt", x, -r, x + 3, r - 1));
							run(server, String.format("fill %d -1 %d %d -1 %d minecraft:podzol", x, -r, x + 3, r - 1));
							run(server, String.format("fill %d 0 %d %d 30 %d minecraft:air", x, -r, x + 3, r - 1));
						}
						run(server, "kill @e[type=minecraft:item]");
						run(server, "kill @e[tag=dota]"); // stand-ins of the previous Dota game
						standIns.clear();
					}
					case "block" -> run(server, String.format("setblock %s %s %s minecraft:%s", p[1], p[2], p[3], p[4]));
					case "unblock" -> run(server, String.format("setblock %s %s %s minecraft:air", p[1], p[2], p[3]));
					case "h" -> terrain(server, p[1], p[2], Integer.parseInt(p[3]), Integer.parseInt(p[4]));
					default -> { }
				}
			}
			// hits on stand-ins become damage to the Dota hero
			for (Entity e : level.getAllEntities()) {
				for (Map.Entry<String, String> s : standIns.entrySet()) {
					if (e instanceof LivingEntity le && le.getTags().contains(s.getValue()) && le.getHealth() < HERO_HP) {
						out.add(String.format(Locale.ROOT, "hit %s %.2f", s.getKey(), HERO_HP - le.getHealth()));
						le.setHealth(HERO_HP);
					}
				}
			}
			// heroes Dota no longer reports (dead, left) lose their stand-in
			standIns.entrySet().removeIf(s -> {
				if (seen.contains(s.getValue())) return false;
				run(server, "kill @e[tag=" + s.getValue() + "]");
				return true;
			});
		} finally {
			applying = false;
		}
	}
}

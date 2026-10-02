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
		if (applying || Math.abs(p.getX()) >= Arena.RADIUS || Math.abs(p.getZ()) >= Arena.RADIUS || p.getY() < -60 || p.getY() > -40) return;
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

	// server thread
	private static void apply(MinecraftServer server, String body) {
		ServerLevel level = server.overworld();
		Set<String> seen = new HashSet<>();
		applying = true;
		try {
			for (String line : body.split("\n")) {
				String[] p = line.trim().split(" ");
				switch (p[0]) {
					case "hero" -> { // hero <id> <name> <x> <z> <hp> <max>
						String tag = "dota_" + p[1];
						seen.add(tag);
						if (standIns.put(p[1], tag) == null) run(server, String.format("summon minecraft:husk %s -60 %s {NoAI:1b,Silent:1b,"
							+ "PersistenceRequired:1b,Tags:[\"dota\",\"%s\"],CustomName:\"%s\",attributes:[{id:\"minecraft:max_health\",base:%d}],"
							+ "Health:%df,active_effects:[{id:\"minecraft:invisibility\",duration:-1,show_particles:0b}]}", p[3], p[4], tag, p[2], (int) HERO_HP, (int) HERO_HP));
						run(server, String.format("tp @e[tag=%s,limit=1] %s -60 %s", tag, p[3], p[4]));
					}
					case "dmg" -> run(server, "damage @p " + p[1] + " minecraft:mob_attack");
					case "reset" -> { // new Dota game: wipe every block above the barrier floor in the arena
						int r = 112; // only chunks within view distance are loaded; fill fails on anything else
						for (int x = -r; x < r; x += 4)
							run(server, String.format("fill %d -60 %d %d -40 %d minecraft:air", x, -r, x + 3, r - 1));
						run(server, "kill @e[type=minecraft:item]");
					}
					case "block" -> run(server, String.format("setblock %s %s %s minecraft:%s", p[1], p[2], p[3], p[4]));
					case "unblock" -> run(server, String.format("setblock %s %s %s minecraft:air", p[1], p[2], p[3]));
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

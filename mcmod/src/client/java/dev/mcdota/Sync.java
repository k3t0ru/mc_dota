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
		if (applying || p.getY() < -60 || p.getY() > 60) return; // Dota decides what to draw / collide by height
		if (s.isAir()) out.add(String.format("break %d %d %d", p.getX(), p.getY(), p.getZ()));
		else out.add(String.format("set %d %d %d %s", p.getX(), p.getY(), p.getZ(), BuiltInRegistries.BLOCK.getKey(s.getBlock()).getPath()));
	}

	// any thread: a line for Dota
	public static void out(String line) { out.add(line); }

	private static String lastCrack = "";

	// client thread: mining progress on a block (stage -1 = stopped)
	public static void crack(BlockPos p, int stage) {
		String line = String.format("crack %d %d %d %d", p.getX(), p.getY(), p.getZ(), stage);
		if (!line.equals(lastCrack)) out.add(line);
		lastCrack = line;
	}

	// client thread, every tick
	public static void tick(Minecraft mc) {
		Target.tick(mc);
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

	static boolean run(MinecraftServer server, String cmd) { return run(server, cmd, true); }

	static boolean run(MinecraftServer server, String cmd, boolean log) {
		try { // execute directly so failures land in the log instead of vanishing
			server.getCommands().getDispatcher().execute(cmd, server.createCommandSourceStack().withSuppressedOutput());
			return true;
		} catch (Exception e) {
			if (log) org.slf4j.LoggerFactory.getLogger("mcdota").warn("command failed: {} -> {}", cmd, e.getMessage());
			return false;
		}
	}

	// column x,z gets its ground at hh half blocks above y 0 (a magenta slab for a half step). Flat ground keeps its podzol
	// top (only the TOP face is magenta, so a dug hole shows real dirt walls). Where Dota's ground drops, the exposed side
	// wall down to the lowest neighbour is mud bricks, magenta on every face, so Dota's slope shows through it.
	private static void terrain(MinecraftServer server, String x, String z, int hh, int low) {
		hh = Math.max(-100, Math.min(100, hh)); // stay well inside the world (bottom is y -64)
		// the superflat underneath (bedrock, stone, dirt) if this column was void before (no bedrock at the bottom)
		if (server.overworld().getBlockState(new BlockPos(Integer.parseInt(x), -64, Integer.parseInt(z))).isAir()) {
			run(server, String.format("fill %s -64 %s %s -64 %s minecraft:bedrock", x, z, x, z), false);
			run(server, String.format("fill %s -63 %s %s -5 %s minecraft:stone", x, z, x, z), false);
			run(server, String.format("fill %s -4 %s %s -2 %s minecraft:dirt", x, z, x, z), false);
		}
		low = Math.max(-100, Math.min(hh, low));
		int full = Math.floorDiv(hh, 2), bottom = Math.floorDiv(low, 2) - 1; // solid up to full - 1; skin from bottom
		Hybrid.setSurface(Integer.parseInt(x), Integer.parseInt(z), full);
		if (full < 0) run(server, String.format("fill %s %d %s %s -1 %s minecraft:air", x, full, z, x, z), false);
		boolean exposed = low < hh || full > 0; // a side wall shows (raised column or a lower neighbour)
		run(server, String.format("fill %s %d %s %s %d %s minecraft:%s", x, Math.min(bottom, full - 1), z, x, full - 1, z,
			exposed ? "mud_bricks" : "podzol"), false);
		if (hh % 2 != 0) run(server, String.format("setblock %s %d %s minecraft:mud_brick_slab", x, full, z), false);
	}

	// Minecraft can only change loaded chunks, and Dota's map is far bigger than the view distance: columns of unloaded
	// chunks wait here and are built the moment their chunk loads (ServerChunkEvents in McDotaClient)
	// Ready builds run at most BUDGET per server tick: a whole Dota map at once froze Minecraft for seconds.
	// A queued column whose chunk unloaded again before its turn (the player walked on; the backlog can be thousands)
	// goes back to waiting: running it then failed with "That position is not loaded" and the column was lost for good,
	// which is why the void past the map edge never appeared.
	private record Build(int x, int z, Runnable run) { }
	private static final Map<Long, java.util.List<Build>> pending = new HashMap<>();
	// ready builds grouped by chunk; the chunks nearest the player go first (the real Dota map queues tens of thousands
	// of columns, and first-come-first-served left the ground under the player unbuilt for minutes)
	private static final Map<Long, java.util.ArrayDeque<Build>> ready = new HashMap<>();
	private static int readyCount;
	private static final int BUDGET = 400;
	private static long lastReport;

	private static void column(MinecraftServer server, int x, int z, Runnable build) {
		Build b = new Build(x, z, build);
		if (server.overworld().hasChunk(x >> 4, z >> 4)) ready(b);
		else wait(b);
	}

	private static void ready(Build b) {
		ready.computeIfAbsent(net.minecraft.world.level.ChunkPos.asLong(b.x >> 4, b.z >> 4), k -> new java.util.ArrayDeque<>()).add(b);
		readyCount++;
	}

	private static void wait(Build b) {
		pending.computeIfAbsent(net.minecraft.world.level.ChunkPos.asLong(b.x >> 4, b.z >> 4), k -> new java.util.ArrayList<>()).add(b);
	}

	// server thread: a chunk just loaded
	public static void chunkLoaded(MinecraftServer server, int cx, int cz) {
		java.util.List<Build> builds = pending.remove(net.minecraft.world.level.ChunkPos.asLong(cx, cz));
		if (builds != null) builds.forEach(Sync::ready);
	}

	// server thread, every tick
	public static void buildSome(MinecraftServer server) {
		if (System.currentTimeMillis() - lastReport > 10000 && (readyCount > 0 || !pending.isEmpty())) {
			lastReport = System.currentTimeMillis();
			org.slf4j.LoggerFactory.getLogger("mcdota").info("terrain: {} columns ready, {} chunks waiting to load", readyCount, pending.size());
		}
		if (readyCount == 0) return;
		var players = server.getPlayerList().getPlayers();
		int px = players.isEmpty() ? 0 : players.get(0).getBlockX() >> 4, pz = players.isEmpty() ? 0 : players.get(0).getBlockZ() >> 4;
		java.util.List<Long> order = new java.util.ArrayList<>(ready.keySet());
		order.sort(java.util.Comparator.comparingLong(k -> {
			long dx = net.minecraft.world.level.ChunkPos.getX(k) - px, dz = net.minecraft.world.level.ChunkPos.getZ(k) - pz;
			return dx * dx + dz * dz;
		}));
		applying = true;
		try {
			int done = 0;
			for (Long k : order) {
				java.util.ArrayDeque<Build> q = ready.get(k);
				while (done < BUDGET && !q.isEmpty()) {
					Build b = q.poll();
					readyCount--;
					done++;
					if (server.overworld().hasChunk(b.x >> 4, b.z >> 4)) b.run.run();
					else wait(b);
				}
				if (q.isEmpty()) ready.remove(k);
				if (done >= BUDGET) break;
			}
		} finally {
			applying = false;
		}
	}

	// stand-in size for big Dota units (Minecraft's scale attribute), so swords and arrows can reach a tower
	private static double scale(String name) {
		if (name.contains("tower")) return 2.5;
		if (name.contains("rax") || name.contains("fort") || name.contains("filler")) return 3;
		if (name.contains("roshan")) return 2;
		return 1;
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
						Target.unit(tag, p[2], Integer.parseInt(p[5]), Integer.parseInt(p[6]), p.length > 8 && p[8].equals("1"));
						boolean fresh = standIns.put(p[1], tag) == null;
						if (fresh) run(server, String.format(Locale.ROOT, "summon minecraft:husk %s " + y + " %s {NoAI:1b,Silent:1b,"
							+ "PersistenceRequired:1b,NoGravity:1b,DeathLootTable:\"minecraft:empty\",Tags:[\"dota\",\"%s\"],attributes:[{id:\"minecraft:max_health\",base:%d},"
							+ "{id:\"minecraft:scale\",base:%.1f}],Health:%df}", p[3], p[4], tag, (int) HERO_HP, scale(p[2]), (int) HERO_HP));
						// the Dota unit is what you see (magenta silhouettes came out pink and shaky: Minecraft lights mobs its own way)
						if (fresh) run(server, "effect give @e[tag=" + tag + "] minecraft:invisibility infinite 0 true");
						run(server, String.format("tp @e[tag=%s,limit=1] %s %s %s", tag, p[3], y, p[4]));
					}
					// from the attacker's stand-in, so a raised shield facing it blocks the hit (no stand-in: plain damage)
					case "dmg" -> Progress.damage(server, Float.parseFloat(p[1]), p.length > 2 ? p[2] : "-1");
					case "loot" -> Progress.loot(server, p);
					case "dead" -> Progress.deadFor(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]));
					case "respawn" -> Progress.respawn(server);
					case "lvl" -> Progress.level(server, Integer.parseInt(p[1]));
					case "delay" -> Overlay.dotaDelay(Integer.parseInt(p[1]));
					case "trader" -> Progress.trader(Double.parseDouble(p[1]), Double.parseDouble(p[2]), p[3]);
					case "xp" -> run(server, "xp add @p " + p[1] + " points"); // Steve killed a Dota unit
					case "reset" -> { // new Dota game: flat ground again (dirt under a magenta podzol top) and nothing on it
						int r = 112; // only chunks within view distance are loaded; fill fails on anything else
						for (int x = -r; x < r; x += 4) {
							run(server, String.format("fill %d -8 %d %d -2 %d minecraft:dirt", x, -r, x + 3, r - 1));
							run(server, String.format("fill %d -1 %d %d -1 %d minecraft:podzol", x, -r, x + 3, r - 1));
							run(server, String.format("fill %d 0 %d %d 30 %d minecraft:air", x, -r, x + 3, r - 1));
						}
						run(server, "kill @e[type=minecraft:item]");
						Progress.newMatch(server);
						run(server, "kill @e[tag=dota]"); // stand-ins of the previous Dota game
						standIns.clear();
						ready.clear(); // terrain of the previous Dota game
						readyCount = 0;
						pending.clear();
					}
					case "block" -> run(server, String.format("setblock %s %s %s minecraft:%s", p[1], p[2], p[3], p[4]));
					case "unblock" -> run(server, String.format("setblock %s %s %s minecraft:air", p[1], p[2], p[3]));
					case "void" -> column(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]), () ->
						run(server, String.format("fill %s -64 %s %s 30 %s minecraft:air", p[1], p[2], p[1], p[2]), false)); // fall and die
					case "border" -> { run(server, "worldborder center 0.5 0.5"); run(server, "worldborder set " + p[1]); }
					case "h" -> column(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]), () ->
						terrain(server, p[1], p[2], Integer.parseInt(p[3]), Integer.parseInt(p[4])));
					default -> { }
				}
			}
			// hits on stand-ins become damage to the Dota hero
			for (Entity e : level.getAllEntities()) {
				for (Map.Entry<String, String> s : standIns.entrySet()) {
					if (e instanceof LivingEntity le && le.getTags().contains(s.getValue()) && le.getHealth() < HERO_HP) {
						// only a player's hit counts: void, suffocation inside blocks etc. must not hurt the Dota unit.
						// direct = the swing's own target or a projectile (a sweep's splash isn't: it never touches allies)
						var src = le.getLastDamageSource();
						if (src != null && src.getEntity() instanceof net.minecraft.world.entity.player.Player pl) {
							boolean direct = src.getDirectEntity() != pl || pl.getLastHurtMob() == le;
							out.add(String.format(Locale.ROOT, "hit %s %.2f %d", s.getKey(), HERO_HP - le.getHealth(), direct ? 1 : 0));
						}
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

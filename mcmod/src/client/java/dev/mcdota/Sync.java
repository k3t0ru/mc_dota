package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.item.ItemStack;
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
	private static final Map<String, Long> lastSeen = new HashMap<>(); // Dota hero id -> last time Dota listed it

	// server thread: remove tagged entities without a death (/kill played the death puff and the husks dropped what
	// they had picked up, right in front of the player)
	public static void discard(MinecraftServer server, String tag) {
		java.util.List<Entity> gone = new java.util.ArrayList<>();
		for (Entity e : server.overworld().getAllEntities()) if (e.getTags().contains(tag)) gone.add(e);
		gone.forEach(Entity::discard);
	}
	private static boolean busy, applying;

	// server thread: a block changed somewhere
	public static void blockChanged(BlockPos p, BlockState s) {
		if (applying || p.getY() < -60 || p.getY() > 60) return; // Dota decides what to draw / collide by height
		// under the ground it's the terrain changing by itself (the superflat's grass under the built ground turns to
		// dirt): Dota drew those as dirt blocks hanging in the air wherever its ground is lower
		int surface = Hybrid.surfaceAt(p.getX(), p.getZ());
		if (p.getY() < surface) return;
		if (Hybrid.slabAt(p.getX(), p.getZ()) && halfStep(p, s, surface)) return;
		if (s.isAir() || !Hybrid.drawnByDota(s, p)) out.add(String.format("break %d %d %d", p.getX(), p.getY(), p.getZ()));
		else {
			// its state too ("axis=x,facing=north,..."): Dota picks the blockstate variant (MC:Variant) to turn its model
			StringBuilder state = new StringBuilder();
			for (var e : s.getValues().entrySet())
				state.append(state.length() > 0 ? "," : "").append(e.getKey().getName()).append('=').append(e.getValue().toString().toLowerCase(Locale.ROOT));
			out.add(String.format("set %d %d %d %s %d %s", p.getX(), p.getY(), p.getZ(), BuiltInRegistries.BLOCK.getKey(s.getBlock()).getPath(),
				s.blocksMotion() ? 1 : 0, state.length() > 0 ? state : "-")); // 0: fire, torches, flowers: drawn, units don't bump into them
		}
	}

	// On a half step (the terrain's top is a slab) a block placed on it stood half a block above Dota's ground, a gap
	// under it: Dota drew it floating. It takes the slab's place instead (half sunk into Dota's ground, like any block on
	// a slope in Minecraft), and the slab comes back when the block there is broken. (Next tick: not inside setBlock.)
	private static boolean halfStep(BlockPos p, BlockState s, int surface) {
		var server = Minecraft.getInstance().getSingleplayerServer();
		if (server == null) return false;
		var level = server.overworld();
		BlockPos below = new BlockPos(p.getX(), surface, p.getZ());
		if (p.getY() == surface + 1 && !s.isAir() && s.isCollisionShapeFullBlock(level, p) && level.getBlockState(below).is(net.minecraft.world.level.block.Blocks.MUD_BRICK_SLAB)) {
			server.execute(() -> {
				if (level.getBlockState(p) != s || !level.getBlockState(below).is(net.minecraft.world.level.block.Blocks.MUD_BRICK_SLAB)) return;
				level.setBlockAndUpdate(below, s);
				level.setBlockAndUpdate(p, net.minecraft.world.level.block.Blocks.AIR.defaultBlockState());
			});
			return true; // (the move sends Dota both changes)
		}
		if (p.getY() == surface && s.isAir()) // a block in a slab's place broken: the half step again
			server.execute(() -> {
				if (!level.getBlockState(below).isAir()) return;
				applying = true;
				try { level.setBlockAndUpdate(below, net.minecraft.world.level.block.Blocks.MUD_BRICK_SLAB.defaultBlockState()); }
				finally { applying = false; }
			});
		return false;
	}

	// A block put onto a half step's top goes straight into the slab's place (what halfStep does afterwards anyway), so
	// it also works with Steve standing on the step: jumping and placing under himself there was impossible (the space
	// above the slab is his), now the block takes the slab's place and lifts him onto it.
	public static net.minecraft.world.InteractionResult placeOnStep(net.minecraft.world.entity.player.Player player,
			net.minecraft.world.level.Level level, net.minecraft.world.InteractionHand hand, net.minecraft.world.phys.BlockHitResult hit) {
		BlockPos pos = hit.getBlockPos();
		var pass = net.minecraft.world.InteractionResult.PASS;
		if (player.getItemInHand(hand).is(net.minecraft.world.item.Items.FLINT_AND_STEEL) && !level.isClientSide()) out("light");
		// clicked on the side of a block: the cell beside it, if that's a terrain slab (a half step), is where it goes
		if (hit.getDirection().getAxis().isHorizontal()) {
			BlockPos t = pos.relative(hit.getDirection());
			if (level.getBlockState(t).is(net.minecraft.world.level.block.Blocks.MUD_BRICK_SLAB) && Hybrid.slabAt(t.getX(), t.getZ())
				&& t.getY() == Hybrid.surfaceAt(t.getX(), t.getZ()))
				pos = t; // as if its top was clicked (below: the block replaces the slab)
			else return pass;
		} else if (hit.getDirection() != net.minecraft.core.Direction.UP || player.isSpectator()
			|| !level.getBlockState(pos).is(net.minecraft.world.level.block.Blocks.MUD_BRICK_SLAB)
			|| !Hybrid.slabAt(pos.getX(), pos.getZ()) || pos.getY() != Hybrid.surfaceAt(pos.getX(), pos.getZ())) return pass;
		ItemStack st = player.getItemInHand(hand);
		if (!(st.getItem() instanceof net.minecraft.world.item.BlockItem bi)) return pass;
		BlockState s = bi.getBlock().defaultBlockState();
		if (!s.isCollisionShapeFullBlock(level, pos)) return pass;
		if (!level.isClientSide()) {
			level.setBlockAndUpdate(pos, s);
			level.playSound(null, pos, s.getSoundType().getPlaceSound(), net.minecraft.sounds.SoundSource.BLOCKS, 1, 0.8f);
			if (!player.getAbilities().instabuild) st.shrink(1);
			if (player.getBoundingBox().intersects(new net.minecraft.world.phys.AABB(pos)) || player.getY() < pos.getY() + 1
				&& player.getBoundingBox().intersects(new net.minecraft.world.phys.AABB(pos.above())))
				player.teleportTo(player.getX(), pos.getY() + 1, player.getZ());
		}
		return net.minecraft.world.InteractionResult.SUCCESS;
	}

	// blocks Dota built (the market, the fountain's barriers): explosions leave them alone (ExplosionMixin)
	public static final Set<BlockPos> protectedBlocks = java.util.concurrent.ConcurrentHashMap.newKeySet();

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
		// the superflat underneath (bedrock, then magenta mud bricks: an unbuilt column never shows) if this column was void before
		if (server.overworld().getBlockState(new BlockPos(Integer.parseInt(x), -64, Integer.parseInt(z))).isAir()) {
			run(server, String.format("fill %s -64 %s %s -64 %s minecraft:bedrock", x, z, x, z), false);
			run(server, String.format("fill %s -63 %s %s -2 %s minecraft:mud_bricks", x, z, x, z), false);
		}
		low = Math.max(-100, Math.min(hh, low));
		int full = Math.floorDiv(hh, 2), bottom = Math.floorDiv(low, 2) - 1; // solid up to full - 1; skin from bottom
		Hybrid.setSurface(Integer.parseInt(x), Integer.parseInt(z), full);
		Hybrid.setSlab(Integer.parseInt(x), Integer.parseInt(z), hh % 2 != 0);
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
	// and at most this long per server tick: each column is several commands, and 400 of them stalled the server for
	// 100+ ms whenever the player walked into new chunks on the big map (the picture twitched while walking)
	private static final long BUDGET_NANOS = 6_000_000;
	private static long lastReport;
	private static int sweep;

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
		if (System.currentTimeMillis() - lastReport > 10000) {
			lastReport = System.currentTimeMillis();
			org.slf4j.LoggerFactory.getLogger("mcdota").info("terrain: {} columns ready, {} chunks waiting to load; server tick {} ms",
				readyCount, pending.size(), String.format(Locale.ROOT, "%.1f", server.getCurrentSmoothedTickTime()));
		}
		// chunks whose load event never came (they were already loaded, or loaded part-way when their columns arrived):
		// the far half of the map stayed unbuilt, Minecraft's flat floor stood as an invisible wall above Dota's ground
		if (++sweep % 40 == 0 && !pending.isEmpty()) {
			var level = server.overworld();
			for (Long k : new java.util.ArrayList<>(pending.keySet()))
				if (level.hasChunk(net.minecraft.world.level.ChunkPos.getX(k), net.minecraft.world.level.ChunkPos.getZ(k)))
					pending.remove(k).forEach(Sync::ready);
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
			long until = System.nanoTime() + BUDGET_NANOS;
			for (Long k : order) {
				java.util.ArrayDeque<Build> q = ready.get(k);
				while (done < BUDGET && !q.isEmpty() && System.nanoTime() < until) {
					Build b = q.poll();
					readyCount--;
					done++;
					if (server.overworld().hasChunk(b.x >> 4, b.z >> 4)) b.run.run();
					else wait(b);
				}
				if (q.isEmpty()) ready.remove(k);
				if (done >= BUDGET || System.nanoTime() >= until) break;
			}
		} finally {
			applying = false;
		}
	}

	// fire, lava and the like (no attacker): on Dota's map only the player can have put them there
	private static boolean burning(net.minecraft.world.damagesource.DamageSource src) {
		String id = src.type().msgId();
		return id.equals("inFire") || id.equals("onFire") || id.equals("lava") || id.equals("hotFloor") || id.equals("campfire") || id.equals("cactus") || id.equals("sweetBerryBush");
	}

	// potions' harm: instant damage, poison
	private static boolean magic(net.minecraft.world.damagesource.DamageSource src) {
		String id = src.type().msgId();
		return id.equals("magic") || id.equals("indirectMagic") || id.equals("wither");
	}

	// Minecraft's fire (1 HP per half second) barely scratches Dota's creeps: 3x, ~55 Dota damage a second
	private static float fireMult(net.minecraft.world.damagesource.DamageSource src) {
		String id = src.type().msgId();
		return id.equals("inFire") || id.equals("onFire") || id.equals("campfire") ? 3 : 1;
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
						lastSeen.put(p[1], System.currentTimeMillis());
						boolean fresh = standIns.put(p[1], tag) == null;
						if (fresh) run(server, String.format(Locale.ROOT, "summon minecraft:pillager %s " + y + " %s {NoAI:1b,Silent:1b,"
							+ "PersistenceRequired:1b,NoGravity:1b,DeathLootTable:\"minecraft:empty\",Tags:[\"dota\",\"%s\"],attributes:[{id:\"minecraft:max_health\",base:%d},"
							+ "{id:\"minecraft:scale\",base:%.1f}],Health:%df,"
							// invisible from the first tick (an effect given afterwards let a zombie flash for a moment): the Dota unit
							// is what you see (magenta silhouettes came out pink and shaky: Minecraft lights mobs its own way)
							+ "active_effects:[{id:\"minecraft:invisibility\",duration:-1,amplifier:0b,show_particles:0b}]}",
							p[3], p[4], tag, (int) HERO_HP, scale(p[2]), (int) HERO_HP));
						if (fresh) run(server, String.format("item replace entity @e[tag=%s,limit=1] weapon.mainhand with minecraft:air", tag), false); // (its crossbow)
						run(server, String.format("tp @e[tag=%s,limit=1] %s %s %s", tag, p[3], y, p[4]));
					}
					// from the attacker's stand-in, so a raised shield facing it blocks the hit (no stand-in: plain damage)
					case "dmg" -> Progress.damage(server, Float.parseFloat(p[1]), p.length > 2 ? p[2] : "-1");
					case "loot" -> Progress.loot(server, p);
					case "dead" -> Progress.deadFor(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]));
					case "respawn" -> Progress.respawn(server);
					case "time" -> ClockHud.set(Integer.parseInt(p[1]), p[2].equals("1"));
					case "fountain" -> Progress.fountain(server);
					case "spawnat" -> Progress.spawnAt(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]), Integer.parseInt(p[3]));
					case "lvl" -> Progress.level(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]), Integer.parseInt(p[3]));
					case "delay" -> Overlay.dotaDelay(Integer.parseInt(p[1]));
					case "boss" -> Progress.boss(server, p);
					case "fx" -> Progress.hitFx(server, p[1], p[2], p.length > 3 ? Integer.parseInt(p[3]) : 0);
					case "mcfov" -> { // Dota's measured vertical field of view: Minecraft's matches it
						int fov = (int) Math.round(Double.parseDouble(p[1]));
						Minecraft mc = Minecraft.getInstance();
						mc.execute(() -> { if (mc.options.fov().get() != fov) mc.options.fov().set(Math.max(30, Math.min(110, fov))); });
					}
					case "cmd" -> { // testing (bridge /cmd): like a player's action, so placed blocks reach Dota
						applying = false;
						run(server, line.trim().substring(4));
						applying = true;
					}
					case "trader" -> Progress.trader(Double.parseDouble(p[1]), Double.parseDouble(p[2]), p[3], p.length > 4 ? Double.parseDouble(p[4]) : Double.NaN);
					case "xp" -> run(server, "xp add @p " + p[1] + " points"); // Steve killed a Dota unit
					case "reset" -> { // new Dota game: flat ground again (dirt under a magenta podzol top) and nothing on it
						int r = 112; // only chunks within view distance are loaded; fill fails on anything else
						for (int x = -r; x < r; x += 4) {
							run(server, String.format("fill %d -8 %d %d -2 %d minecraft:mud_bricks", x, -r, x + 3, r - 1));
							run(server, String.format("fill %d -1 %d %d -1 %d minecraft:podzol", x, -r, x + 3, r - 1));
							run(server, String.format("fill %d 0 %d %d 30 %d minecraft:air", x, -r, x + 3, r - 1));
						}
						run(server, "kill @e[type=minecraft:item]");
						Progress.newMatch(server);
						discard(server, "dota"); // stand-ins of the previous Dota game
						standIns.clear();
						ready.clear(); // terrain of the previous Dota game
						readyCount = 0;
						pending.clear();
					}
					// queued behind its column's terrain build (which would otherwise clear or overwrite it later)
					case "block" -> { protectedBlocks.add(new BlockPos(Integer.parseInt(p[1]), Integer.parseInt(p[2]), Integer.parseInt(p[3])));
						column(server, Integer.parseInt(p[1]), Integer.parseInt(p[3]), () ->
						run(server, String.format("setblock %s %s %s minecraft:%s", p[1], p[2], p[3], p[4]))); }
					case "unblock" -> run(server, String.format("setblock %s %s %s minecraft:air", p[1], p[2], p[3]));
					case "sign" -> { // "sign x y z <block[state]> line|line|...": the stalls' signs (after their blocks: same queue)
						protectedBlocks.add(new BlockPos(Integer.parseInt(p[1]), Integer.parseInt(p[2]), Integer.parseInt(p[3])));
						String[] lines = line.split(" ", 6).length > 5 ? line.split(" ", 6)[5].split("\\|") : new String[0];
						StringBuilder msgs = new StringBuilder();
						for (int i = 0; i < 4; i++)
							msgs.append(i > 0 ? "," : "").append('"').append(i < lines.length ? lines[i].replace("\\", "").replace("\"", "") : "").append('"');
						String cmd = String.format("setblock %s %s %s minecraft:%s{is_waxed:1b,front_text:{messages:[%s]}}", p[1], p[2], p[3], p[4], msgs);
						column(server, Integer.parseInt(p[1]), Integer.parseInt(p[3]), () -> run(server, cmd));
					}
					case "void" -> column(server, Integer.parseInt(p[1]), Integer.parseInt(p[2]), () ->
						run(server, String.format("fill %s -64 %s %s 30 %s minecraft:air", p[1], p[2], p[1], p[2]), false)); // fall and die
					case "border" -> { // "border <size> [<centre x> <centre z>]": the map's box
						run(server, p.length > 3 ? "worldborder center " + (Integer.parseInt(p[2]) + 0.5) + " " + (Integer.parseInt(p[3]) + 0.5) : "worldborder center 0.5 0.5");
						run(server, "worldborder set " + p[1]);
					}
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
						// the kind of hit for Dota: fire (burning: cooked loot), boom (TNT: magic damage, scaled), magic (potions)
						String kind = src == null ? "" : src.is(net.minecraft.tags.DamageTypeTags.IS_EXPLOSION) ? "boom"
							: magic(src) ? "magic" : burning(src) ? "fire" : "-";
						if (src != null && src.getEntity() == null && (burning(src) || magic(src))) // fire/lava/poison a player set: splash damage
							out.add(String.format(Locale.ROOT, "hit %s %.2f 0 %s", s.getKey(), (HERO_HP - le.getHealth()) * fireMult(src), kind));
						if (src != null && src.getEntity() instanceof net.minecraft.world.entity.player.Player pl
							&& !(src.getDirectEntity() == pl && pl.getLastHurtMob() != le)) { // that's Minecraft's own sweep: Lua sweeps (swing)
							boolean projectile = src.getDirectEntity() instanceof net.minecraft.world.entity.projectile.Projectile; // TNT: splash
							boolean melee = src.getDirectEntity() == pl && pl.getLastHurtMob() == le;
							// the swing's own target: AttackMixin's "swing" hits what Dota highlights instead
							if (!melee)
								out.add(String.format(Locale.ROOT, "hit %s %.2f %d %s", s.getKey(), HERO_HP - le.getHealth(), projectile ? 1 : 0, kind));
						}
						le.setHealth(HERO_HP);
					}
					// splash potions' lasting effects on a stand-in: Dota applies them (slowness, weakness)
					if (e instanceof LivingEntity le && le.getTags().contains(s.getValue())) {
						for (var ef : java.util.List.of(net.minecraft.world.effect.MobEffects.SLOWNESS, net.minecraft.world.effect.MobEffects.WEAKNESS)) {
							var inst = le.getEffect(ef);
							if (inst == null) continue;
							out.add(String.format(Locale.ROOT, "eff %s %s %d %.1f", s.getKey(), ef == net.minecraft.world.effect.MobEffects.SLOWNESS ? "slow" : "weak",
								inst.getAmplifier() + 1, inst.getDuration() / 20f));
							le.removeEffect(ef);
						}
					}
				}
			}
			// heroes Dota no longer reports (dead, left) lose their stand-in
			// (after a second unlisted: answers can arrive out of order, and a stand-in removed and summoned again flickered)
			long now = System.currentTimeMillis();
			standIns.entrySet().removeIf(s -> {
				if (seen.contains(s.getValue()) || now - lastSeen.getOrDefault(s.getKey(), 0L) < 1000) return false;
				lastSeen.remove(s.getKey());
				discard(server, s.getValue());
				return true;
			});
		} finally {
			applying = false;
		}
	}
}

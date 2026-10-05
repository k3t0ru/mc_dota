package dev.mcdota;

import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.network.chat.Component;
import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.entity.projectile.arrow.AbstractArrow;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;
import net.minecraft.world.level.levelgen.Heightmap;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

// Steve's progression inside one Dota match. Dota has nothing to mine, so everything comes from fighting: Steve's kills
// drop emeralds (by the unit's gold bounty, MC:LootFor in Lua), food and, from neutrals, crafting materials; his Dota
// level (hero XP from those kills) is his max health; Minecraft XP stays for enchanting.
// Crafting is the core: villagers sell MATERIALS, like Dota's shops sell components, and gear is crafted as usual.
// Basic materials sit by the spawn; diamonds, netherite and its upgrade template, elytra are at the "secret shop" (Dota's
// own shop on this map, away from the spawn). The toolsmith repairs the held item (sneak + right click) for a third of
// its material cost. Dying costs emeralds and waits for Dota's respawn timer. Every new match starts over.
// The traders are DRAWN by Dota (blocky villager models, tools/gen_villager.py) at spots Dota picks ("trader x z prof");
// Minecraft only keeps an invisible villager there to open the trading screen (anything Minecraft draws lags Dota's world).
public final class Progress {
	private static final int TEST_EMERALDS = 192; // testing: 3 stacks at the start of every match (0 for real games)
	private static final int HP_PER_LEVEL = 1; // half a heart per Dota level: level 30 = 49 hp (Dota's DOTA_TO_MC: 1 hp = 50 Dota damage)
	private static final double SWEEP = 0.8; // sweep hits deal this share of the main hit (vanilla: 1 damage flat)
	private static final int ARROW_TICKS = 300; // Steve's arrows: gone after 15 s
	private static int level = 1;
	private static boolean dead;

	static void say(MinecraftServer server, String text, String color) {
		Sync.run(server, "title @p actionbar {text:\"" + text + "\",color:\"" + color + "\"}");
	}

	// the player's own attributes: also after a respawn, which resets them
	public static void attributes(MinecraftServer server) {
		// (a heart every two levels: whole hearts only, an odd max showed as a half heart that never filled)
		Sync.run(server, "attribute @p minecraft:max_health base set " + (20 + (level - 1) / 2 * 2 * HP_PER_LEVEL + 4 * shards));
		Sync.run(server, "attribute @p minecraft:sweeping_damage_ratio base set " + SWEEP);
		Sync.run(server, "attribute @p minecraft:knockback_resistance base set 1"); // Dota hits hurt but don't shove the camera
	}

	// server thread: new Dota match
	public static void newMatch(MinecraftServer server) {
		level = 1;
		shards = 0;
		dead = false;
		placed = false;
		for (String c : new String[] {
			// a session that ended while dead left the "frozen" state in the player's save: no walking, no jumping
			"gamemode survival @p", "attribute @p minecraft:movement_speed base set 0.1", "attribute @p minecraft:jump_strength base set 0.42",
			"title @p clear", "clear @p", "xp set @p 0 levels", "xp set @p 0 points",
			"effect clear @p", "effect give @p minecraft:instant_health 1 10 true", "effect give @p minecraft:saturation 1 20 true",
			"give @p minecraft:wooden_sword", "give @p minecraft:wooden_pickaxe", "give @p minecraft:crafting_table",
			"give @p minecraft:bread 8", "give @p minecraft:oak_planks 16",
			"give @p minecraft:emerald " + TEST_EMERALDS,
		}) Sync.run(server, c);
		Sync.discard(server, "mcdota_trader"); // re-summoned with fresh trades by tick()
		attributes(server);
		xp = 0;
		need = 240;
		xpBar(server);
	}

	// server thread: Steve killed a Dota unit: "loot <emeralds> [<item> <n>]..."
	// "loot <emeralds> <gold> [<item> <n>]...": Dota keeps the gold left over below an emerald for the next kill
	public static void loot(MinecraftServer server, String[] p) {
		int emeralds = Integer.parseInt(p[1]);
		if (emeralds > 0) Sync.run(server, "give @p minecraft:emerald " + emeralds);
		java.util.List<String> got = new ArrayList<>(); // the emeralds rise over the corpse in Dota (MC:Popup); the rest here
		for (int i = 3; i + 1 < p.length; i += 2) {
			int n = Integer.parseInt(p[i + 1]);
			if (n <= 0 || p[i].equals("none")) continue;
			Sync.run(server, "give @p minecraft:" + p[i] + " " + n);
			// the item's own name in the game's language
			String key = BuiltInRegistries.ITEM.getValue(net.minecraft.resources.Identifier.withDefaultNamespace(p[i])).getDescriptionId();
			got.add((got.isEmpty() ? "" : "{text:\", \"},") + "{text:\"+" + n + " \"},{translate:\"" + key + "\"}");
		}
		if (!got.isEmpty()) Sync.run(server, "title @p actionbar [{text:\"\",color:\"green\"}," + String.join(",", got) + "]");
	}

	// server thread: Steve's Dota level changed
	// Minecraft's XP bar IS Steve's level: the number is his level, the bar the way to the next one, earned by kills
	// (the XP Dota would give his hero, by Dota's table, then ever steeper past 30: no cap). Kept on death; enchanting and
	// the anvil need the level but don't spend it (tick() puts it back): it's his level, not a currency.
	private static int xp, need = 240;

	public static void level(MinecraftServer server, int lvl, int xp, int need) {
		Progress.xp = xp;
		Progress.need = need;
		if (lvl != level) {
			level = lvl;
			attributes(server);
		}
		xpBar(server);
	}

	private static void xpBar(MinecraftServer server) {
		int points = level >= 30 ? 9 * level - 158 : level >= 15 ? 5 * level - 38 : 2 * level + 7; // Minecraft's, for the next level
		Sync.run(server, "xp set @p " + level + " levels", false);
		Sync.run(server, "xp set @p " + (need > 0 ? Math.min(points - 1, (int) ((long) xp * points / need)) : 0) + " points", false);
	}

	// server thread, twice a second in our fountain's aura: 5% health back each time (full in ~10 s); not hunger
	public static void fountain(MinecraftServer server) {
		if (dead || server.getPlayerList().getPlayers().isEmpty()) return;
		ServerPlayer p = server.getPlayerList().getPlayers().get(0);
		p.heal(p.getMaxHealth() * 0.05f);
	}

	// Tormentor's reward, like Aghanim's shard: two more hearts for the rest of the match
	private static int shards;

	public static void shard(MinecraftServer server) {
		shards++;
		attributes(server);
		say(server, "Осколок терзателя: +2 сердца", "light_purple");
	}

	// --- Dota's hits ----------------------------------------------------------------------------------------------
	// A raised shield facing the attacker's stand-in (within 90 degrees) blocks the whole hit and takes the wear, like a
	// melee hit in Minecraft; the damage otherwise comes from that stand-in (armour applies as usual).
	public static void damage(MinecraftServer server, float amount, String attacker) {
		ServerPlayer player = server.getPlayerList().getPlayers().isEmpty() ? null : server.getPlayerList().getPlayers().get(0);
		if (player == null || dead) return;
		Entity from = null;
		for (Entity e : server.overworld().getAllEntities()) if (e.getTags().contains("dota_" + attacker)) { from = e; break; }
		if (from != null && player.isBlocking()) {
			net.minecraft.world.phys.Vec3 to = from.position().subtract(player.position()).multiply(1, 0, 1).normalize();
			net.minecraft.world.phys.Vec3 look = player.getViewVector(1).multiply(1, 0, 1).normalize();
			if (to.dot(look) > 0) {
				ItemStack shield = player.getUseItem();
				shield.hurtAndBreak(Math.max(1, (int) Math.ceil(amount)), player, player.getUsedItemHand());
				player.level().playSound(null, player.blockPosition(), net.minecraft.sounds.SoundEvents.SHIELD_BLOCK.value(),
					net.minecraft.sounds.SoundSource.PLAYERS, 1, 1);
				return;
			}
		}
		String cmd = String.format(Locale.ROOT, "damage @p %.2f minecraft:mob_attack", amount);
		if (from == null || !Sync.run(server, cmd + " by @e[tag=dota_" + attacker + ",limit=1]", false)) Sync.run(server, cmd);
	}

	// --- boss bar and hit effects (Dota decides; see MC:BossBar / MCBridge:HitUnit) ------------------------------
	private static String bossShown = "";

	// server thread: "boss none" or "boss <color> <hp> <max> <name...>": Roshan while Steve is in his pit, a building
	// a few seconds after Steve hit it (a Minecraft boss bar, like the Wither's)
	public static void boss(MinecraftServer server, String[] p) {
		String state = String.join(" ", java.util.Arrays.copyOfRange(p, 1, p.length));
		if (state.equals(bossShown)) return;
		if (bossShown.isEmpty()) Sync.run(server, "bossbar add mcdota:boss \"\"", false);
		bossShown = state;
		if (p[1].equals("none")) { Sync.run(server, "bossbar set mcdota:boss visible false", false); return; }
		String name = String.join(" ", java.util.Arrays.copyOfRange(p, 4, p.length));
		for (String c : new String[] { "players @a", "color " + p[1], "style notched_10", "max " + Math.max(1, Integer.parseInt(p[3])),
			"value " + Math.max(0, Integer.parseInt(p[2])), "name {text:\"" + name + "\"}", "visible true" })
			Sync.run(server, "bossbar set mcdota:boss " + c, false);
	}

	// server thread: a swing Dota landed: Minecraft's crit / sweep effects on the target's stand-in (Minecraft only
	// shows them when its own crosshair hit the stand-in, so they were missing now and then)
	public static void hitFx(MinecraftServer server, String kind, String id, int seconds) {
		Entity e = null;
		for (Entity c : server.overworld().getAllEntities()) if (c.getTags().contains("dota_" + id)) { e = c; break; }
		if (e == null) return;
		double x = e.getX(), y = e.getY() + e.getBbHeight() * 0.6, z = e.getZ();
		String at = String.format(Locale.ROOT, "%.2f %.2f %.2f", x, y, z);
		switch (kind) {
			case "crit" -> {
				Sync.run(server, "particle minecraft:crit " + at + " 0.3 0.4 0.3 0.4 18 force", false);
				Sync.run(server, "playsound minecraft:entity.player.attack.crit player @a " + at + " 1 1", false);
			}
			case "sweep" -> {
				Sync.run(server, "particle minecraft:sweep_attack " + at + " 0 0 0 0 1 force", false);
				Sync.run(server, "playsound minecraft:entity.player.attack.sweep player @a " + at + " 1 1", false);
			}
			case "burn" -> e.igniteForSeconds(seconds); // Fire Aspect: Minecraft's fire burns the Dota unit (fire hits)
			default -> Sync.run(server, "playsound minecraft:entity.player.attack.strong player @a " + at + " 1 1", false);
		}
	}

	// --- Dota's disables ----------------------------------------------------------------------------------------------
	// "cc <stun> <root> <speed ratio> <disarmed>": stunned/rooted -> no walking or jumping; slowed -> slower; stunned or
	// disarmed -> no swinging (AttackMixin asks noAttack)
	public static volatile boolean noAttack, noUse, noFly;
	private static String ccNow = "";

	public static void cc(MinecraftServer server, String[] p) {
		String now = String.join(" ", p);
		if (now.equals(ccNow) || dead) return;
		ccNow = now;
		boolean stun = p[1].equals("1"), root = p[2].equals("1");
		double ratio = Double.parseDouble(p[3]);
		boolean hexed = p.length > 5 && p[5].equals("1");
		noAttack = stun || hexed || p[4].equals("1");
		noUse = noFly = stun || hexed;
		Sync.run(server, String.format(Locale.ROOT, "attribute @p minecraft:movement_speed base set %.4f", root ? 0 : 0.1 * ratio), false);
		Sync.run(server, "attribute @p minecraft:jump_strength base set " + (root ? 0 : 0.42), false);
		if (stun) say(server, "Оглушён", "red");
	}

	// "follow x z": a Dota spell moves Steve (a push, a pull): Minecraft's player goes with it
	public static void follow(MinecraftServer server, double x, double z) {
		if (server.getPlayerList().getPlayers().isEmpty()) return;
		ServerPlayer pl = server.getPlayerList().getPlayers().get(0);
		// blocks in the way (a force staff toward stairs, a wall): up on top of them, like Dota's heroes slide up a
		// slope; a drop below is left to gravity (off a pillar he flies on, then falls)
		double y = pl.getY();
		net.minecraft.world.phys.AABB box = pl.getBoundingBox().move(x - pl.getX(), 0, z - pl.getZ());
		for (int i = 0; i < 8 && !pl.level().noCollision(pl, box); i++) {
			box = box.move(0, 0.5, 0);
			y += 0.5;
		}
		pl.teleportTo(x, y, z);
	}

	// a teleport (a twin gate) to block x, y, z: on the first height there with room for him (blocks built there)
	public static void teleport(MinecraftServer server, int x, int y, int z) {
		if (server.getPlayerList().getPlayers().isEmpty()) return;
		ServerPlayer pl = server.getPlayerList().getPlayers().get(0);
		double tx = x + 0.5, tz = z + 0.5, ty = y;
		net.minecraft.world.phys.AABB box = pl.getBoundingBox().move(tx - pl.getX(), ty - pl.getY(), tz - pl.getZ());
		for (int i = 0; i < 40 && !pl.level().noCollision(pl, box); i++) {
			box = box.move(0, 0.5, 0);
			ty += 0.5;
		}
		pl.teleportTo(tx, ty, tz);
		pl.fallDistance = 0;
	}

	// a block Dota took away (a Dota hero broke it, or what stood on it): Minecraft's breaking look and sound, no drop
	public static void unblock(MinecraftServer server, int x, int y, int z) {
		var level = server.overworld();
		var pos = new net.minecraft.core.BlockPos(x, y, z);
		var st = level.getBlockState(pos);
		if (st.isAir()) return;
		level.levelEvent(2001, pos, net.minecraft.world.level.block.Block.getId(st));
		level.setBlock(pos, net.minecraft.world.level.block.Blocks.AIR.defaultBlockState(), 3);
		Sync.collapse(server, pos); // what stood on it comes down
	}

	// --- mob sounds -----------------------------------------------------------------------------------------------
	// Radiant's creeps are Minecraft mobs in Dota (gen_mobs.py): their sounds, played at their stand-in (if it has one:
	// only units near Steve do)
	public static void mobSound(MinecraftServer server, String id, String mob, String kind) {
		Entity e = null;
		for (Entity c : server.overworld().getAllEntities()) if (c.getTags().contains("dota_" + id)) { e = c; break; }
		if (e == null) return;
		String base = mob.startsWith("zombie") ? "zombie" : "skeleton";
		String sound = switch (kind) {
			case "attack" -> mob.startsWith("zombie") ? "entity.zombie.ambient" : mob.startsWith("spider") ? "entity.spider.ambient" : "entity.skeleton.shoot";
			case "hurt" -> "entity." + base + ".hurt";
			default -> "entity." + base + ".death";
		};
		Sync.run(server, String.format(Locale.ROOT, "playsound minecraft:%s hostile @a %.2f %.2f %.2f 0.8 %.2f", sound, e.getX(), e.getY(), e.getZ(),
			0.9 + server.overworld().getRandom().nextFloat() * 0.2), false);
		if (kind.equals("death")) // (after its fall: MC:MobDeath)
			Sync.run(server, String.format(Locale.ROOT, "particle minecraft:poof %.2f %.2f %.2f 0.3 0.4 0.3 0.04 20 force", e.getX(), e.getY() + 0.6, e.getZ()), false);
	}

	// --- damage numbers ---------------------------------------------------------------------------------------------
	// Steve's hits on Dota units: the damage in Minecraft's font over the unit (its stand-in), rising and gone in
	// ~0.9 s; white, a crit red, a deny grey
	private static final List<Object[]> numbers = new ArrayList<>(); // { tag, ticks left }
	private static int numberCount;

	public static void damageNumber(MinecraftServer server, String id, int amount, String kind) {
		Entity e = null;
		for (Entity c : server.overworld().getAllEntities()) if (c.getTags().contains("dota_" + id)) { e = c; break; }
		boolean miss = kind.equals("miss");
		if (e == null || (amount <= 0 && !miss)) return;
		var r = server.overworld().getRandom();
		double x = e.getX() + (r.nextDouble() - 0.5) * 0.6, y = e.getY() + e.getBbHeight() + 0.2, z = e.getZ() + (r.nextDouble() - 0.5) * 0.6;
		String tag = "dmgnum_" + (++numberCount);
		String color = kind.equals("crit") ? "red" : kind.equals("deny") ? "gray" : "white";
		Sync.run(server, String.format(Locale.ROOT, "summon minecraft:text_display %.2f %.2f %.2f {billboard:\"center\",background:0,shadow:1b,"
			+ "Tags:[\"mcdota_dmg\",\"%s\"],text:{text:\"%s\",color:\"%s\",bold:%s},transformation:{left_rotation:[0f,0f,0f,1f],"
			+ "right_rotation:[0f,0f,0f,1f],translation:[0f,0f,0f],scale:[1.2f,1.2f,1.2f]}}", x, y, z, tag, miss ? "Промах" : String.valueOf(amount), miss ? "gray" : color,
			kind.equals("crit") ? "1b" : "0b"), false);
		numbers.add(new Object[] { tag, 18 });
	}

	private static void numbersTick(MinecraftServer server) {
		numbers.removeIf(n -> {
			int left = (int) n[1];
			if (left == 17) // a tick after it appeared: float up (the client interpolates)
				Sync.run(server, "data merge entity @e[tag=" + n[0] + ",limit=1] {start_interpolation:0,interpolation_duration:16,"
					+ "transformation:{left_rotation:[0f,0f,0f,1f],right_rotation:[0f,0f,0f,1f],translation:[0f,0.9f,0f],scale:[0.8f,0.8f,0.8f]}}", false);
			n[1] = left - 1;
			if (left > 0) return false;
			Sync.discard(server, (String) n[0]);
			return true;
		});
	}

	// --- death ----------------------------------------------------------------------------------------------------
	// Dota takes gold on death; Steve loses emeralds (2 + level, what he carries at most), his Dota hero dies too (the
	// killer gets the bounty), and he waits for Dota's respawn timer frozen at the spawn ("respawn" from Dota frees him).

	// server thread: the Minecraft player died
	public static void died(ServerPlayer player) {
		org.slf4j.LoggerFactory.getLogger("mcdota").info("death: {} (dead {})", "died", dead);
		MinecraftServer server = player.level().getServer();
		int have = player.getInventory().countItem(Items.EMERALD);
		int lose = Math.min(have, 2 + level);
		if (lose > 0) Sync.run(server, "clear @p minecraft:emerald " + lose);
		dead = true;
		Sync.out("died " + lose);
	}

	// server thread: back in the world after Minecraft's instant respawn: frozen until Dota's hero is back
	public static void afterRespawn(MinecraftServer server) {
		org.slf4j.LoggerFactory.getLogger("mcdota").info("death: {} (dead {})", "afterRespawn", dead);
		attributes(server);
		if (!dead) return;
		for (String c : new String[] { "gamemode adventure @p", "attribute @p minecraft:movement_speed base set 0",
			"attribute @p minecraft:jump_strength base set 0", "effect give @p minecraft:resistance infinite 4 true" })
			Sync.run(server, c);
	}

	// server thread: Dota's respawn timer
	// (shown again every second by tick() with the time left: Minecraft's respawn clears a title shown before it)
	private static long deadUntil;
	private static int deadLost;

	public static void deadFor(MinecraftServer server, int seconds, int lost) {
		org.slf4j.LoggerFactory.getLogger("mcdota").info("death: {} (dead {})", "deadFor", dead);
		deadUntil = System.currentTimeMillis() + seconds * 1000L;
		deadLost = lost;
		deadTitle(server);
	}

	private static void deadTitle(MinecraftServer server) {
		long left = (deadUntil - System.currentTimeMillis() + 999) / 1000;
		if (!dead || deadUntil == 0) return; // (until Dota's "respawn": "title @p clear")
		Sync.run(server, "title @p times 0 40 0");
		Sync.run(server, "title @p subtitle {text:\"-" + deadLost + " изумр., " + (left > 0 ? "возрождение через " + left + " с" : "возрождение...")
			+ "\",color:\"gray\"}");
		Sync.run(server, "title @p title {text:\"Вы погибли\",color:\"red\"}");
	}

	// Steve's spawn point (the market square, from Dota; Minecraft 0,0 until it arrives)
	private static int[] spawn = { 0, 0, 0 };
	private static boolean placed;

	// server thread: the player joined: to the spawn point (not wherever the last session ended)
	public static void joined(MinecraftServer server) {
		placed = false;
		spawnAt(server, spawn[0], spawn[1], spawn[2]);
	}

	// server thread: Dota's spawn point (sent again every few seconds; the first one also puts Steve there)
	public static void spawnAt(MinecraftServer server, int x, int y, int z) {
		boolean moved = !placed || spawn[0] != x || spawn[1] != y || spawn[2] != z;
		spawn = new int[] { x, y, z };
		if (moved) {
			Sync.run(server, String.format("setworldspawn %d %d %d", x, y, z));
			Sync.run(server, String.format("spawnpoint @p %d %d %d", x, y, z));
		}
		if (!placed) {
			placed = true;
			Sync.run(server, String.format(Locale.ROOT, "tp @p %.1f %d %.1f", x + 0.5, y, z + 0.5));
		}
	}

	// server thread: Dota respawned Steve's hero
	public static void respawn(MinecraftServer server) {
		org.slf4j.LoggerFactory.getLogger("mcdota").info("death: {} (dead {})", "respawn", dead);
		dead = false;
		deadUntil = 0;
		for (String c : new String[] { "gamemode survival @p", "attribute @p minecraft:movement_speed base set 0.1",
			"attribute @p minecraft:jump_strength base set 0.42", "effect clear @p minecraft:resistance", "title @p clear",
			String.format(Locale.ROOT, "tp @p %.1f %d %.1f", spawn[0] + 0.5, spawn[1], spawn[2] + 0.5),
			"effect give @p minecraft:instant_health 1 10 true" })
			Sync.run(server, c);
	}

	// --- Steve's projectiles, seen in Dota --------------------------------------------------------------------------
	private static final java.util.Set<Integer> flying = new java.util.HashSet<>();
	private static void projectiles(MinecraftServer server) {
		java.util.Set<Integer> now = new java.util.HashSet<>();
		for (Entity e : server.overworld().getAllEntities()) {
			String n = e.getClass().getSimpleName();
			String kind = n.equals("WindCharge") ? "wind_charge" : n.equals("ThrownEnderpearl") ? "ender_pearl"
				: e instanceof AbstractArrow a && !a.onGround() && a.getOwner() instanceof Player ? "arrow" : null;
			if (kind == null || !(e instanceof net.minecraft.world.entity.projectile.Projectile pr && pr.getOwner() instanceof Player)) continue;
			now.add(e.getId());
			var v = e.getDeltaMovement();
			Sync.out(String.format(Locale.ROOT, "proj %d %s %.2f %.2f %.2f %.2f %.2f", e.getId(), kind, e.getX(), e.getY(), e.getZ(), v.x, v.z));
		}
		for (Integer id : flying) if (!now.contains(id)) Sync.out("projend " + id);
		flying.clear();
		flying.addAll(now);
	}

	// --- arrows ---------------------------------------------------------------------------------------------------
	private static final List<AbstractArrow> arrows = new ArrayList<>();

	// server thread: an entity joined the world
	public static void entityLoaded(Entity e) {
		if (e instanceof AbstractArrow a && a.getOwner() instanceof Player) {
			arrows.add(a);
		}
	}

	// --- repair ---------------------------------------------------------------------------------------------------
	// material cost in emeralds (shop prices: iron ingot 2, diamond 4, netherite ingot 20, template 5, leather/string 0.5)
	private static final Map<String, Integer> VALUE = new HashMap<>();

	static {
		String[] tools = { "sword", "axe", "pickaxe", "shovel", "hoe" };
		int[] units = { 2, 3, 3, 1, 2 };
		for (int i = 0; i < tools.length; i++) {
			VALUE.put("wooden_" + tools[i], 1);
			VALUE.put("stone_" + tools[i], 1);
			VALUE.put("iron_" + tools[i], 2 * units[i]);
			VALUE.put("diamond_" + tools[i], 4 * units[i]);
			VALUE.put("netherite_" + tools[i], 4 * units[i] + 25);
		}
		String[] armor = { "helmet", "chestplate", "leggings", "boots" };
		int[] pieces = { 5, 8, 7, 4 };
		for (int i = 0; i < armor.length; i++) {
			VALUE.put("leather_" + armor[i], (pieces[i] + 1) / 2);
			VALUE.put("iron_" + armor[i], 2 * pieces[i]);
			VALUE.put("diamond_" + armor[i], 4 * pieces[i]);
			VALUE.put("netherite_" + armor[i], 4 * pieces[i] + 25);
		}
		VALUE.put("bow", 2);
		VALUE.put("crossbow", 4);
		VALUE.put("shield", 2);
		VALUE.put("elytra", 60);
		VALUE.put("fishing_rod", 1);
	}

	// server thread: a player used an entity; sneak + right click on the toolsmith repairs the held item
	public static InteractionResult interact(Player player, Entity target) {
		if (!player.level().isClientSide() && target.getTags().contains("mcdota_trader")) sellOffers(player, target);
		if (player.level().isClientSide() || !player.isShiftKeyDown() || !target.getTags().contains("mcdota_trader_toolsmith"))
			return InteractionResult.PASS;
		MinecraftServer server = player.level().getServer();
		ItemStack held = player.getMainHandItem();
		String id = BuiltInRegistries.ITEM.getKey(held.getItem()).getPath();
		Integer value = VALUE.get(id);
		if (value == null || !held.isDamaged()) {
			say(server, "Возьмите в руку повреждённое оружие, инструмент или броню", "yellow");
			return InteractionResult.SUCCESS;
		}
		int cost = Math.max(1, (int) Math.round(value / 3.0 * held.getDamageValue() / held.getMaxDamage()));
		int have = player.getInventory().countItem(Items.EMERALD);
		if (have < cost) {
			say(server, "Ремонт стоит " + cost + " изумр. (у вас " + have + ")", "red");
			return InteractionResult.SUCCESS;
		}
		Sync.run(server, "clear @p minecraft:emerald " + cost);
		held.setDamageValue(0);
		say(server, "Отремонтировано за " + cost + " изумр.", "green");
		return InteractionResult.SUCCESS;
	}

	// --- traders --------------------------------------------------------------------------------------------------

	private record Trader(String name, String profession, List<String> offers) { }
	private static final Map<String, double[]> spots = new java.util.concurrent.ConcurrentHashMap<>(); // profession -> x, z (exact), feet y

	// sync thread: Dota placed a trader
	public static void trader(double x, double z, String profession, double y) { spots.put(profession, new double[] { x, z, y }); }

	private static final List<Trader> TRADERS = new ArrayList<>();
	// emeralds for one of each item the shops sell (buy() fills it), plus what only drops
	private static final Map<String, Double> PRICE = new HashMap<>(Map.of(
		"rotten_flesh", 1 / 8.0, "beef", 1 / 4.0, "porkchop", 1 / 4.0, "totem_of_undying", 40.0, "emerald", 0.0));

	// --- selling: any trader buys anything worth something, not a list of fixed offers --------------------------
	// When the trading screen opens, the trader's own offers get one more for each kind of thing in the player's
	// inventory: worth an emerald or more -> one for that many emeralds (tools, weapons and armour by what's left of
	// them, each one on its own), less -> as many as make one emerald. A trader pays half the price, like Dota.
	public static void sellOffers(Player player, Entity target) {
		if (!(target instanceof net.minecraft.world.entity.npc.villager.AbstractVillager v)) return;
		Trader t = null;
		for (Trader c : TRADERS) if (target.getTags().contains("mcdota_trader_" + c.profession)) t = c;
		if (t == null) return;
		var offers = v.getOffers();
		while (offers.size() > t.offers.size()) offers.remove(offers.size() - 1);
		java.util.Set<String> seen = new java.util.HashSet<>();
		var inv = player.getInventory();
		for (int i = 0; i < inv.getContainerSize() && offers.size() < t.offers.size() + 27; i++) {
			ItemStack st = inv.getItem(i);
			if (st.isEmpty()) continue;
			double w = worth(st);
			if (w <= 0) continue;
			boolean single = st.isDamageableItem() || levels(st) > 0; // its own price: the exact one
			net.minecraft.world.item.trading.ItemCost cost;
			int emeralds;
			String key = BuiltInRegistries.ITEM.getKey(st.getItem()).getPath();
			if (w >= 1) {
				emeralds = (int) Math.floor(w);
				cost = single ? new net.minecraft.world.item.trading.ItemCost(st.getItemHolder(), 1,
					net.minecraft.core.component.DataComponentExactPredicate.someOf(st.getComponents(),
						net.minecraft.core.component.DataComponents.DAMAGE, net.minecraft.core.component.DataComponents.ENCHANTMENTS,
						net.minecraft.core.component.DataComponents.STORED_ENCHANTMENTS))
					: new net.minecraft.world.item.trading.ItemCost(st.getItem(), 1);
				if (single) key += "@" + st.getDamageValue() + st.getComponents().get(net.minecraft.core.component.DataComponents.ENCHANTMENTS)
					+ st.getComponents().get(net.minecraft.core.component.DataComponents.STORED_ENCHANTMENTS);
			} else {
				int n = (int) Math.ceil(1 / w - 1e-9);
				if (n > st.getMaxStackSize()) continue;
				emeralds = 1;
				cost = new net.minecraft.world.item.trading.ItemCost(st.getItem(), n);
			}
			if (!seen.add(key)) continue;
			offers.add(new net.minecraft.world.item.trading.MerchantOffer(cost, java.util.Optional.empty(),
				new ItemStack(Items.EMERALD, emeralds), single ? 1 : 9999, 0, 0f));
		}
	}

	private static int levels(ItemStack st) {
		int n = 0;
		for (var e : net.minecraft.world.item.enchantment.EnchantmentHelper.getEnchantmentsForCrafting(st).entrySet()) n += e.getIntValue();
		return n;
	}

	// what a trader pays for one: half its price; gear by its durability left; enchantments ~4 emeralds a level
	private static double worth(ItemStack st) {
		String id = BuiltInRegistries.ITEM.getKey(st.getItem()).getPath();
		Integer gear = VALUE.get(id);
		double v = gear != null ? gear * (st.isDamageableItem() ? 1.0 - (double) st.getDamageValue() / st.getMaxDamage() : 1)
			: PRICE.getOrDefault(id, 0.0);
		return (v + 4 * levels(st)) / 2;
	}

	private static String item(String id, int count, String components) {
		return "{id:\"minecraft:" + id + "\",count:" + count + (components == null ? "" : ",components:{" + components + "}") + "}";
	}

	private static String offer(int emeralds, String sellId, int sellCount, String components) {
		return "{buy:" + item("emerald", emeralds, null) + ",sell:" + item(sellId, sellCount, components)
			+ ",maxUses:9999,rewardExp:0b,xp:0,priceMultiplier:0f}";
	}

	private static String buy(int emeralds, String id) { return buy(emeralds, id, 1); }
	private static String buy(int emeralds, String id, int count) {
		PRICE.merge(id, (double) emeralds / count, Math::min);
		return offer(emeralds, id, count, null);
	}
	private static String potion(int emeralds, String item, String potion) {
		return offer(emeralds, item, 1, "\"minecraft:potion_contents\":{potion:\"minecraft:" + potion + "\"}");
	}
	private static String book(int emeralds, String ench, int lvl) {
		return offer(emeralds, "enchanted_book", 1, "\"minecraft:stored_enchantments\":{\"minecraft:" + ench + "\":" + lvl + "}");
	}

	static {
		// income: a lane creep ~1-2 emeralds, a neutral camp ~4-8 plus materials, a hero 6-17, a tower 10 (EMERALD_GOLD in Lua)
		// craft costs that follow: iron sword 4, iron armour 46, diamond sword 8, diamond armour 96, netherite +25 a piece
		TRADERS.add(new Trader("Лучник", "fletcher", List.of( // basic shop: bows, arrows, food
			buy(3, "bow"), buy(5, "crossbow"), buy(1, "arrow", 16), buy(1, "string", 2), buy(1, "flint", 4),
			buy(1, "feather", 8), buy(1, "bread", 4), buy(1, "cooked_beef", 2), buy(4, "golden_carrot", 2))));
		TRADERS.add(new Trader("Библиотекарь", "librarian", List.of( // basic shop: enchanting
			buy(12, "enchanting_table"), buy(2, "bookshelf"), buy(1, "lapis_lazuli", 8), buy(1, "book", 3), buy(1, "paper", 6),
			buy(8, "anvil"),
			book(15, "sharpness", 3), book(15, "protection", 3), book(12, "power", 3), book(10, "quick_charge", 2),
			book(10, "multishot", 1), book(8, "piercing", 3), book(12, "fire_aspect", 2), book(12, "flame", 1),
			book(8, "unbreaking", 3), book(6, "feather_falling", 4))));
		TRADERS.add(new Trader("Инструментальщик (присесть + ПКМ: ремонт)", "toolsmith", List.of( // basic shop: smithing
			buy(1, "crafting_table"), buy(3, "smithing_table"), buy(2, "iron_ingot"), buy(1, "leather", 2), buy(3, "shield"),
			buy(2, "flint_and_steel"), buy(2, "clock")))); // the clock shows Dota's game time (ClockHud)
		TRADERS.add(new Trader("Каменщик", "mason", List.of( // basic shop: building blocks (nothing to mine on Dota's map)
			buy(1, "cobblestone", 64), buy(1, "stone", 48), buy(1, "oak_planks", 64), buy(1, "oak_log", 16), buy(1, "dirt", 64),
			buy(1, "sand", 64), buy(1, "cobweb", 2), buy(6, "tnt"), buy(1, "gunpowder", 2),
			buy(2, "torch"), buy(3, "soul_torch")))); // wards: a torch is an observer, a soul torch a sentry
		TRADERS.add(new Trader("Ведьма", "cleric", List.of( // potions: for Steve (drink or splash) and against enemies (splash)
			potion(3, "potion", "healing"), potion(5, "potion", "strong_healing"), potion(4, "potion", "regeneration"),
			potion(3, "potion", "swiftness"), potion(5, "potion", "strength"), potion(4, "potion", "fire_resistance"),
			potion(2, "potion", "leaping"), potion(4, "splash_potion", "healing"), potion(5, "splash_potion", "regeneration"),
			potion(4, "splash_potion", "harming"), potion(7, "splash_potion", "strong_harming"), potion(4, "splash_potion", "poison"),
			potion(3, "splash_potion", "slowness"), potion(3, "splash_potion", "weakness"))));
		// far from the spawn, at both of Dota's secret shops: the rare stuff
		List<String> secret = List.of(
			buy(4, "diamond"), buy(20, "netherite_ingot"), buy(5, "netherite_upgrade_smithing_template"),
			buy(60, "elytra"), buy(1, "firework_rocket", 4), buy(8, "golden_apple"), buy(2, "ender_pearl"),
			buy(40, "mace"), buy(1, "wind_charge", 4),
			book(25, "mending", 1), book(40, "sharpness", 5), book(30, "protection", 4), book(30, "power", 5),
			book(15, "density", 3), book(15, "breach", 3), book(20, "wind_burst", 1));
		TRADERS.add(new Trader("Тайная лавка", "weaponsmith", secret));
		TRADERS.add(new Trader("Тайная лавка", "armorer", secret)); // (Dire's side)
	}

	private static int ticks;

	// server thread, every tick: arrows' flight time; every 2 s: the traders stand on the ground at their spots
	public static void tick(MinecraftServer server) {
		arrows.removeIf(a -> {
			if (a.isRemoved()) return true;
			if (a.tickCount < ARROW_TICKS) return false;
			a.discard();
			return true;
		});
		numbersTick(server);
		Sync.fallTick(server);
		projectiles(server);
		if (!server.getPlayerList().getPlayers().isEmpty()) {
			ServerPlayer pl = server.getPlayerList().getPlayers().get(0);
			if (noFly && pl.isFallFlying()) pl.stopFallFlying(); // (stunned, hexed: down he comes)
			if (pl.getY() < -62 && pl.isAlive()) {
				int sx = (int) Math.floor(pl.getX()), sz = (int) Math.floor(pl.getZ());
				pl.teleportTo(pl.getX(), Math.max(Hybrid.surfaceAt(sx, sz) + 1, server.overworld().getHeight(Heightmap.Types.MOTION_BLOCKING, sx, sz)), pl.getZ());
				pl.fallDistance = 0;
			}
		}
		if (++ticks % 20 == 0) deadTitle(server);
		if (ticks % 40 != 0 || server.getPlayerList().getPlayers().isEmpty()) return;
		ServerPlayer me = server.getPlayerList().getPlayers().get(0);
		if (me.experienceLevel != Progress.level) xpBar(server); // spent on enchanting, or orbs: back to his level
		ServerLevel level = server.overworld();
		for (Trader t : TRADERS) {
			double[] at = spots.get(t.profession);
			if (at == null) continue;
			double tx = at[0], tz = at[1];
			int bx = (int) Math.floor(tx), bz = (int) Math.floor(tz);
			if (!level.hasChunk(bx >> 4, bz >> 4)) continue;
			// Dota's ground height (a stall's roof is the column's top block); without it, the top of the column
			double y = !Double.isNaN(at[2]) ? at[2] : level.getHeight(Heightmap.Types.MOTION_BLOCKING, bx, bz);
			String tag = "mcdota_trader_" + t.profession;
			Entity e = null;
			for (Entity c : level.getAllEntities()) if (c.getTags().contains(tag)) { e = c; break; }
			if (e == null) {
				Sync.run(server, String.format(Locale.ROOT, "summon minecraft:villager %.2f %.1f %.2f {NoAI:1b,Invulnerable:1b,"
					+ "PersistenceRequired:1b,Silent:1b,Rotation:[90f,0f],Tags:[\"mcdota_trader\",\"%s\"],CustomName:\"%s\","
					+ "VillagerData:{profession:\"minecraft:%s\",level:5,type:\"minecraft:plains\"},Offers:{Recipes:[%s]},"
					+ "active_effects:[{id:\"minecraft:invisibility\",duration:-1,amplifier:0b,show_particles:0b}]}",
					tx, y, tz, tag, t.name, t.profession, String.join(",", t.offers)));
			} else if (Math.abs(e.getY() - y) > 0.1 || Math.abs(e.getX() - tx) > 0.1 || Math.abs(e.getZ() - tz) > 0.1) {
				e.teleportTo(tx, y, tz);
			}
			// a block in the trader's own space (a barrier, a stall part) swallows the clicks meant for him
			for (int dy = 0; dy < 2; dy++) { // his body (0.6 and 1.6 above the feet: a slab under them is fine)
				var st = level.getBlockState(net.minecraft.core.BlockPos.containing(tx, y + 0.6 + dy, tz));
				if (!st.isAir() && ticks % 400 == 0)
					org.slf4j.LoggerFactory.getLogger("mcdota").warn("trader {} is inside {} at {} {} {}", t.profession, st, bx, (int) Math.floor(y + 0.6) + dy, bz);
			}
		}
	}
}

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
	private static final int HP_PER_LEVEL = 1; // half a heart per Dota level: level 30 = 49 hp (Dota's DOTA_TO_MC: 1 hp = 50 Dota damage)
	private static final double SWEEP = 0.8; // sweep hits deal this share of the main hit (vanilla: 1 damage flat)
	private static final int ARROW_TICKS = 80; // Steve's arrows fly straight (Dota's camera can't look up to lob them) for 4 s
	private static int level = 1;
	private static boolean dead;

	private static void say(MinecraftServer server, String text, String color) {
		Sync.run(server, "title @p actionbar {text:\"" + text + "\",color:\"" + color + "\"}");
	}

	// the player's own attributes: also after a respawn, which resets them
	public static void attributes(MinecraftServer server) {
		Sync.run(server, "attribute @p minecraft:max_health base set " + (20 + (level - 1) * HP_PER_LEVEL));
		Sync.run(server, "attribute @p minecraft:sweeping_damage_ratio base set " + SWEEP);
		Sync.run(server, "attribute @p minecraft:knockback_resistance base set 1"); // Dota hits hurt but don't shove the camera
	}

	// server thread: new Dota match
	public static void newMatch(MinecraftServer server) {
		level = 1;
		dead = false;
		for (String c : new String[] {
			"gamemode survival @p", "clear @p", "xp set @p 0 levels", "xp set @p 0 points",
			"effect clear @p", "effect give @p minecraft:instant_health 1 10 true", "effect give @p minecraft:saturation 1 20 true",
			"give @p minecraft:wooden_sword", "give @p minecraft:wooden_pickaxe", "give @p minecraft:crafting_table",
			"give @p minecraft:bread 8", "give @p minecraft:oak_planks 16",
			"kill @e[tag=mcdota_trader]", // re-summoned with fresh trades by tick()
		}) Sync.run(server, c);
		attributes(server);
	}

	// server thread: Steve killed a Dota unit: "loot <emeralds> [<item> <n>]..."
	// "loot <emeralds> <gold> [<item> <n>]...": Dota keeps the gold left over below an emerald for the next kill
	public static void loot(MinecraftServer server, String[] p) {
		int emeralds = Integer.parseInt(p[1]);
		if (emeralds > 0) Sync.run(server, "give @p minecraft:emerald " + emeralds);
		StringBuilder got = new StringBuilder("+" + p[2] + " gold");
		if (emeralds > 0) got.append(" = ").append(emeralds).append(" emerald").append(emeralds > 1 ? "s" : "");
		for (int i = 3; i + 1 < p.length; i += 2) {
			int n = Integer.parseInt(p[i + 1]);
			if (n <= 0 || p[i].equals("none")) continue;
			Sync.run(server, "give @p minecraft:" + p[i] + " " + n);
			got.append(", ").append(n).append(" ").append(p[i].replace('_', ' '));
		}
		say(server, got.toString(), "green");
	}

	// server thread: Steve's Dota level changed
	public static void level(MinecraftServer server, int lvl) {
		level = lvl;
		attributes(server);
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

	// --- death ----------------------------------------------------------------------------------------------------
	// Dota takes gold on death; Steve loses emeralds (2 + level, what he carries at most), his Dota hero dies too (the
	// killer gets the bounty), and he waits for Dota's respawn timer frozen at the spawn ("respawn" from Dota frees him).

	// server thread: the Minecraft player died
	public static void died(ServerPlayer player) {
		MinecraftServer server = player.level().getServer();
		int have = player.getInventory().countItem(Items.EMERALD);
		int lose = Math.min(have, 2 + level);
		if (lose > 0) Sync.run(server, "clear @p minecraft:emerald " + lose);
		dead = true;
		Sync.out("died " + lose);
	}

	// server thread: back in the world after Minecraft's instant respawn: frozen until Dota's hero is back
	public static void afterRespawn(MinecraftServer server) {
		attributes(server);
		if (!dead) return;
		for (String c : new String[] { "gamemode adventure @p", "attribute @p minecraft:movement_speed base set 0",
			"attribute @p minecraft:jump_strength base set 0", "effect give @p minecraft:resistance infinite 4 true" })
			Sync.run(server, c);
	}

	// server thread: Dota's respawn timer
	public static void deadFor(MinecraftServer server, int seconds, int lost) {
		Sync.run(server, "title @p times 0 " + seconds * 20 + " 10");
		Sync.run(server, "title @p subtitle {text:\"-" + lost + " emeralds, respawn in " + seconds + " s\",color:\"gray\"}");
		Sync.run(server, "title @p title {text:\"You died\",color:\"red\"}");
	}

	// server thread: Dota respawned Steve's hero
	public static void respawn(MinecraftServer server) {
		dead = false;
		for (String c : new String[] { "gamemode survival @p", "attribute @p minecraft:movement_speed base set 0.1",
			"attribute @p minecraft:jump_strength base set 0.42", "effect clear @p minecraft:resistance", "title @p clear",
			"tp @p 0.5 0 0.5", "effect give @p minecraft:instant_health 1 10 true" })
			Sync.run(server, c);
	}

	// --- arrows ---------------------------------------------------------------------------------------------------
	private static final List<AbstractArrow> arrows = new ArrayList<>();

	// server thread: an entity joined the world
	public static void entityLoaded(Entity e) {
		if (e instanceof AbstractArrow a && a.getOwner() instanceof Player) {
			a.setNoGravity(true);
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
		if (player.level().isClientSide() || !player.isShiftKeyDown() || !target.getTags().contains("mcdota_trader_toolsmith"))
			return InteractionResult.PASS;
		MinecraftServer server = player.level().getServer();
		ItemStack held = player.getMainHandItem();
		String id = BuiltInRegistries.ITEM.getKey(held.getItem()).getPath();
		Integer value = VALUE.get(id);
		if (value == null || !held.isDamaged()) {
			say(server, "Hold a damaged weapon, tool or armour piece to repair it", "yellow");
			return InteractionResult.SUCCESS;
		}
		int cost = Math.max(1, (int) Math.round(value / 3.0 * held.getDamageValue() / held.getMaxDamage()));
		int have = player.getInventory().countItem(Items.EMERALD);
		if (have < cost) {
			say(server, "Repair costs " + cost + " emeralds (you have " + have + ")", "red");
			return InteractionResult.SUCCESS;
		}
		Sync.run(server, "clear @p minecraft:emerald " + cost);
		held.setDamageValue(0);
		say(server, "Repaired for " + cost + " emeralds", "green");
		return InteractionResult.SUCCESS;
	}

	// --- traders --------------------------------------------------------------------------------------------------

	private record Trader(String name, String profession, List<String> offers) { }
	private static final Map<String, int[]> spots = new java.util.concurrent.ConcurrentHashMap<>(); // profession -> x, z

	// sync thread: Dota placed a trader
	public static void trader(int x, int z, String profession) { spots.put(profession, new int[] { x, z }); }

	private static final List<Trader> TRADERS = new ArrayList<>();

	private static String item(String id, int count, String components) {
		return "{id:\"minecraft:" + id + "\",count:" + count + (components == null ? "" : ",components:{" + components + "}") + "}";
	}

	private static String offer(int emeralds, String sellId, int sellCount, String components) {
		return "{buy:" + item("emerald", emeralds, null) + ",sell:" + item(sellId, sellCount, components)
			+ ",maxUses:9999,rewardExp:0b,xp:0,priceMultiplier:0f}";
	}

	private static String buy(int emeralds, String id) { return offer(emeralds, id, 1, null); }
	private static String buy(int emeralds, String id, int count) { return offer(emeralds, id, count, null); }
	private static String book(int emeralds, String ench, int lvl) {
		return offer(emeralds, "enchanted_book", 1, "\"minecraft:stored_enchantments\":{\"minecraft:" + ench + "\":" + lvl + "}");
	}

	static {
		// income: a lane creep ~1-2 emeralds, a neutral camp ~4-8 plus materials, a hero 6-17, a tower 10 (EMERALD_GOLD in Lua)
		// craft costs that follow: iron sword 4, iron armour 46, diamond sword 8, diamond armour 96, netherite +25 a piece
		TRADERS.add(new Trader("Fletcher", "fletcher", List.of( // basic shop: the everyday materials
			buy(1, "oak_log", 8), buy(1, "cobblestone", 32), buy(2, "string", 4), buy(1, "flint", 4), buy(1, "feather", 8),
			buy(2, "leather", 4), buy(2, "iron_ingot"), buy(1, "tripwire_hook"), buy(2, "gunpowder", 4), buy(1, "paper", 6),
			buy(1, "arrow", 16), buy(1, "bread", 4), buy(2, "cooked_beef", 4))));
		TRADERS.add(new Trader("Librarian", "librarian", List.of( // basic shop: enchanting
			buy(12, "enchanting_table"), buy(2, "bookshelf"), buy(1, "lapis_lazuli", 8), buy(1, "book", 3), buy(8, "anvil"),
			buy(2, "grindstone"), book(15, "sharpness", 3), book(15, "protection", 3), book(12, "power", 3),
			book(10, "quick_charge", 2), book(10, "multishot", 1), book(8, "piercing", 3), book(12, "fire_aspect", 2),
			book(8, "unbreaking", 3), book(6, "feather_falling", 4))));
		TRADERS.add(new Trader("Toolsmith (sneak + right click: repair)", "toolsmith", List.of( // basic shop: smithing
			buy(1, "crafting_table"), buy(3, "smithing_table"), buy(7, "iron_ingot", 4), buy(3, "shield"))));
		TRADERS.add(new Trader("Mason", "mason", List.of( // basic shop: building blocks (nothing to mine on Dota's map);
			// only blocks Dota has models for (MODELS in addon_game_mode.lua), anything else would show up as cobblestone there
			buy(1, "cobblestone", 64), buy(1, "stone", 48), buy(1, "oak_planks", 64), buy(1, "oak_log", 16), buy(1, "dirt", 64),
			buy(1, "sand", 64))));
		TRADERS.add(new Trader("Secret shop", "weaponsmith", List.of( // far from the spawn: the rare stuff
			buy(4, "diamond"), buy(15, "diamond", 4), buy(20, "netherite_ingot"), buy(5, "netherite_upgrade_smithing_template"),
			buy(60, "elytra"), buy(8, "golden_apple"), buy(3, "ender_pearl", 2), buy(30, "totem_of_undying"),
			buy(6, "experience_bottle", 8), book(25, "mending", 1), book(40, "sharpness", 5), book(30, "protection", 4),
			book(30, "power", 5))));
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
		if (++ticks % 40 != 0 || server.getPlayerList().getPlayers().isEmpty()) return;
		ServerLevel level = server.overworld();
		for (Trader t : TRADERS) {
			int[] at = spots.get(t.profession);
			if (at == null || !level.hasChunk(at[0] >> 4, at[1] >> 4)) continue;
			int tx = at[0], tz = at[1];
			int y = level.getHeight(Heightmap.Types.MOTION_BLOCKING, tx, tz);
			String tag = "mcdota_trader_" + t.profession;
			Entity e = null;
			for (Entity c : level.getAllEntities()) if (c.getTags().contains(tag)) { e = c; break; }
			if (e == null) {
				Sync.run(server, String.format(Locale.ROOT, "summon minecraft:villager %.1f %d %.1f {NoAI:1b,Invulnerable:1b,"
					+ "PersistenceRequired:1b,Silent:1b,Rotation:[90f,0f],Tags:[\"mcdota_trader\",\"%s\"],CustomName:\"%s\","
					+ "VillagerData:{profession:\"minecraft:%s\",level:5,type:\"minecraft:plains\"},Offers:{Recipes:[%s]},"
					+ "active_effects:[{id:\"minecraft:invisibility\",duration:-1,amplifier:0b,show_particles:0b}]}",
					tx + 0.5, y, tz + 0.5, tag, t.name, t.profession, String.join(",", t.offers)));
			} else if ((int) Math.floor(e.getY()) != y || (int) Math.floor(e.getX()) != tx || (int) Math.floor(e.getZ()) != tz) {
				e.teleportTo(tx + 0.5, y, tz + 0.5);
			}
		}
	}
}

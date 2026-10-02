package dev.mcdota;

import net.minecraft.server.MinecraftServer;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.level.levelgen.Heightmap;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

// Steve's progression inside one Dota match. Dota has nothing to mine, so everything comes from fighting:
// Steve's kills drop emeralds (by the unit's gold bounty, see MC:LootFor in Lua) and food, his Dota level (hero XP from
// those kills) is his max health, Minecraft XP stays for enchanting. Three traders by the spawn sell the rest; a better
// weapon or armour piece costs emeralds PLUS the previous tier (wood -> stone -> iron -> diamond -> netherite), so nobody
// skips straight to netherite. Every new match starts over with a wooden sword.
// The traders are DRAWN by Dota (blocky villager models, tools/gen_villager.py) at spots Dota picks ("trader x z prof");
// Minecraft only keeps an invisible villager there to open the trading screen (anything Minecraft draws lags Dota's world).
public final class Progress {
	private static final int HP_PER_LEVEL = 1; // half a heart per Dota level: level 30 = 49 hp (Dota's DOTA_TO_MC: 1 hp = 50 Dota damage)

	// server thread: new Dota match
	public static void newMatch(MinecraftServer server) {
		for (String c : new String[] {
			"clear @p", "xp set @p 0 levels", "xp set @p 0 points",
			"attribute @p minecraft:max_health base set 20", "effect give @p minecraft:instant_health 1 10 true",
			"effect give @p minecraft:saturation 1 20 true",
			"give @p minecraft:wooden_sword", "give @p minecraft:wooden_pickaxe", "give @p minecraft:bread 8",
			"give @p minecraft:oak_planks 16",
			"kill @e[tag=mcdota_trader]", // re-summoned with fresh trades by tick()
		}) Sync.run(server, c);
	}

	// server thread: Steve killed a Dota unit
	public static void loot(MinecraftServer server, int emeralds, String food, int n) {
		org.slf4j.LoggerFactory.getLogger("mcdota").info("loot: {} emeralds, {} x{}", emeralds, food, n);
		Sync.run(server, "give @p minecraft:emerald " + emeralds);
		if (n > 0 && !food.equals("none")) Sync.run(server, "give @p minecraft:" + food + " " + n);
		Sync.run(server, "title @p actionbar {text:\"+" + emeralds + " emerald" + (emeralds > 1 ? "s" : "") + "\",color:\"green\"}");
	}

	// server thread: Steve's Dota level changed
	public static void level(MinecraftServer server, int lvl) {
		Sync.run(server, "attribute @p minecraft:max_health base set " + (20 + (lvl - 1) * HP_PER_LEVEL));
	}

	// --- traders ---------------------------------------------------------------------------------------------------

	private record Trader(String name, String profession, List<String> offers) { }
	private static final java.util.Map<String, int[]> spots = new java.util.concurrent.ConcurrentHashMap<>(); // profession -> x, z

	// sync thread: Dota placed a trader
	public static void trader(int x, int z, String profession) { spots.put(profession, new int[] { x, z }); }

	private static final List<Trader> TRADERS = new ArrayList<>();

	private static String item(String id, int count, String components) {
		return "{id:\"minecraft:" + id + "\",count:" + count + (components == null ? "" : ",components:{" + components + "}") + "}";
	}

	private static String offer(int emeralds, String sellId, int sellCount, String components, String buyB) {
		return "{buy:" + item("emerald", emeralds, null) + (buyB == null ? "" : ",buyB:" + item(buyB, 1, null))
			+ ",sell:" + item(sellId, sellCount, components) + ",maxUses:9999,rewardExp:0b,xp:0,priceMultiplier:0f}";
	}

	private static String buy(int emeralds, String id) { return offer(emeralds, id, 1, null, null); }
	private static String buy(int emeralds, String id, int count) { return offer(emeralds, id, count, null, null); }
	private static String upgrade(int emeralds, String id, String from) { return offer(emeralds, id, 1, null, from); }
	private static String book(int emeralds, String ench, int lvl) {
		return offer(emeralds, "enchanted_book", 1, "\"minecraft:stored_enchantments\":{\"minecraft:" + ench + "\":" + lvl + "}", null);
	}

	static {
		// prices: a lane creep ~2 emeralds, a neutral camp ~4-8, a hero 6-17, a tower 10 (see EMERALD_GOLD in Lua)
		List<String> w = new ArrayList<>();
		w.add(upgrade(3, "stone_sword", "wooden_sword"));
		w.add(upgrade(8, "iron_sword", "stone_sword"));
		w.add(upgrade(20, "diamond_sword", "iron_sword"));
		w.add(upgrade(40, "netherite_sword", "diamond_sword"));
		w.add(buy(9, "iron_axe"));
		w.add(upgrade(22, "diamond_axe", "iron_axe"));
		w.add(upgrade(42, "netherite_axe", "diamond_axe"));
		w.add(buy(6, "bow"));
		w.add(buy(10, "crossbow"));
		w.add(buy(1, "arrow", 16));
		w.add(buy(5, "shield"));
		w.add(upgrade(2, "stone_pickaxe", "wooden_pickaxe"));
		w.add(upgrade(5, "iron_pickaxe", "stone_pickaxe"));
		w.add(upgrade(12, "diamond_pickaxe", "iron_pickaxe"));
		TRADERS.add(new Trader("Weaponsmith", "weaponsmith", w));

		List<String> a = new ArrayList<>();
		String[] parts = { "helmet", "chestplate", "leggings", "boots" };
		int[] leather = { 1, 2, 2, 1 }, iron = { 5, 8, 7, 4 }, diamond = { 12, 20, 16, 10 }, netherite = { 25, 40, 32, 20 };
		for (int i = 0; i < 4; i++) a.add(buy(leather[i], "leather_" + parts[i]));
		for (int i = 0; i < 4; i++) a.add(upgrade(iron[i], "iron_" + parts[i], "leather_" + parts[i]));
		for (int i = 0; i < 4; i++) a.add(upgrade(diamond[i], "diamond_" + parts[i], "iron_" + parts[i]));
		for (int i = 0; i < 4; i++) a.add(upgrade(netherite[i], "netherite_" + parts[i], "diamond_" + parts[i]));
		a.add(buy(60, "elytra"));
		a.add(buy(2, "firework_rocket", 8));
		TRADERS.add(new Trader("Armorer", "armorer", a));

		List<String> l = new ArrayList<>();
		l.add(buy(1, "bread", 4));
		l.add(buy(2, "cooked_beef", 4));
		l.add(buy(8, "golden_apple"));
		l.add(buy(12, "enchanting_table"));
		l.add(buy(2, "bookshelf"));
		l.add(buy(1, "lapis_lazuli", 8));
		l.add(buy(8, "anvil"));
		l.add(book(15, "sharpness", 3));
		l.add(book(15, "protection", 3));
		l.add(book(12, "power", 3));
		l.add(book(10, "quick_charge", 2));
		l.add(book(10, "multishot", 1));
		l.add(book(8, "piercing", 3));
		l.add(book(12, "fire_aspect", 2));
		l.add(book(8, "unbreaking", 3));
		l.add(book(25, "mending", 1));
		l.add(book(6, "feather_falling", 4));
		l.add(buy(1, "cobblestone", 32));
		l.add(buy(1, "oak_planks", 32));
		TRADERS.add(new Trader("Librarian", "librarian", l));
	}

	private static int ticks;

	// server thread, every tick: keep the traders standing on the ground by the spawn (terrain is built after they spawn)
	public static void tick(MinecraftServer server) {
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

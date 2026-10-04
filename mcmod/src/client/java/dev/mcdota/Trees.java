package dev.mcdota;

import net.minecraft.client.Minecraft;
import net.minecraft.core.particles.BlockParticleOption;
import net.minecraft.core.particles.ParticleTypes;
import net.minecraft.server.MinecraftServer;
import net.minecraft.sounds.SoundEvents;
import net.minecraft.sounds.SoundSource;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.Interaction;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.phys.EntityHitResult;

import java.util.Locale;

// Dota's trees in Minecraft: each one an invisible "interaction" entity exactly where the tree stands (Dota's trees
// are thin and off Minecraft's grid, blocks would sit wrong). Holding the attack button on one chops it like
// Minecraft wood: progress as fast as the held item breaks an oak log (axes fast, a sword or a hand slowly), wood hit
// sounds and chips; done -> it's gone, two oak logs, and Dota cuts its tree ("chop <id>"). No collision (Steve walks
// through trees).
public final class Trees {
	private static final float HEIGHT = 3, WIDTH = 0.7f;
	private static int target = -1; // the tree entity being chopped (client side id)
	private static float progress;
	private static int ticks;

	// server thread: "tree <id> <x> <y> <z>" (a tree, or one grown back), "untree <id>" (cut in Dota)
	private static final java.util.Set<String> placed = java.util.concurrent.ConcurrentHashMap.newKeySet();

	public static void place(MinecraftServer server, String id, double x, double y, double z) {
		if (placed.contains(id)) remove(server, id); // (grown back)
		// when its chunk is loaded (Sync's terrain queue: the map is far bigger than what's loaded)
		Sync.column(server, (int) Math.floor(x), (int) Math.floor(z), () -> {
			Sync.run(server, String.format(Locale.ROOT, "summon minecraft:interaction %.3f %.2f %.3f {width:%.2ff,height:%.1ff,response:1b,"
				+ "Tags:[\"mctree\",\"tree_%s\"]}", x, y, z, WIDTH, HEIGHT, id), false);
			placed.add(id);
		});
	}

	public static void remove(MinecraftServer server, String id) {
		if (placed.remove(id)) Sync.discard(server, "tree_" + id);
	}

	// client thread, every tick: chopping the tree under the crosshair while the attack button is held
	public static void tick(Minecraft mc) {
		var player = mc.player;
		var server = mc.getSingleplayerServer();
		Entity e = mc.hitResult instanceof EntityHitResult h ? h.getEntity() : null;
		boolean on = player != null && server != null && mc.screen == null && mc.options.keyAttack.isDown()
			&& e instanceof Interaction && e.getTags().contains("mctree");
		if (!on) { target = -1; progress = 0; return; }
		if (e.getId() != target) { target = e.getId(); progress = 0; ticks = 0; }
		// Minecraft's mining speed for an oak log (hardness 2): the held item's speed / 60 a tick
		progress += player.getMainHandItem().getDestroySpeed(Blocks.OAK_LOG.defaultBlockState()) / 60f;
		player.swing(net.minecraft.world.InteractionHand.MAIN_HAND);
		String tag = e.getTags().stream().filter(t -> t.startsWith("tree_")).findFirst().orElse(null);
		double x = e.getX(), y = e.getY() + 1.2, z = e.getZ();
		boolean done = progress >= 1;
		boolean sound = ++ticks % 4 == 0;
		server.execute(() -> {
			var level = server.overworld();
			if (sound || done) {
				level.playSound(null, x, y, z, done ? SoundEvents.WOOD_BREAK : SoundEvents.WOOD_HIT, SoundSource.BLOCKS, done ? 1 : 0.5f, done ? 0.8f : 0.5f);
				level.sendParticles(new BlockParticleOption(ParticleTypes.BLOCK, Blocks.OAK_LOG.defaultBlockState()), x, y, z, done ? 30 : 4, 0.3, 0.6, 0.3, 0.1);
			}
			if (done && tag != null) {
				remove(server, tag.substring(5));
				Sync.run(server, "give @p minecraft:oak_log 2", false);
				Sync.out("chop " + tag.substring(5));
			}
		});
		if (done) { target = -1; progress = 0; }
	}
}

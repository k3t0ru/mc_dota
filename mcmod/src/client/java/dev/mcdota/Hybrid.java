package dev.mcdota;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;

import java.util.concurrent.ConcurrentHashMap;

// Hybrid mode: blocks standing on the ground are drawn by Dota (cubes nailed to its world, so they can't swim), and
// Minecraft skips them when it builds chunk meshes. Minecraft still draws the ground (see-through magenta on top, real
// dirt/stone in dug holes), the hand and the HUD.
public final class Hybrid {
	private static final ConcurrentHashMap<Long, Integer> surface = new ConcurrentHashMap<>(); // column -> feet y of the ground

	public static void setSurface(int x, int z, int y) { surface.put(key(x, z), y); }

	public static int surfaceAt(int x, int z) { return surface.getOrDefault(key(x, z), 0); }

	private static long key(int x, int z) { return ((long) x << 32) ^ (z & 0xffffffffL); }

	private static boolean terrain(BlockState s) {
		// only what the terrain builder puts at or above the surface (the magenta skin); dirt/stone there were placed by a player
		return s.is(Blocks.PODZOL) || s.is(Blocks.MUD_BRICKS) || s.is(Blocks.MUD_BRICK_SLAB) || s.is(Blocks.BARRIER);
	}

	// The ground can't be dug (not yet: holes in Dota's ground are more trouble than they're worth): only blocks a player
	// put above the surface can be broken or blown up, never the terrain skin or anything below the surface.
	public static boolean ground(BlockState s, BlockPos p) {
		return terrain(s) || p.getY() < surface.getOrDefault(key(p.getX(), p.getZ()), 0);
	}

	// render thread (chunk compile): Dota draws this one
	public static boolean drawnByDota(BlockState s, BlockPos p) {
		return !s.isAir() && s.getFluidState().isEmpty() && !terrain(s) && p.getY() >= surface.getOrDefault(key(p.getX(), p.getZ()), 0);
	}
}

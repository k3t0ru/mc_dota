package dev.mcdota.mixin;

import dev.mcdota.Sync;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.ServerExplosion;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

import java.util.ArrayList;
import java.util.List;

// (and Dota shows the blast: "boom x y z")
// TNT blows up what players built, but not the ground (no digging: Hybrid.ground) nor what Dota built (the market
// stalls, the fountain's barriers: Sync.protectedBlocks) - Dota keeps drawing those, so they'd be ghosts.
@Mixin(ServerExplosion.class)
public class ExplosionMixin {
	// every explosion as it goes off: Dota's look of it ("boom": TNT; "wind": a wind charge's burst, a gust)
	@Inject(method = "explode", at = @At("HEAD"))
	private void mcdota$report(CallbackInfoReturnable<Integer> cir) {
		var c = ((ServerExplosion) (Object) this).center();
		var src = ((ServerExplosion) (Object) this).getDirectSourceEntity();
		boolean wind = src != null && src.getClass().getSimpleName().contains("WindCharge");
		Sync.out(String.format(java.util.Locale.ROOT, "%s %.2f %.2f %.2f", wind ? "wind" : "boom", c.x, c.y, c.z));
	}

	@Inject(method = "calculateExplodedPositions", at = @At("RETURN"), cancellable = true)
	private void mcdota$spareDotaBlocks(CallbackInfoReturnable<List<BlockPos>> cir) {
		List<BlockPos> all = cir.getReturnValue();
		var level = ((ServerExplosion) (Object) this).level();
		var c = ((ServerExplosion) (Object) this).center();
		if (all.isEmpty()) return;
		List<BlockPos> keep = new ArrayList<>(all.size());
		for (BlockPos p : all)
			if (!Sync.protectedBlocks.contains(p) && !dev.mcdota.Hybrid.ground(level.getBlockState(p), p)
				&& !dev.mcdota.Hybrid.tree(level.getBlockState(p))) keep.add(p); // (trees: Dota's)
		cir.setReturnValue(keep);
	}
}

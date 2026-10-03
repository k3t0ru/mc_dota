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

// TNT blows up what players built, but not the ground (no digging: Hybrid.ground) nor what Dota built (the market
// stalls, the fountain's barriers: Sync.protectedBlocks) - Dota keeps drawing those, so they'd be ghosts.
@Mixin(ServerExplosion.class)
public class ExplosionMixin {
	@Inject(method = "calculateExplodedPositions", at = @At("RETURN"), cancellable = true)
	private void mcdota$spareDotaBlocks(CallbackInfoReturnable<List<BlockPos>> cir) {
		List<BlockPos> all = cir.getReturnValue();
		if (all.isEmpty()) return;
		var level = ((ServerExplosion) (Object) this).level();
		List<BlockPos> keep = new ArrayList<>(all.size());
		for (BlockPos p : all)
			if (!Sync.protectedBlocks.contains(p) && !dev.mcdota.Hybrid.ground(level.getBlockState(p), p)) keep.add(p);
		cir.setReturnValue(keep);
	}
}

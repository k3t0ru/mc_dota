package dev.mcdota.mixin;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.FireBlock;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// Fire burns on Dota's ground everywhere. Where the ground is half a block higher, Minecraft's terrain tops it with a
// slab (Sync.terrain), and a bottom slab's top isn't a full face, so vanilla fire couldn't stand there: flint and
// steel worked in some places only. (Dota draws such fire half a block lower, on the slab: MC:ShowBlock.)
@Mixin(FireBlock.class)
public class FireMixin {
	@Inject(method = "canSurvive", at = @At("RETURN"), cancellable = true)
	private void mcdota$onTerrainSlab(BlockState state, LevelReader level, BlockPos pos, CallbackInfoReturnable<Boolean> cir) {
		if (!cir.getReturnValue() && level.getBlockState(pos.below()).is(Blocks.MUD_BRICK_SLAB)) cir.setReturnValue(true);
	}
}

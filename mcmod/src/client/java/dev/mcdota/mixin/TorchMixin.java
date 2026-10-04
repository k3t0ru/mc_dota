package dev.mcdota.mixin;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.LevelReader;
import net.minecraft.world.level.block.BaseTorchBlock;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// Torches (wards) stand on Dota's ground everywhere, also on the half steps' slabs (like FireMixin)
@Mixin(BaseTorchBlock.class)
public class TorchMixin {
	@Inject(method = "canSurvive", at = @At("RETURN"), cancellable = true)
	private void mcdota$onTerrainSlab(BlockState state, LevelReader level, BlockPos pos, CallbackInfoReturnable<Boolean> cir) {
		if (!cir.getReturnValue() && level.getBlockState(pos.below()).is(Blocks.MUD_BRICK_SLAB)) cir.setReturnValue(true);
	}
}

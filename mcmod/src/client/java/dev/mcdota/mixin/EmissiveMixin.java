package dev.mcdota.mixin;

import net.minecraft.core.BlockPos;
import net.minecraft.world.level.BlockGetter;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockBehaviour;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// The see-through ground (magenta podzol / mud bricks) renders full-bright, so shadows, night or a block standing on it
// never darken it into a visible black patch: it stays exactly the overlay's hole colour.
@Mixin(BlockBehaviour.BlockStateBase.class)
public class EmissiveMixin {
	@Inject(method = "emissiveRendering", at = @At("HEAD"), cancellable = true)
	private void mcdota$magentaIsBright(BlockGetter level, BlockPos pos, CallbackInfoReturnable<Boolean> cir) {
		BlockBehaviour.BlockStateBase s = (BlockBehaviour.BlockStateBase) (Object) this;
		if (s.is(Blocks.PODZOL) || s.is(Blocks.MUD_BRICKS) || s.is(Blocks.MUD_BRICK_SLAB) || s.is(Blocks.STRIPPED_OAK_LOG)) cir.setReturnValue(true);
	}
}

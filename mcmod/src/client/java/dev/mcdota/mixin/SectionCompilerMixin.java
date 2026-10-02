package dev.mcdota.mixin;

import dev.mcdota.Hybrid;
import net.minecraft.client.renderer.chunk.RenderSectionRegion;
import net.minecraft.core.BlockPos;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// Chunk meshes are built from this region: blocks Dota draws (Hybrid.drawnByDota) look like air to it, so Minecraft
// neither draws them nor culls the faces under them (the magenta ground top stays, no hole into the dirt below).
@Mixin(RenderSectionRegion.class)
public class SectionCompilerMixin {
	@Inject(method = "getBlockState", at = @At("RETURN"), cancellable = true)
	private void mcdota$dotaBlocksAreAir(BlockPos pos, CallbackInfoReturnable<BlockState> cir) {
		if (Hybrid.drawnByDota(cir.getReturnValue(), pos)) cir.setReturnValue(Blocks.AIR.defaultBlockState());
	}
}

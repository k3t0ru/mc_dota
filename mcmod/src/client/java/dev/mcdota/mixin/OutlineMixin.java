package dev.mcdota.mixin;

import net.minecraft.client.Camera;
import net.minecraft.client.Minecraft;
import net.minecraft.client.renderer.LevelRenderer;
import net.minecraft.client.renderer.state.LevelRenderState;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.state.BlockState;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// The see-through ground (magenta podzol / slabs) gets no selection outline: it would float over Dota's terrain.
@Mixin(LevelRenderer.class)
public class OutlineMixin {
	@Inject(method = "extractBlockOutline", at = @At("TAIL"))
	private void mcdota$noOutlineOnGround(Camera camera, LevelRenderState state, CallbackInfo ci) {
		if (state.blockOutlineRenderState == null || Minecraft.getInstance().level == null) return;
		BlockState b = Minecraft.getInstance().level.getBlockState(state.blockOutlineRenderState.pos());
		if (b.is(Blocks.PODZOL) || b.is(Blocks.MUD_BRICK_SLAB)) state.blockOutlineRenderState = null;
	}
}

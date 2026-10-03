package dev.mcdota.mixin;

import net.minecraft.client.renderer.entity.EntityRenderer;
import net.minecraft.client.renderer.entity.state.EntityRenderState;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.player.Player;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// A burning Dota unit: its invisible stand-in burns like a Minecraft mob, flames over its whole (big) body, which
// covered creeps from head to toe. Up to the waist: the flame is sized by the bounding box
// (FlameFeatureRenderer: one 1.4 x width tall layer per 0.45 of height), so a stand-in's flame gets a short, narrow box.
@Mixin(EntityRenderer.class)
public class FlameMixin {
	@Inject(method = "extractRenderState", at = @At("TAIL"))
	private void mcdota$feetOnly(Entity entity, EntityRenderState state, float partialTick, CallbackInfo ci) {
		if (state.displayFireAnimation && entity.isInvisible() && !(entity instanceof Player)) {
			state.boundingBoxWidth = Math.min(state.boundingBoxWidth, 0.6f); // one layer 1.2 tall: up to a creep's waist
			state.boundingBoxHeight = 0.01f;
		}
	}
}

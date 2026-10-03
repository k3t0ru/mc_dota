package dev.mcdota.mixin;

import net.minecraft.client.renderer.entity.LivingEntityRenderer;
import net.minecraft.client.renderer.entity.state.LivingEntityRenderState;
import net.minecraft.world.entity.EntityType;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// Dota units' stand-ins are husks (nothing else in this world is: mob spawning is off), summoned invisible. For the
// first frames after one appears the client doesn't know about the effect yet and drew a husk in the air now and then.
// Never draw a husk's body (its flames still show: FlameMixin).
@Mixin(LivingEntityRenderer.class)
public class StandInMixin {
	@Inject(method = "extractRenderState(Lnet/minecraft/world/entity/LivingEntity;Lnet/minecraft/client/renderer/entity/state/LivingEntityRenderState;F)V", at = @At("TAIL"))
	private void mcdota$hideStandIn(LivingEntity entity, LivingEntityRenderState state, float partialTick, CallbackInfo ci) {
		if (entity.getType() == EntityType.HUSK) {
			state.isInvisible = true;
			state.isInvisibleToPlayer = true;
		}
	}
}

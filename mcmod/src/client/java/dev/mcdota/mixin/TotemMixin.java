package dev.mcdota.mixin;

import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.damagesource.DamageSource;
import net.minecraft.world.entity.LivingEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// The totem of undying is Roshan's Aegis here (only he drops it): when it saves Steve he comes back whole, like a
// reincarnation, with full health and a full stomach instead of vanilla's half heart and a few effects.
@Mixin(LivingEntity.class)
public class TotemMixin {
	@Inject(method = "checkTotemDeathProtection", at = @At("RETURN"))
	private void mcdota$aegis(DamageSource source, CallbackInfoReturnable<Boolean> cir) {
		if (!cir.getReturnValue() || !((Object) this instanceof ServerPlayer player)) return;
		player.setHealth(player.getMaxHealth());
		player.getFoodData().setFoodLevel(20);
		player.getFoodData().setSaturation(20);
	}
}

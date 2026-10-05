package dev.mcdota.mixin;

import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// Dota's disables in Minecraft (Progress.cc): stunned or hexed, Steve can't hit or mine (disarmed: can't hit); stunned or
// hexed, he can't use anything either (eat, drink, place, a firework)
@Mixin(Minecraft.class)
public class DisableMixin {
	@Inject(method = "startAttack", at = @At("HEAD"), cancellable = true)
	private void mcdota$noAttack(CallbackInfoReturnable<Boolean> cir) {
		if (dev.mcdota.Progress.noAttack) cir.setReturnValue(false);
	}

	@Inject(method = "continueAttack", at = @At("HEAD"), cancellable = true)
	private void mcdota$noMining(boolean leftClick, CallbackInfo ci) {
		if (dev.mcdota.Progress.noAttack) ci.cancel();
	}

	// never paused (Esc's menu paused the world: Dota's hits on Steve went nowhere meanwhile)
	@Inject(method = "isPaused", at = @At("HEAD"), cancellable = true)
	private void mcdota$neverPaused(CallbackInfoReturnable<Boolean> cir) {
		cir.setReturnValue(false);
	}

	@Inject(method = "startUseItem", at = @At("HEAD"), cancellable = true)
	private void mcdota$noUse(CallbackInfo ci) {
		if (dev.mcdota.Progress.noUse) ci.cancel();
	}
}

package dev.mcdota.mixin;

import net.minecraft.client.gui.components.toasts.SystemToast;
import net.minecraft.client.gui.components.toasts.Toast;
import net.minecraft.client.gui.components.toasts.ToastManager;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// No pop-ups over the game (advancements, recipes, tutorial hints): only the system's own messages
@Mixin(ToastManager.class)
public class ToastMixin {
	@Inject(method = "addToast", at = @At("HEAD"), cancellable = true)
	private void mcdota$noToasts(Toast toast, CallbackInfo ci) {
		if (!(toast instanceof SystemToast)) ci.cancel();
	}
}

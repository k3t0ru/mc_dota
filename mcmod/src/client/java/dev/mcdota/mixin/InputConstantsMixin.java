package dev.mcdota.mixin;

import com.mojang.blaze3d.platform.InputConstants;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// The window is off-screen, so GLFW can't hold the cursor in it; MouseInput reads the mouse instead.
@Mixin(InputConstants.class)
public class InputConstantsMixin {
	@Inject(method = "grabOrReleaseMouse", at = @At("HEAD"), cancellable = true)
	private static void mcdota$keepCursor(CallbackInfo ci) {
		ci.cancel();
	}
}

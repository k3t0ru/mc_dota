package dev.mcdota.mixin;

import net.minecraft.client.renderer.LevelRenderer;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.ModifyArg;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// No sky, and the frame starts as the colour key, so wherever Minecraft draws nothing, Dota shows through.
@Mixin(LevelRenderer.class)
public class LevelRendererMixin {
	@Inject(method = "addSkyPass", at = @At("HEAD"), cancellable = true)
	private void mcdota$noSky(CallbackInfo ci) {
		ci.cancel();
	}

	// clear to the colour key instead of the fog colour: those pixels become holes in the window
	@ModifyArg(method = "*", at = @At(value = "INVOKE", target = "Lcom/mojang/blaze3d/systems/CommandEncoder;clearColorAndDepthTextures(Lcom/mojang/blaze3d/textures/GpuTexture;ILcom/mojang/blaze3d/textures/GpuTexture;D)V"), index = 1)
	private int mcdota$clearTransparent(int argb) {
		// ponytail: only the frame clear uses the fog colour; other clears (entity outlines) pass 0 and must stay 0
		return argb != 0 ? dev.mcdota.McDotaClient.KEY_ARGB : argb;
	}
}

package dev.mcdota.mixin;

import com.mojang.blaze3d.platform.Window;
import dev.mcdota.McDotaClient;
import org.lwjgl.glfw.GLFW;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// Minecraft's own window is borderless and parked off-screen: it keeps focus and input, while Overlay shows its
// pixels over Dota (GLFW's transparent framebuffer and colour-keyed GL windows both stay opaque on this GPU).
@Mixin(Window.class)
public class WindowMixin {
	@Inject(method = "<init>", at = @At(value = "INVOKE", target = "Lorg/lwjgl/glfw/GLFW;glfwCreateWindow(IILjava/lang/CharSequence;JJ)J", remap = false))
	private void mcdota$hints(CallbackInfo ci) {
		GLFW.glfwWindowHint(GLFW.GLFW_DECORATED, GLFW.GLFW_FALSE);
	}

	@Inject(method = "<init>", at = @At("TAIL"))
	private void mcdota$parkOffscreen(CallbackInfo ci) {
		long handle = ((Window) (Object) this).handle();
		GLFW.glfwSetWindowPos(handle, McDotaClient.OFFSCREEN_X, 0);
	}
}

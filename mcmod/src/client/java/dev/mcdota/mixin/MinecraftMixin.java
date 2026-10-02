package dev.mcdota.mixin;

import com.mojang.blaze3d.opengl.GlStateManager;
import com.mojang.blaze3d.opengl.GlTexture;
import com.mojang.blaze3d.pipeline.RenderTarget;
import dev.mcdota.McDotaClient;
import net.minecraft.client.Minecraft;
import org.lwjgl.opengl.GL30;
import org.lwjgl.system.MemoryUtil;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.nio.ByteBuffer;

// Right before Minecraft presents a frame, read it back and hand it to the overlay window over Dota.
@Mixin(Minecraft.class)
public class MinecraftMixin {
	private static int mcdota$fbo, mcdota$tex = -1;
	private static ByteBuffer mcdota$buf;

	@Inject(method = "runTick", at = @At(value = "INVOKE", target = "Lcom/mojang/blaze3d/pipeline/RenderTarget;blitToScreen()V"))
	private void mcdota$grab(CallbackInfo ci) {
		dev.mcdota.MouseInput.frame((Minecraft) (Object) this);
		long stamp = System.currentTimeMillis(); // this frame's id: Dota shows the pose with this stamp, the overlay this picture
		dev.mcdota.CameraSender.send((Minecraft) (Object) this, stamp);
		if (McDotaClient.overlay == null) return;
		RenderTarget rt = ((Minecraft) (Object) this).getMainRenderTarget();
		int w = rt.width, h = rt.height, tex = ((GlTexture) rt.getColorTexture()).glId();
		if (mcdota$fbo == 0) mcdota$fbo = GlStateManager.glGenFramebuffers();
		if (mcdota$buf == null || mcdota$buf.capacity() != w * h * 4) mcdota$buf = MemoryUtil.memAlloc(w * h * 4);
		// ponytail: synchronous glReadPixels stalls the GPU a bit; switch to a PBO ring if FPS suffers
		GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, mcdota$fbo);
		if (tex != mcdota$tex) {
			GlStateManager._glFramebufferTexture2D(GL30.GL_READ_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0, GL30.GL_TEXTURE_2D, tex, 0);
			mcdota$tex = tex;
		}
		GlStateManager._readPixels(0, 0, w, h, GL30.GL_BGRA, GL30.GL_UNSIGNED_BYTE, MemoryUtil.memAddress(mcdota$buf));
		GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, 0);
		McDotaClient.overlay.submit(mcdota$buf, w, h, stamp);
	}
}

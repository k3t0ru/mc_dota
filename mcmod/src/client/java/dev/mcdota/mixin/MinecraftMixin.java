package dev.mcdota.mixin;

import com.mojang.blaze3d.opengl.GlStateManager;
import com.mojang.blaze3d.opengl.GlTexture;
import com.mojang.blaze3d.pipeline.RenderTarget;
import dev.mcdota.McDotaClient;
import net.minecraft.client.Minecraft;
import org.lwjgl.opengl.GL11;
import org.lwjgl.opengl.GL15;
import org.lwjgl.opengl.GL21;
import org.lwjgl.opengl.GL30;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

import java.nio.ByteBuffer;

// Right before Minecraft presents a frame, read it back and hand it to the overlay window over Dota.
@Mixin(Minecraft.class)
public class MinecraftMixin {
	private static int mcdota$fbo, mcdota$tex = -1;
	private static final int[] mcdota$pbo = new int[2];
	private static int mcdota$pboSize, mcdota$next;
	private static boolean mcdota$filled;
	private static double mcdota$pboStamp;

	private static double mcdota$stamp; // wall-clock ms with a fraction (Panorama compares it to Date.now)
	private static final double mcdota$clock = System.currentTimeMillis() - System.nanoTime() / 1e6;

	// The cursor is read right before Minecraft turns the player with it, in the same frame, and the frame is stamped
	// at that moment (the partial tick that places the player was taken a moment earlier). Reading it at the end of
	// the frame instead (where the picture is grabbed) put each turn one frame late against its stamp: with uneven
	// frame times the turn per stamped millisecond varied by 30% even for a perfectly steady mouse, and Dota's
	// interpolation showed exactly that as jerks.
	@Inject(method = "runTick", at = @At(value = "INVOKE", target = "Lnet/minecraft/client/MouseHandler;handleAccumulatedMovement()V"))
	private void mcdota$mouse(CallbackInfo ci) {
		dev.mcdota.MouseInput.frame((Minecraft) (Object) this);
		mcdota$stamp = System.nanoTime() / 1e6 + mcdota$clock;
	}

	@Inject(method = "runTick", at = @At(value = "INVOKE", target = "Lcom/mojang/blaze3d/pipeline/RenderTarget;blitToScreen()V"))
	private void mcdota$grab(CallbackInfo ci) {
		double stamp = mcdota$stamp; // this frame's id: Dota shows the pose with this stamp, the overlay this picture
		dev.mcdota.CameraSender.send((Minecraft) (Object) this, stamp);
		if (McDotaClient.overlay == null) return;
		RenderTarget rt = ((Minecraft) (Object) this).getMainRenderTarget();
		int w = rt.width, h = rt.height, tex = ((GlTexture) rt.getColorTexture()).glId();
		if (mcdota$fbo == 0) mcdota$fbo = GlStateManager.glGenFramebuffers();
		// Read back through two pixel-pack buffers: this frame's copy runs on the GPU while the previous frame's (done
		// by now) goes to the overlay. A plain glReadPixels waited for the GPU every frame, and Dota, sharing the video
		// card, lost frames to it. The picture is one frame older; the overlay waits ~80 ms for Dota anyway.
		int size = w * h * 4;
		if (mcdota$pbo[0] == 0 || mcdota$pboSize != size) {
			for (int i = 0; i < 2; i++) {
				if (mcdota$pbo[i] == 0) mcdota$pbo[i] = GL15.glGenBuffers();
				GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, mcdota$pbo[i]);
				GL15.glBufferData(GL21.GL_PIXEL_PACK_BUFFER, size, GL15.GL_STREAM_READ);
			}
			mcdota$pboSize = size;
			mcdota$filled = false;
		}
		GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, mcdota$fbo);
		if (tex != mcdota$tex) {
			GlStateManager._glFramebufferTexture2D(GL30.GL_READ_FRAMEBUFFER, GL30.GL_COLOR_ATTACHMENT0, GL30.GL_TEXTURE_2D, tex, 0);
			mcdota$tex = tex;
		}
		GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, mcdota$pbo[mcdota$next]);
		GL11.glReadPixels(0, 0, w, h, GL30.GL_BGRA, GL30.GL_UNSIGNED_BYTE, 0L); // into the buffer, asynchronously
		GlStateManager._glBindFramebuffer(GL30.GL_READ_FRAMEBUFFER, 0);
		double prevStamp = mcdota$pboStamp;
		mcdota$pboStamp = stamp;
		int prev = 1 - mcdota$next;
		mcdota$next = prev;
		if (mcdota$filled) {
			GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, mcdota$pbo[prev]);
			ByteBuffer px = GL15.glMapBuffer(GL21.GL_PIXEL_PACK_BUFFER, GL15.GL_READ_ONLY, size, null);
			if (px != null) {
				McDotaClient.overlay.submit(px, w, h, (long) prevStamp);
				GL15.glUnmapBuffer(GL21.GL_PIXEL_PACK_BUFFER);
			}
		}
		mcdota$filled = true;
		GL15.glBindBuffer(GL21.GL_PIXEL_PACK_BUFFER, 0);
	}
}

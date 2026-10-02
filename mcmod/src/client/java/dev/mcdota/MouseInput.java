package dev.mcdota;

import com.mojang.blaze3d.platform.InputConstants;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef.POINT;
import dev.mcdota.mixin.MouseHandlerAccessor;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;

// Mouse for an off-screen Minecraft: look = cursor offset from the centre of Dota's window (re-centred every frame),
// buttons = the real mouse buttons fed to Minecraft's key mappings (break, place, attack, pick).
public final class MouseInput {
	private static final int[] VK = { 0x01, 0x02, 0x04 }; // left, right, middle -> GLFW mouse buttons 0, 1, 2
	private static final boolean[] down = new boolean[3];
	private static boolean wasPlaying; // first frame after (re)gaining control only re-centres
	private static final POINT anchor = new POINT(); // where the cursor really landed after re-centring (DPI-proof)

	// Dota's camera can't look above the horizon (negative pitch shows the ground), so neither can Steve
	public static final float MIN_PITCH = 3; // same as MIN_PITCH in bridge.py

	public static void frame(Minecraft mc) {
		if (mc.player != null && mc.player.getXRot() < MIN_PITCH) mc.player.setXRot(MIN_PITCH);
		Overlay o = McDotaClient.overlay;
		boolean playing = o != null && o.cx != 0 && mc.isWindowActive() && mc.screen == null && mc.mouseHandler.isMouseGrabbed();
		User32 u = User32.INSTANCE;
		if (playing) {
			POINT p = new POINT();
			u.GetCursorPos(p);
			if (wasPlaying) {
				MouseHandlerAccessor m = (MouseHandlerAccessor) mc.mouseHandler;
				m.mcdota$setDX(m.mcdota$getDX() + p.x - anchor.x);
				m.mcdota$setDY(m.mcdota$getDY() + p.y - anchor.y);
			}
			u.SetCursorPos(o.cx, o.cy);
			u.GetCursorPos(anchor);
		}
		wasPlaying = playing;
		for (int b = 0; b < 3; b++) {
			boolean now = playing && (u.GetAsyncKeyState(VK[b]) & 0x8000) != 0;
			if (now != down[b]) {
				InputConstants.Key key = InputConstants.Type.MOUSE.getOrCreate(b);
				KeyMapping.set(key, now);
				if (now) KeyMapping.click(key);
				down[b] = now;
			}
		}
	}
}

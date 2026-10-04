package dev.mcdota;

import com.mojang.blaze3d.platform.InputConstants;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef.POINT;
import dev.mcdota.mixin.MouseHandlerAccessor;
import dev.mcdota.mixin.MouseHandlerInvoker;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;

// Mouse for an off-screen Minecraft: look = cursor offset from the centre of Dota's window (re-centred every frame),
// buttons = the real mouse buttons fed to Minecraft's key mappings (break, place, attack, pick).
public final class MouseInput {
	// a menu is open: the cursor over Dota's window maps to Minecraft's (same size, maybe offset/scaled)
	private static void menuMouse(Minecraft mc, Overlay ov) {
		User32 u = User32.INSTANCE;
		POINT p = new POINT();
		u.GetCursorPos(p);
		if (p.x < ov.x || p.y < ov.y || p.x >= ov.x + ov.w || p.y >= ov.y + ov.h) return; // only over Dota's window
		long win = mc.getWindow().handle();
		MouseHandlerInvoker m = (MouseHandlerInvoker) mc.mouseHandler;
		m.mcdota$move(win, (p.x - ov.x) * (double) mc.getWindow().getWidth() / ov.w, (p.y - ov.y) * (double) mc.getWindow().getHeight() / ov.h);
		for (int b = 0; b < 3; b++) {
			boolean now = (u.GetAsyncKeyState(VK[b]) & 0x8000) != 0;
			if (now != menuDown[b]) {
				int mods = ((u.GetAsyncKeyState(0x10) & 0x8000) != 0 ? 1 : 0) | ((u.GetAsyncKeyState(0x11) & 0x8000) != 0 ? 2 : 0)
					| ((u.GetAsyncKeyState(0x12) & 0x8000) != 0 ? 4 : 0); // (GLFW_MOD_SHIFT, _CONTROL, _ALT)
				m.mcdota$button(win, new net.minecraft.client.input.MouseButtonInfo(b, mods), now ? 1 : 0);
			}
			menuDown[b] = now;
		}
	}

	private static final int[] VK = { 0x01, 0x02, 0x04 }; // left, right, middle -> GLFW mouse buttons 0, 1, 2
	private static final boolean[] down = new boolean[3];
	private static boolean wasPlaying; // first frame after (re)gaining control only re-centres

	// how far up Steve can look: as far as Dota's camera (bridge.py's MIN_PITCH: a pitch of 360 - x looks up in Dota)
	public static final float MIN_PITCH = System.getenv("MCDOTA_MIN_PITCH") != null
		? Float.parseFloat(System.getenv("MCDOTA_MIN_PITCH")) : -89;
	private static final boolean[] menuDown = new boolean[3];

	public static void frame(Minecraft mc) {
		if (mc.player != null && mc.player.getXRot() < MIN_PITCH) mc.player.setXRot(MIN_PITCH);
		Overlay ov = McDotaClient.overlay;
		if (ov != null) ov.showCursor = mc.screen != null;
		if (ov != null && ov.w > 0 && mc.screen != null) menuMouse(mc, ov);
		Overlay o = McDotaClient.overlay;
		boolean playing = o != null && o.cx != 0 && mc.isWindowActive() && mc.screen == null && mc.mouseHandler.isMouseGrabbed();
		User32 u = User32.INSTANCE;
		if (playing) MouseWheel.captureAt = System.nanoTime();
		if (playing) { // the mouse hook (MouseWheel) adds up the moves and keeps the cursor still
			if (!wasPlaying) { // (re)gaining control: cursor to Dota's centre, moves from now on are ours
				u.SetCursorPos(o.cx, o.cy);
				MouseWheel.takeMove();
				MouseWheel.capture = true;
			} else {
				int[] d = MouseWheel.takeMove();
				MouseHandlerAccessor m = (MouseHandlerAccessor) mc.mouseHandler;
				m.mcdota$setDX(m.mcdota$getDX() + d[0]);
				m.mcdota$setDY(m.mcdota$getDY() + d[1]);
			}
		} else MouseWheel.capture = false;
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

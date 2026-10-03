package dev.mcdota;

import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef;
import com.sun.jna.platform.win32.WinUser;
import net.minecraft.client.Minecraft;

// The mouse wheel: Windows hands it to the window under the cursor, which is Dota's (Minecraft's own window sits off
// screen) and Dota ignores input while it isn't in front, so the wheel did nothing at all. A low-level mouse hook
// catches it for the whole system: while Minecraft is in front and in the game (no menu), it switches the hotbar slot
// like Minecraft's own scrolling, and Dota never sees it.
public final class MouseWheel {
	private static volatile int pending; // notches waiting for the client thread (+ = wheel up)

	public static void start() {
		Thread t = new Thread(() -> {
			User32 u = User32.INSTANCE;
			WinUser.LowLevelMouseProc proc = (code, wParam, info) -> {
				if (code >= 0 && wParam.intValue() == 0x020A && playing()) { // WM_MOUSEWHEEL
					pending += (short) (info.mouseData >> 16) / 120;
					return new WinDef.LRESULT(1); // swallowed
				}
				return u.CallNextHookEx(null, code, wParam, new WinDef.LPARAM(com.sun.jna.Pointer.nativeValue(info.getPointer())));
			};
			WinUser.HHOOK hook = u.SetWindowsHookEx(WinUser.WH_MOUSE_LL, proc, Kernel32.INSTANCE.GetModuleHandle(null), 0);
			WinUser.MSG msg = new WinUser.MSG();
			while (u.GetMessage(msg, null, 0, 0) > 0) { // low-level hooks are called through this thread's message loop
				u.TranslateMessage(msg);
				u.DispatchMessage(msg);
			}
			u.UnhookWindowsHookEx(hook);
		}, "mcdota-wheel");
		t.setDaemon(true);
		t.start();
	}

	private static boolean playing() {
		Minecraft mc = Minecraft.getInstance();
		return mc.player != null && mc.screen == null && mc.isWindowActive();
	}

	// client thread, every tick: like Minecraft's own scroll, wheel up = the previous slot
	public static void tick(Minecraft mc) {
		int n = pending;
		if (n == 0 || mc.player == null) return;
		pending -= n;
		var inv = mc.player.getInventory();
		inv.setSelectedSlot(Math.floorMod(inv.getSelectedSlot() - n, 9));
	}
}

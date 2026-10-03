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
// The same hook takes the mouse's movement while in the game (MouseInput.capture): every move is added up exactly and
// swallowed, so the cursor stays put at Dota's centre and each frame takes what moved since the last one. (Reading
// the cursor every frame and putting it back raced with moves arriving in between: some frames got two frames' worth
// of turning, the next one little, and Dota's camera showed it as jerks.)
public final class MouseWheel {
	private static volatile int pending; // notches waiting for the client thread (+ = wheel up)
	static volatile boolean capture; // in the game: moves are ours
	static volatile long captureAt; // the client thread renews it every frame: a hung Minecraft must not freeze the mouse
	private static long moveX, moveY; // added up since the last take (guarded by MouseWheel.class)

	// client thread: what the mouse moved since the last call
	static synchronized int[] takeMove() {
		int[] d = { (int) moveX, (int) moveY };
		moveX = moveY = 0;
		return d;
	}

	private static synchronized void addMove(int dx, int dy) { moveX += dx; moveY += dy; }

	public static void start() {
		Thread t = new Thread(() -> {
			User32 u = User32.INSTANCE;
			WinUser.LowLevelMouseProc proc = (code, wParam, info) -> {
				if (code >= 0 && wParam.intValue() == 0x020A && playing()) { // WM_MOUSEWHEEL
					pending += (short) (info.mouseData >> 16) / 120;
					return new WinDef.LRESULT(1); // swallowed
				}
				if (code >= 0 && wParam.intValue() == 0x020A && inMenu()) { // a menu (the trading list): it scrolls
					menuScroll += (short) (info.mouseData >> 16) / 120.0;
					return new WinDef.LRESULT(1);
				}
				if (code >= 0 && wParam.intValue() == 0x0200 && capture && System.nanoTime() - captureAt < 250_000_000L
					&& McDotaClient.mcHwnd != null && McDotaClient.mcHwnd.equals(u.GetForegroundWindow())) { // WM_MOUSEMOVE, cursor not moved yet
					WinDef.POINT at = new WinDef.POINT();
					u.GetCursorPos(at);
					addMove(info.pt.x - at.x, info.pt.y - at.y);
					return new WinDef.LRESULT(1); // swallowed: the cursor stays where it is
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

	private static volatile double menuScroll;

	private static boolean inMenu() {
		Minecraft mc = Minecraft.getInstance();
		return mc.screen != null && McDotaClient.mcHwnd != null && McDotaClient.mcHwnd.equals(User32.INSTANCE.GetForegroundWindow());
	}

	private static boolean playing() {
		Minecraft mc = Minecraft.getInstance();
		return mc.player != null && mc.screen == null && mc.isWindowActive();
	}

	// client thread, every tick: like Minecraft's own scroll, wheel up = the previous slot
	public static void tick(Minecraft mc) {
		double m = menuScroll;
		if (m != 0) {
			menuScroll -= m;
			((dev.mcdota.mixin.MouseHandlerInvoker) mc.mouseHandler).mcdota$scroll(mc.getWindow().handle(), 0, m);
		}
		int n = pending;
		if (n == 0 || mc.player == null) return;
		pending -= n;
		var inv = mc.player.getInventory();
		inv.setSelectedSlot(Math.floorMod(inv.getSelectedSlot() - n, 9));
	}
}

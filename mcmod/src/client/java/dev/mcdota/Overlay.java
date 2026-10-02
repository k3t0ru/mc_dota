package dev.mcdota;

import com.sun.jna.Pointer;
import com.sun.jna.platform.win32.GDI32;
import com.sun.jna.platform.win32.User32;
import com.sun.jna.platform.win32.WinDef.HBITMAP;
import com.sun.jna.platform.win32.WinDef.HDC;
import com.sun.jna.platform.win32.WinDef.HWND;
import com.sun.jna.platform.win32.WinDef.POINT;
import com.sun.jna.platform.win32.WinDef.RECT;
import com.sun.jna.platform.win32.WinGDI;
import com.sun.jna.platform.win32.WinUser;
import com.sun.jna.ptr.PointerByReference;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

// An always-on-top, per-pixel-alpha window lying exactly over Dota's window, showing Minecraft's frame scaled up
// (nearest) to Dota's size. Near-magenta pixels (the cleared sky) become holes Dota shows through. Holes keep alpha 1
// so clicks still land here, not in Dota (alpha 0 is click-through). The overlay never takes focus, and if Dota gets
// it, it goes back to Minecraft's off-screen window: all keyboard input is Minecraft's, the mouse goes via MouseInput.
public final class Overlay implements Runnable {
	interface Keys extends com.sun.jna.Library { // not in jna-platform's User32
		Keys INSTANCE = com.sun.jna.Native.load("user32", Keys.class);
		void keybd_event(byte vk, byte scan, int flags, int extra);
		Pointer SetClassLongPtrW(HWND hwnd, int index, Pointer value);
		int ShowCursor(boolean show);
		Pointer LoadCursorW(Pointer instance, Pointer name);
	}

	public volatile int cx, cy; // centre of Dota's window on screen (mouse anchor)
	public volatile int x, y, w, h; // Dota's window on screen (menus map the cursor through it)
	public volatile boolean showCursor; // a Minecraft menu is open
	// Dota plays poses back PLAYBACK_MS (fpcam.js, 150) after Minecraft had them, and needs ~1 frame to draw; Minecraft frames are shown
	// DELAY ms late from a small ring buffer: both layers then move together instead of blocks sliding over the map
	private static final int RING = 24;
	private static volatile int delay = Integer.getInteger("mcdota.delay", 0); // live knob: run/mcdota_delay.txt
	private final int[][] ring = new int[RING][];
	private final long[] stamp = new long[RING];
	private int head, lw, lh;
	private long shown; // stamp of the frame on screen

	public Overlay() {
		Thread t = new Thread(this, "mcdota-overlay");
		t.setDaemon(true);
		t.start();
	}

	// render thread: glReadPixels output, BGRA bytes bottom-up
	public void submit(ByteBuffer bgra, int w, int h, long time) {
		synchronized (this) {
			if (ring[head] == null || ring[head].length != w * h) ring[head] = new int[w * h];
			bgra.order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().get(0, ring[head]); // ints are 0xAARRGGBB
			stamp[head] = time;
			head = (head + 1) % RING;
			lw = w; lh = h;
		}
	}

	// magenta = hole. Besides the cleared sky, the floor (bedrock) and the stand-ins of Dota units are textured pure
	// magenta, so they cut holes too: Dota's terrain and units show through and hide Minecraft blocks behind them.
	// Tolerance covers face shading, ambient occlusion and the vignette.
	private static boolean hole(int p) {
		int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
		return r > 30 && b > 30 && g * 3 < r && Math.abs(r - b) <= Math.max(24, r / 4);
	}

	// translucent GUI (hotbar, chat) blended over the magenta clear comes out pink: show it as plain grey instead
	private static int unpink(int p) {
		int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
		if (r - g > 40 && b - g > 30 && Math.abs(r - b) < 40) return (g << 16) | (g << 8) | g; // ponytail: real purples get greyed too
		return p;
	}

	@Override
	public void run() {
		User32 u = User32.INSTANCE;
		int ex = WinUser.WS_EX_LAYERED | 0x08 /* TOPMOST */ | 0x80 /* TOOLWINDOW */ | 0x08000000 /* NOACTIVATE */;
		HWND hwnd = u.CreateWindowEx(ex, "STATIC", "mcdota overlay", WinUser.WS_POPUP | WinUser.WS_VISIBLE, 0, 0, 1, 1, null, null, null, null);
		Keys.INSTANCE.SetClassLongPtrW(hwnd, -12 /* GCLP_HCURSOR */, null); // no Windows cursor over the picture (Minecraft has a crosshair)
		Keys.INSTANCE.ShowCursor(false);
		HDC mem = GDI32.INSTANCE.CreateCompatibleDC(u.GetDC(null));
		WinUser.BLENDFUNCTION blend = new WinUser.BLENDFUNCTION();
		blend.BlendOp = WinUser.AC_SRC_OVER;
		blend.SourceConstantAlpha = (byte) 255;
		blend.AlphaFormat = WinUser.AC_SRC_ALPHA;
		WinUser.MSG msg = new WinUser.MSG();

		int W = 0, H = 0, X = 0, Y = 0, sw = 0, sh = 0;
		int[] src = new int[0], dst = new int[0], xmap = new int[0], ymap = new int[0];
		Pointer bits = null;
		HWND dota = null;
		long lastFind = 0, lastLog = System.currentTimeMillis();
		boolean cursorShown = false;
		int frames = 0;

		while (true) {
			boolean clicked = false; // a click on the picture means "I'm playing": keyboard goes to Minecraft
			while (u.PeekMessage(msg, null, 0, 0, 1)) {
				if (msg.message == 0x0201 || msg.message == 0x0204 || msg.message == 0x0207) clicked = true; // L/R/M button down
				u.TranslateMessage(msg);
				u.DispatchMessage(msg);
			}
			if (showCursor != cursorShown) { // arrow over the picture only while a menu is open
				cursorShown = showCursor;
				Keys.INSTANCE.SetClassLongPtrW(hwnd, -12, cursorShown ? Keys.INSTANCE.LoadCursorW(null, new Pointer(32512)) : null);
				Keys.INSTANCE.ShowCursor(cursorShown);
			}
			HWND fg = u.GetForegroundWindow(); // Dota is only the picture: focus always goes back to Minecraft
			// a mouse press over Dota's window also counts (the overlay's STATIC window doesn't always get the message)
			POINT cur = new POINT();
			u.GetCursorPos(cur);
			boolean pressed = (u.GetAsyncKeyState(0x01) & 0x8000) != 0 || (u.GetAsyncKeyState(0x02) & 0x8000) != 0;
			if (pressed && W > 0 && cur.x >= X && cur.x < X + W && cur.y >= Y && cur.y < Y + H) clicked = true;
			if (McDotaClient.mcHwnd != null && !McDotaClient.mcHwnd.equals(fg) && (clicked || hwnd.equals(fg) || (dota != null && dota.equals(fg)))) {
				// Windows refuses SetForegroundWindow from a background process; a synthetic Alt tap lifts that lock
				Keys.INSTANCE.keybd_event((byte) 0x12, (byte) 0, 0, 0);
				Keys.INSTANCE.keybd_event((byte) 0x12, (byte) 0, 2, 0);
				u.SetForegroundWindow(McDotaClient.mcHwnd);
			}
			long now = System.currentTimeMillis();
			if (now - lastLog >= 5000) {
				org.slf4j.LoggerFactory.getLogger("mcdota").info("overlay {} fps, minecraft {} fps, size {}x{} -> {}x{}, delay {} ms",
					frames * 1000 / (now - lastLog), net.minecraft.client.Minecraft.getInstance().getFps(), lw, lh, W, H, delay);
				frames = 0;
				lastLog = now;
			}
			if (now - lastFind > 1000) { // follow Dota's window
				lastFind = now;
				try {
					delay = Integer.parseInt(java.nio.file.Files.readString(java.nio.file.Path.of("mcdota_delay.txt")).trim());
				} catch (Exception ignored) { // no file: keep the default
				}
				dota = u.FindWindow(null, "Dota 2");
				RECT r = new RECT();
				if (dota != null && u.GetWindowRect(dota, r)) {
					if (r.right - r.left != W || r.bottom - r.top != H) {
						W = r.right - r.left; H = r.bottom - r.top;
						WinGDI.BITMAPINFO bi = new WinGDI.BITMAPINFO();
						bi.bmiHeader.biWidth = W;
						bi.bmiHeader.biHeight = H; // bottom-up, like glReadPixels
						bi.bmiHeader.biPlanes = 1;
						bi.bmiHeader.biBitCount = 32;
						bi.bmiHeader.biCompression = WinGDI.BI_RGB;
						PointerByReference pb = new PointerByReference();
						HBITMAP dib = GDI32.INSTANCE.CreateDIBSection(mem, bi, WinGDI.DIB_RGB_COLORS, pb, null, 0);
						GDI32.INSTANCE.DeleteObject(GDI32.INSTANCE.SelectObject(mem, dib));
						bits = pb.getValue();
						dst = new int[W * H];
						sw = 0; // rebuild maps
					}
					X = r.left; Y = r.top;
					cx = X + W / 2; cy = Y + H / 2;
					x = X; y = Y; w = W; h = H;
				}
			}

			boolean have = false;
			synchronized (this) {
				int pick = -1; // newest frame that is at least DELAY old
				for (int i = 0; i < RING; i++)
					if (stamp[i] != 0 && stamp[i] <= now - delay && (pick < 0 || stamp[i] > stamp[pick])) pick = i;
				if (pick >= 0 && stamp[pick] != shown && W > 0 && ring[pick].length == lw * lh) {
					have = true;
					shown = stamp[pick];
					int[] latest = ring[pick];
					if (src.length != latest.length) src = new int[latest.length];
					System.arraycopy(latest, 0, src, 0, latest.length);
					if (lw != sw || lh != sh) {
						sw = lw; sh = lh;
						xmap = new int[W]; ymap = new int[H];
						for (int x = 0; x < W; x++) xmap[x] = (int) ((long) x * sw / W);
						for (int y = 0; y < H; y++) ymap[y] = (int) ((long) y * sh / H) * sw;
					}
				}
			}
			if (have) {
				for (int i = 0; i < src.length; i++) src[i] = hole(src[i]) ? 0x01000000 : unpink(src[i]) | 0xFF000000; // premultiplied; alpha 1 = invisible but clickable
				for (int y = 0, o = 0; y < H; y++) {
					int row = ymap[y];
					for (int x = 0; x < W; x++) dst[o++] = src[row + xmap[x]];
				}
				bits.write(0, dst, 0, dst.length);
				u.UpdateLayeredWindow(hwnd, null, new POINT(X, Y), new WinUser.SIZE(W, H), mem, new POINT(0, 0), 0, blend, WinUser.ULW_ALPHA);
				frames++;
			}
			try { Thread.sleep(2); } catch (InterruptedException e) { return; }
		}
	}
}

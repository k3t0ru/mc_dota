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

// A click-through, always-on-top, per-pixel-alpha window lying exactly over Dota's window, showing Minecraft's
// frame scaled up (nearest) to Dota's size. Near-magenta pixels (the cleared sky) become holes Dota shows through.
public final class Overlay implements Runnable {
	private int[] latest = new int[0];
	private int lw, lh;
	private boolean fresh;

	public Overlay() {
		Thread t = new Thread(this, "mcdota-overlay");
		t.setDaemon(true);
		t.start();
	}

	// render thread: glReadPixels output, BGRA bytes bottom-up
	public void submit(ByteBuffer bgra, int w, int h) {
		synchronized (this) {
			if (latest.length != w * h) latest = new int[w * h];
			bgra.order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().get(0, latest); // ints are 0xAARRGGBB
			lw = w; lh = h; fresh = true;
		}
	}

	private static boolean hole(int p) { // magenta key with tolerance for Minecraft's vignette
		int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
		return r > 200 && b > 200 && g < 40 && Math.abs(r - b) < 16;
	}

	@Override
	public void run() {
		User32 u = User32.INSTANCE;
		int ex = WinUser.WS_EX_LAYERED | WinUser.WS_EX_TRANSPARENT | 0x08 /* TOPMOST */ | 0x80 /* TOOLWINDOW */ | 0x08000000 /* NOACTIVATE */;
		HWND hwnd = u.CreateWindowEx(ex, "STATIC", "mcdota overlay", WinUser.WS_POPUP | WinUser.WS_VISIBLE, 0, 0, 1, 1, null, null, null, null);
		HDC mem = GDI32.INSTANCE.CreateCompatibleDC(u.GetDC(null));
		WinUser.BLENDFUNCTION blend = new WinUser.BLENDFUNCTION();
		blend.BlendOp = WinUser.AC_SRC_OVER;
		blend.SourceConstantAlpha = (byte) 255;
		blend.AlphaFormat = WinUser.AC_SRC_ALPHA;
		WinUser.MSG msg = new WinUser.MSG();

		int W = 0, H = 0, X = 0, Y = 0, sw = 0, sh = 0;
		int[] src = new int[0], dst = new int[0], xmap = new int[0], ymap = new int[0];
		Pointer bits = null;
		long lastFind = 0;

		while (true) {
			while (u.PeekMessage(msg, null, 0, 0, 1)) { u.TranslateMessage(msg); u.DispatchMessage(msg); }
			long now = System.currentTimeMillis();
			if (now - lastFind > 1000) { // follow Dota's window
				lastFind = now;
				HWND dota = u.FindWindow(null, "Dota 2");
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
				}
			}

			boolean have;
			synchronized (this) {
				have = fresh && W > 0;
				if (have) {
					if (src.length != latest.length) src = new int[latest.length];
					System.arraycopy(latest, 0, src, 0, latest.length);
					if (lw != sw || lh != sh) {
						sw = lw; sh = lh;
						xmap = new int[W]; ymap = new int[H];
						for (int x = 0; x < W; x++) xmap[x] = (int) ((long) x * sw / W);
						for (int y = 0; y < H; y++) ymap[y] = (int) ((long) y * sh / H) * sw;
					}
					fresh = false;
				}
			}
			if (have) {
				for (int i = 0; i < src.length; i++) src[i] = hole(src[i]) ? 0 : src[i] | 0xFF000000; // premultiplied
				for (int y = 0, o = 0; y < H; y++) {
					int row = ymap[y];
					for (int x = 0; x < W; x++) dst[o++] = src[row + xmap[x]];
				}
				bits.write(0, dst, 0, dst.length);
				u.UpdateLayeredWindow(hwnd, null, new POINT(X, Y), new WinUser.SIZE(W, H), mem, new POINT(0, 0), 0, blend, WinUser.ULW_ALPHA);
			}
			try { Thread.sleep(2); } catch (InterruptedException e) { return; }
		}
	}
}

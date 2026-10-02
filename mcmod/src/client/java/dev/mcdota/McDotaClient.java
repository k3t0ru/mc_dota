package dev.mcdota;

import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientLifecycleEvents;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.networking.v1.ClientPlayConnectionEvents;
import org.lwjgl.glfw.GLFW;
import net.minecraft.client.CloudStatus;

public class McDotaClient implements ClientModInitializer {
	// colour of the see-through holes (Minecraft clears its frame to it); magenta never shows up in vanilla terrain
	public static final int KEY_ARGB = 0xFFFF00FF;
	public static final int OFFSCREEN_X = -20000;
	public static Overlay overlay;
	public static com.sun.jna.platform.win32.WinDef.HWND mcHwnd; // Minecraft's own (off-screen) window

	// Minecraft's render size; the overlay scales it up to whatever size Dota's window is (-Dmcdota.size=WxH)
	public static int[] renderSize() {
		String[] p = System.getProperty("mcdota.size", "1920x1080").split("x");
		return new int[] { Integer.parseInt(p[0].trim()), Integer.parseInt(p[1].trim()) };
	}

	@Override
	public void onInitializeClient() {
		ClientLifecycleEvents.CLIENT_STARTED.register(mc -> {
			mc.options.cloudStatus().set(CloudStatus.OFF);
			int[] r = renderSize(); // resizing inside Window's constructor crashes, so do it once the client is up
			GLFW.glfwSetWindowSize(mc.getWindow().handle(), r[0], r[1]);
			GLFW.glfwSetWindowPos(mc.getWindow().handle(), OFFSCREEN_X, 0);
			mcHwnd = new com.sun.jna.platform.win32.WinDef.HWND(new com.sun.jna.Pointer(
				org.lwjgl.glfw.GLFWNativeWin32.glfwGetWin32Window(mc.getWindow().handle())));
			overlay = new Overlay();
		});
		ClientPlayConnectionEvents.JOIN.register((handler, sender, mc) -> Arena.ensure(mc));
		// clicks land on the overlay, never in Minecraft's window, so grab the mouse ourselves once focus arrives
		ClientTickEvents.END_CLIENT_TICK.register(mc -> {
			if (mc.isWindowActive() && mc.screen == null && mc.level != null && !mc.mouseHandler.isMouseGrabbed()) mc.mouseHandler.grabMouse();
		});
	}
}

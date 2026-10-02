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
	// measured with Game.WorldToScreen at 1600x900: focal 692 px = 66 degrees vertical (Minecraft fov is vertical)
	public static final int FOV = Integer.getInteger("mcdota.fov", 66);
	public static Overlay overlay;
	public static com.sun.jna.platform.win32.WinDef.HWND mcHwnd; // Minecraft's own (off-screen) window

	// Minecraft's render size; the overlay scales it up to whatever size Dota's window is (-Dmcdota.size=WxH)
	public static int[] renderSize() {
		String[] p = System.getProperty("mcdota.size", "1600x900").split("x");
		return new int[] { Integer.parseInt(p[0].trim()), Integer.parseInt(p[1].trim()) };
	}

	@Override
	public void onInitializeClient() {
		ClientLifecycleEvents.CLIENT_STARTED.register(mc -> {
			mc.options.cloudStatus().set(CloudStatus.OFF);
			if (net.minecraft.client.renderer.fog.FogRenderer.toggleFog()) net.minecraft.client.renderer.fog.FogRenderer.toggleFog(); // off: fog tints the magenta floor
			mc.options.fov().set(FOV); // must match Dota's camera (dota_camera_fov_min/max in tools/dev_launch.sh)
			mc.options.fovEffectScale().set(0.0); // no sprint/speed zoom: Dota's FOV never changes
			mc.options.damageTiltStrength().set(0.0); // a hurt camera tilt would tear Minecraft's layer off Dota's
			mc.options.framerateLimit().set(30); // same pace as Dota (fps_max 30): both layers step together
			mc.options.ambientOcclusion().set(false); // shaded corners turn the magenta ground into dark triangles
			mc.options.autoJump().set(true); // the floor follows Dota's terrain in whole-block steps
			mc.options.bobView().set(false); // walking bob shakes only Minecraft's layer, so blocks would swim over the map
			int[] r = renderSize(); // resizing inside Window's constructor crashes, so do it once the client is up
			GLFW.glfwSetWindowSize(mc.getWindow().handle(), r[0], r[1]);
			GLFW.glfwSetWindowPos(mc.getWindow().handle(), OFFSCREEN_X, 0);
			mcHwnd = new com.sun.jna.platform.win32.WinDef.HWND(new com.sun.jna.Pointer(
				org.lwjgl.glfw.GLFWNativeWin32.glfwGetWin32Window(mc.getWindow().handle())));
			overlay = new Overlay();
		});
		ClientPlayConnectionEvents.JOIN.register((handler, sender, mc) -> Arena.ensure(mc));
		net.fabricmc.fabric.api.event.lifecycle.v1.ServerTickEvents.END_SERVER_TICK.register(server -> Sync.buildSome());
		net.fabricmc.fabric.api.event.lifecycle.v1.ServerChunkEvents.CHUNK_LOAD.register((level, chunk) -> {
			if (level.dimension() == net.minecraft.world.level.Level.OVERWORLD) Sync.chunkLoaded(level.getServer(), chunk.getPos().x, chunk.getPos().z);
		});
		// a respawn resets attributes: Steve must keep ignoring Dota's knockback
		net.fabricmc.fabric.api.entity.event.v1.ServerPlayerEvents.AFTER_RESPAWN.register((oldPlayer, newPlayer, alive) ->
			newPlayer.level().getServer().getCommands().performPrefixedCommand(newPlayer.level().getServer().createCommandSourceStack().withSuppressedOutput(),
				"attribute " + newPlayer.getName().getString() + " minecraft:knockback_resistance base set 1"));
		// clicks land on the overlay, never in Minecraft's window, so grab the mouse ourselves once focus arrives
		ClientTickEvents.END_CLIENT_TICK.register(Sync::tick);
		ClientTickEvents.END_CLIENT_TICK.register(mc -> {
			if (mc.isWindowActive() && mc.screen == null && mc.level != null && !mc.mouseHandler.isMouseGrabbed()) mc.mouseHandler.grabMouse();
		});
	}
}

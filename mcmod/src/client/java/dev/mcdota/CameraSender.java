package dev.mcdota;

import net.minecraft.client.Camera;
import net.minecraft.client.Minecraft;
import net.minecraft.world.phys.Vec3;

import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

// Every frame: Minecraft's eye pose "x y z yaw pitch millis" to the bridge (UDP 127.0.0.1:27101), which steers Dota's camera.
public final class CameraSender {
	private static final InetSocketAddress BRIDGE = new InetSocketAddress("127.0.0.1", 27101);
	private static DatagramSocket socket;

	public static void send(Minecraft mc, double stamp) {
		if (mc.level == null) return;
		try {
			if (socket == null) socket = new DatagramSocket();
			Camera cam = mc.gameRenderer.getMainCamera();
			Vec3 p = cam.position();
			byte[] msg = String.format(java.util.Locale.ROOT, "%.3f %.3f %.3f %.2f %.2f %.2f", p.x, p.y, p.z, cam.yRot(), cam.xRot(), stamp)
				.getBytes(StandardCharsets.US_ASCII);
			socket.send(new DatagramPacket(msg, msg.length, BRIDGE));
		} catch (Exception ignored) { // bridge not running: Minecraft just plays on
		}
	}
}

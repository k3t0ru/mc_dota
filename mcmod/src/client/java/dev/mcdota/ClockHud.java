package dev.mcdota;

import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.minecraft.client.Minecraft;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.resources.Identifier;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.item.Items;

// A clock in the inventory (the fletcher sells it) shows Dota's game time, Minecraft style: the clock's icon, the time
// with a shadow, and whether it's Dota's day or night (it decides how far units see). Dota sends "time <s> <day 1/0>".
public final class ClockHud {
	private static volatile int seconds;
	private static volatile boolean day = true, known;

	public static void set(int s, boolean isDay) {
		seconds = s;
		day = isDay;
		known = true;
	}

	public static void register() {
		HudElementRegistry.addLast(Identifier.fromNamespaceAndPath("mcdota", "clock"), (g, tick) -> render(g));
	}

	private static void render(GuiGraphics g) {
		Minecraft mc = Minecraft.getInstance();
		if (!known || mc.player == null || mc.options.hideGui || !mc.player.getInventory().contains(new ItemStack(Items.CLOCK))) return;
		int s = Math.abs(seconds);
		String time = (seconds < 0 ? "-" : "") + (s / 60) + ":" + String.format("%02d", s % 60);
		g.renderItem(new ItemStack(Items.CLOCK), 4, 4);
		g.drawString(mc.font, time, 24, 5, 0xFFFFFFFF, true);
		g.drawString(mc.font, day ? "Day" : "Night", 24, 14, day ? 0xFFFFD84A : 0xFF7FA6FF, true);
	}
}

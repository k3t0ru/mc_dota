package dev.mcdota.mixin;

import net.minecraft.client.gui.Font;
import net.minecraft.client.gui.GuiGraphics;
import net.minecraft.world.item.ItemStack;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

// The spell block's cooldown on the shield's icon (inventory, hotbar), like Minecraft's item cooldowns; the shield itself
// works on meanwhile (Minecraft's own cooldown would have stopped it)
@Mixin(GuiGraphics.class)
public class ShieldCooldownMixin {
	@Inject(method = "renderItemDecorations(Lnet/minecraft/client/gui/Font;Lnet/minecraft/world/item/ItemStack;IILjava/lang/String;)V", at = @At("TAIL"))
	private void mcdota$spellBlockCooldown(Font font, ItemStack stack, int x, int y, String text, CallbackInfo ci) {
		float left = dev.mcdota.Progress.spellBlockLeft(stack);
		if (left <= 0) return;
		int top = y + net.minecraft.util.Mth.floor(16 * (1 - left));
		((GuiGraphics) (Object) this).fill(x, top, x + 16, y + 16, 0x7FFFFFFF);
	}
}

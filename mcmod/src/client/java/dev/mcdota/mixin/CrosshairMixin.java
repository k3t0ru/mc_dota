package dev.mcdota.mixin;

import com.mojang.blaze3d.pipeline.RenderPipeline;
import net.minecraft.client.gui.Gui;
import net.minecraft.client.renderer.RenderPipelines;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

// Minecraft draws the crosshair inverting what's under it; under it is the overlay's magenta, so it came out green.
// Drawn as a plain (white) sprite instead.
@Mixin(Gui.class)
public class CrosshairMixin {
	@Redirect(method = "renderCrosshair", at = @At(value = "FIELD", opcode = org.objectweb.asm.Opcodes.GETSTATIC,
		target = "Lnet/minecraft/client/renderer/RenderPipelines;CROSSHAIR:Lcom/mojang/blaze3d/pipeline/RenderPipeline;"))
	private RenderPipeline mcdota$plainCrosshair() {
		return RenderPipelines.GUI_TEXTURED;
	}
}

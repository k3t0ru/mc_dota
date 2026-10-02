package dev.mcdota.mixin;

import net.minecraft.client.MouseHandler;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;

@Mixin(MouseHandler.class)
public interface MouseHandlerAccessor {
	@Accessor("accumulatedDX") double mcdota$getDX();
	@Accessor("accumulatedDX") void mcdota$setDX(double v);
	@Accessor("accumulatedDY") double mcdota$getDY();
	@Accessor("accumulatedDY") void mcdota$setDY(double v);
}

package dev.mcdota.mixin;

import net.minecraft.world.entity.projectile.FireworkRocketEntity;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.Constant;
import org.spongepowered.asm.mixin.injection.ModifyConstant;

// Elytra and a firework: Minecraft pushes toward 1.5 blocks a tick, too fast over Dota's map: 0.8
@Mixin(FireworkRocketEntity.class)
public class FireworkMixin {
	@ModifyConstant(method = "tick", constant = @Constant(doubleValue = 1.5))
	private double mcdota$slowerBoost(double v) { return 0.8; }
}

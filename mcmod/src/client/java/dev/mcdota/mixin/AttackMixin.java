package dev.mcdota.mixin;

import net.minecraft.client.Minecraft;
import net.minecraft.core.registries.Registries;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.item.enchantment.EnchantmentHelper;
import net.minecraft.world.item.enchantment.Enchantments;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// Melee goes to the Dota unit Dota itself highlights under the crosshair (Panorama reports it), not to whichever
// invisible stand-in Minecraft's crosshair happens to touch: those lag and are shaped differently, so last hits missed.
// Every left click sends the swing's damage, worked out like Minecraft does (attack cooldown, sharpness, crit).
@Mixin(Minecraft.class)
public class AttackMixin {
	@Inject(method = "startAttack", at = @At("HEAD"))
	private void mcdota$swing(CallbackInfoReturnable<Boolean> cir) {
		Minecraft mc = (Minecraft) (Object) this;
		var p = mc.player;
		if (p == null || mc.level == null || p.isSpectator() || mc.screen != null) return;
		float s = p.getAttackStrengthScale(0.5f);
		if (s < 0.1f) return;
		double base = p.getAttributeValue(Attributes.ATTACK_DAMAGE);
		var sharp = mc.level.registryAccess().lookupOrThrow(Registries.ENCHANTMENT).getOrThrow(Enchantments.SHARPNESS);
		int lvl = EnchantmentHelper.getItemEnchantmentLevel(sharp, p.getMainHandItem());
		double dmg = base * (0.2 + s * s * 0.8) + (lvl > 0 ? 0.5 * lvl + 0.5 : 0) * s;
		boolean crit = s > 0.9f && p.fallDistance > 0 && !p.onGround() && !p.onClimbable() && !p.isInWater() && !p.isPassenger();
		if (crit) dmg *= 1.5;
		dev.mcdota.Sync.out(String.format(java.util.Locale.ROOT, "swing %.2f", dmg));
	}
}

package dev.mcdota.mixin;

import net.minecraft.client.Minecraft;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.item.enchantment.EnchantmentHelper;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfoReturnable;

// Melee goes to the Dota unit Dota itself highlights under the crosshair (Panorama reports it), not to whichever
// invisible stand-in Minecraft's crosshair happens to touch: those lag and are shaped differently, so last hits missed.
// Every left click sends the swing's damage, worked out like Minecraft's Player.attack: the client knows the attack
// cooldown and whether it's a crit, the integrated server the weapon's attack damage (equipment attributes exist only
// there: the client's value is a bare fist) and the enchantments.
@Mixin(Minecraft.class)
public class AttackMixin {
	@Inject(method = "startAttack", at = @At("HEAD"))
	private void mcdota$swing(CallbackInfoReturnable<Boolean> cir) {
		Minecraft mc = (Minecraft) (Object) this;
		var p = mc.player;
		var server = mc.getSingleplayerServer();
		if (p == null || server == null || p.isSpectator() || mc.screen != null) return;
		float s = p.getAttackStrengthScale(0.5f);
		if (s < 0.1f) return;
		boolean crit = s > 0.9f && p.fallDistance > 0 && !p.onGround() && !p.onClimbable() && !p.isInWater() && !p.isPassenger();
		// a sword's sweep: full swing, on the ground, not sprinting, no crit (as in Player.attack)
		boolean sweep = s > 0.9f && !crit && p.onGround() && !p.isSprinting()
			&& p.getMainHandItem().is(net.minecraft.tags.ItemTags.SWORDS);
		java.util.UUID id = p.getUUID();
		server.execute(() -> {
			var sp = server.getPlayerList().getPlayer(id);
			if (sp == null) return;
			float base = (float) sp.getAttributeValue(Attributes.ATTACK_DAMAGE);
			var source = sp.damageSources().playerAttack(sp);
			float ench = EnchantmentHelper.modifyDamage(sp.level(), sp.getMainHandItem(), sp, source, base) - base;
			float dmg = base * (0.2f + s * s * 0.8f);
			if (crit) dmg *= 1.5f;
			dmg += ench * s;
			// the sweep's splash: 1 + sweeping ratio x attack damage (vanilla), Lua deals it around the target
			float sweepDmg = sweep ? 1f + (float) sp.getAttributeValue(Attributes.SWEEPING_DAMAGE_RATIO) * base : 0f;
			// and the full swing's damage (no cooldown, no crit): Lua's damage curve goes by it (MeleeScale)
			dev.mcdota.Sync.out(String.format(java.util.Locale.ROOT, "swing %.2f %d %.2f %.2f", dmg, crit ? 1 : 0, sweepDmg, base + ench));
		});
	}
}

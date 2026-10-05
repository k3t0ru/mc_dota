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
		if (dev.mcdota.Progress.noAttack) return; // stunned or disarmed in Dota
		float s = p.getAttackStrengthScale(0.5f);
		if (s < 0.1f) return;
		boolean crit = s > 0.9f && p.fallDistance > 0 && !p.onGround() && !p.onClimbable() && !p.isInWater() && !p.isPassenger();
		// a sword's sweep: full swing, on the ground, not sprinting, no crit (as in Player.attack)
		boolean sweep = s > 0.9f && !crit && p.onGround() && !p.isSprinting()
			&& p.getMainHandItem().is(net.minecraft.tags.ItemTags.SWORDS);
		java.util.UUID id = p.getUUID();
		float clientFall = (float) p.fallDistance; // (the server's was 0 at the swing: a mace never smashed)
		boolean clientFlying = p.isFallFlying();
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
			// and the full swing's damage (no cooldown, no crit): Lua's damage curve goes by it (MeleeScale);
			// Fire Aspect's burn (4 s a level, as in vanilla) for the target's stand-in
			// and the weapon's own damage and Sharpness level (Lua: Dota damage = curve of the weapon x Sharpness)
			int fire = 0, sharp = 0;
			for (var e : sp.getMainHandItem().getEnchantments().entrySet()) {
				if (e.getKey().is(net.minecraft.world.item.enchantment.Enchantments.FIRE_ASPECT)) fire = 4 * e.getIntValue();
				if (e.getKey().is(net.minecraft.world.item.enchantment.Enchantments.SHARPNESS)) sharp = e.getIntValue();
			}
			// a mace falling on its target: Minecraft's smash bonus (fall distance, Density), its sound and dust, his fall
			// forgiven (he hit nothing in Minecraft: the hit is Dota's); Lua knocks back the units around ("smash")
			var held = sp.getMainHandItem();
			if (held.getItem() instanceof net.minecraft.world.item.MaceItem) // (diagnostics: a mace's smash showed nothing)
				org.slf4j.LoggerFactory.getLogger("mcdota").info("mace swing: client fall {}, server fall {}, flying {}", clientFall, sp.fallDistance, clientFlying);
			if (held.getItem() instanceof net.minecraft.world.item.MaceItem mace && clientFall > 1.5f && !clientFlying) {
				sp.fallDistance = Math.max(sp.fallDistance, clientFall);
				float bonus = mace.getAttackDamageBonus(sp, base, source);
				dmg += bonus * s;
				boolean heavy = clientFall > 5;
				var lv = sp.level();
				// (on the ground he comes down on, like Minecraft's: the target's feet)
				var ground = sp.blockPosition();
				for (int i = 0; i < 40 && lv.getBlockState(ground.below()).isAir(); i++) ground = ground.below();
				lv.levelEvent(2013, ground, 750);
				lv.playSound(null, ground.getX() + 0.5, ground.getY(), ground.getZ() + 0.5, heavy ? net.minecraft.sounds.SoundEvents.MACE_SMASH_GROUND_HEAVY
					: net.minecraft.sounds.SoundEvents.MACE_SMASH_GROUND, net.minecraft.sounds.SoundSource.PLAYERS, 1f, 1f);
				sp.resetFallDistance();
				dev.mcdota.Sync.out(String.format(java.util.Locale.ROOT, "smash %.2f %.2f %.2f %d", sp.getX(), sp.getY(), sp.getZ(), heavy ? 1 : 0));
			}
			dev.mcdota.Sync.out(String.format(java.util.Locale.ROOT, "swing %.2f %d %.2f %.2f %d %.2f %d", dmg, crit ? 1 : 0, sweepDmg, base + ench, fire, base, sharp));
		});
	}
}

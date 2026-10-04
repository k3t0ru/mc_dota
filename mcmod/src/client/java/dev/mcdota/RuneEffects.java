package dev.mcdota;

import net.minecraft.core.Holder;
import net.minecraft.core.Registry;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.resources.Identifier;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.effect.MobEffect;
import net.minecraft.world.effect.MobEffectCategory;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.ai.attributes.AttributeModifier;
import net.minecraft.world.entity.ai.attributes.Attributes;

// Dota's runes as Minecraft effects of their own (mcdota:rune_*: names, icons and colours of the runes, not vanilla
// potions). Lua gives one for as long as the rune's modifier lasts on Dota's hero ("buff mcdota:rune_haste <s> 0").
//   haste: +80% walking speed (Dota's max speed)        double damage: the icon (Lua doubles the swing)
//   regeneration: 2 hp a second                           invisibility: the icon (Dota hides the hero)
//   arcane: +30% attack speed (Minecraft has no mana)    shield: 12 hp of absorption
public final class RuneEffects {
	public static Holder<MobEffect> HASTE, DOUBLE_DAMAGE, REGEN, INVIS, ARCANE, SHIELD;

	private static class Rune extends MobEffect {
		private final String kind;

		Rune(String kind, int color) {
			super(MobEffectCategory.BENEFICIAL, color);
			this.kind = kind;
		}

		@Override
		public boolean shouldApplyEffectTickThisTick(int duration, int amplifier) {
			return kind.equals("regen") && duration % 10 == 0;
		}

		@Override
		public boolean applyEffectTick(ServerLevel level, LivingEntity e, int amplifier) {
			if (kind.equals("regen")) e.heal(1);
			return true;
		}

		@Override
		public void onEffectStarted(LivingEntity e, int amplifier) {
			if (kind.equals("shield")) e.setAbsorptionAmount(Math.max(e.getAbsorptionAmount(), 12));
		}
	}

	private static Holder<MobEffect> register(String name, MobEffect effect) {
		return Registry.registerForHolder(BuiltInRegistries.MOB_EFFECT, Identifier.fromNamespaceAndPath("mcdota", name), effect);
	}

	public static void register() {
		HASTE = register("rune_haste", new Rune("haste", 0xFF3B30)
			.addAttributeModifier(Attributes.MOVEMENT_SPEED, Identifier.fromNamespaceAndPath("mcdota", "rune_haste"), 0.8, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
		DOUBLE_DAMAGE = register("rune_double_damage", new Rune("dd", 0x3A7BFF));
		REGEN = register("rune_regen", new Rune("regen", 0x3FD13F));
		INVIS = register("rune_invis", new Rune("invis", 0xB46CFF));
		ARCANE = register("rune_arcane", new Rune("arcane", 0xFF5CD6)
			.addAttributeModifier(Attributes.ATTACK_SPEED, Identifier.fromNamespaceAndPath("mcdota", "rune_arcane"), 0.3, AttributeModifier.Operation.ADD_MULTIPLIED_TOTAL));
		SHIELD = register("rune_shield", new Rune("shield", 0xFFC93A)
			.addAttributeModifier(Attributes.MAX_ABSORPTION, Identifier.fromNamespaceAndPath("mcdota", "rune_shield"), 12, AttributeModifier.Operation.ADD_VALUE));
	}
}

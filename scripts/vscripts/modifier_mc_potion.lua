-- A splash potion from Minecraft on a Dota unit: slowness (15% slower a level), weakness (25% less attack damage a level)
modifier_mc_potion = class( {} )

function modifier_mc_potion:IsDebuff() return true end
function modifier_mc_potion:IsPurgable() return true end
function modifier_mc_potion:GetAttributes() return MODIFIER_ATTRIBUTE_MULTIPLE end
function modifier_mc_potion:OnCreated( kv )
	self.kind, self.level = kv.kind or "slow", kv.level or 1
end
function modifier_mc_potion:DeclareFunctions()
	return { MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE, MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE }
end
function modifier_mc_potion:GetModifierMoveSpeedBonus_Percentage()
	return self.kind == "slow" and -15 * ( self.level or 1 ) or 0
end
function modifier_mc_potion:GetModifierDamageOutgoing_Percentage()
	return self.kind == "weak" and -25 * ( self.level or 1 ) or 0
end

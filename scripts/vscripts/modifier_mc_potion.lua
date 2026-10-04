-- A splash potion from Minecraft on a Dota unit: slowness (15% slower a level), weakness (25% less attack damage a
-- level); "web": a cobweb's slow (no icon, no look: it is renewed every moment). Minecraft's effect icons
-- (tools/gen_mobs.py copies them) and Dota's look of a slow / Bane's enfeeble. The stack count carries kind and level
-- to the clients (kind * 10 + level), which draw the icon.
modifier_mc_potion = class( {} )
local KINDS = { slow = 1, weak = 2, web = 3 }

function modifier_mc_potion:IsDebuff() return true end
function modifier_mc_potion:IsPurgable() return true end
function modifier_mc_potion:GetAttributes() return MODIFIER_ATTRIBUTE_MULTIPLE end
function modifier_mc_potion:IsHidden() return self:Kind() == 3 end
function modifier_mc_potion:OnCreated( kv )
	if IsServer() then self:SetStackCount( ( KINDS[ kv.kind ] or 1 ) * 10 + math.min( 9, kv.level or 1 ) ) end
end
function modifier_mc_potion:Kind() return math.floor( self:GetStackCount() / 10 ) end
function modifier_mc_potion:Level() return math.max( 1, self:GetStackCount() % 10 ) end
function modifier_mc_potion:DeclareFunctions()
	return { MODIFIER_PROPERTY_MOVESPEED_BONUS_PERCENTAGE, MODIFIER_PROPERTY_DAMAGEOUTGOING_PERCENTAGE }
end
function modifier_mc_potion:GetModifierMoveSpeedBonus_Percentage()
	return self:Kind() ~= 2 and -15 * self:Level() or 0
end
function modifier_mc_potion:GetModifierDamageOutgoing_Percentage()
	return self:Kind() == 2 and -25 * self:Level() or 0
end
function modifier_mc_potion:GetTexture() return self:Kind() == 2 and "mc/weakness" or "mc/slowness" end
function modifier_mc_potion:GetEffectName()
	local k = self:Kind()
	return k == 2 and "particles/units/heroes/hero_bane/bane_enfeeble.vpcf" or k == 1 and "particles/generic_gameplay/generic_slowed_cold.vpcf" or nil
end
function modifier_mc_potion:GetEffectAttachType() return PATTACH_ABSORIGIN_FOLLOW end

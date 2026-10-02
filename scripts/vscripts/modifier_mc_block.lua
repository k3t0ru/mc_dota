-- Blocks show no health bar until someone starts mining them. Stack count 1 = a lone block at ground level: units walk
-- over it like a Minecraft player steps up one block (modifier_mc_lift draws them on top), so it must not collide.
modifier_mc_block = class( {} )

function modifier_mc_block:IsHidden() return true end
function modifier_mc_block:IsPurgable() return false end
function modifier_mc_block:CheckState()
	return { [MODIFIER_STATE_NO_HEALTH_BAR] = true, [MODIFIER_STATE_NO_UNIT_COLLISION] = self:GetStackCount() == 1 }
end

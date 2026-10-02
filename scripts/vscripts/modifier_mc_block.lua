-- Blocks show no health bar until someone starts mining them
modifier_mc_block = class( {} )

function modifier_mc_block:IsHidden() return true end
function modifier_mc_block:IsPurgable() return false end
function modifier_mc_block:CheckState() return { [MODIFIER_STATE_NO_HEALTH_BAR] = true } end

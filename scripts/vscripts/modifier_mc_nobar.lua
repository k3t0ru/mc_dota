-- No health bar (Steve's courier, hidden and left alone: MC:OnSpawned)
modifier_mc_nobar = class( {} )

function modifier_mc_nobar:IsHidden() return true end
function modifier_mc_nobar:IsPurgable() return false end
function modifier_mc_nobar:RemoveOnDeath() return true end
function modifier_mc_nobar:CheckState() return { [MODIFIER_STATE_NO_HEALTH_BAR] = true } end

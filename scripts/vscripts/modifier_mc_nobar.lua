-- A unit far from Steve: no health bar (Dota draws bars at a fixed screen size, so far away they covered the view)
modifier_mc_nobar = class( {} )

function modifier_mc_nobar:IsHidden() return true end
function modifier_mc_nobar:IsPurgable() return false end
function modifier_mc_nobar:RemoveOnDeath() return true end
function modifier_mc_nobar:CheckState() return { [MODIFIER_STATE_NO_HEALTH_BAR] = true } end

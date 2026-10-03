-- Steve 4+ blocks above the ground (a tower of blocks, flying): sees over cliffs and trees, like from high ground
modifier_mc_highground = class( {} )

function modifier_mc_highground:IsHidden() return true end
function modifier_mc_highground:IsPurgable() return false end
function modifier_mc_highground:CheckState() return { [MODIFIER_STATE_FORCED_FLYING_VISION] = true } end

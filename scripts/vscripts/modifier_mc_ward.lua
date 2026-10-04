-- A torch ward (MCWorld:Ward): invisible to the enemy without true sight (a sentry, a soul torch, a gem), like Dota's
-- wards. (Dota's modifier_invisible left it seen: its torch, its bar. An invisibility level turned it into a shimmer
-- for its own team.)
modifier_mc_ward = class( {} )

function modifier_mc_ward:IsHidden() return true end
function modifier_mc_ward:IsPurgable() return false end
function modifier_mc_ward:CheckState()
	return { [MODIFIER_STATE_INVISIBLE] = true, [MODIFIER_STATE_NO_UNIT_COLLISION] = true }
end

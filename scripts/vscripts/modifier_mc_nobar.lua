-- A unit far from Steve: no health bar on Steve's screen (Dota draws bars at a fixed screen size, so far away they
-- covered his view). Only his: Dota's players keep Dota's bars. (Decided by each client's own copy of the modifier:
-- the server says nothing.)
modifier_mc_nobar = class( {} )

function modifier_mc_nobar:IsHidden() return true end
function modifier_mc_nobar:IsPurgable() return false end
function modifier_mc_nobar:RemoveOnDeath() return true end
function modifier_mc_nobar:CheckState()
	if not IsClient() then return {} end
	local ok, team = pcall( function() return GetLocalPlayerTeam() end )
	if ok and team == DOTA_TEAM_GOODGUYS then return { [MODIFIER_STATE_NO_HEALTH_BAR] = true } end
	return {}
end

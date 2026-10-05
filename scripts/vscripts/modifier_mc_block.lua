-- A Minecraft block column's Dota unit. Stack count: +1 = a lone block at ground level (units walk over it like a
-- Minecraft player steps up one block, modifier_mc_lift draws them on top: no collision), +2 = being mined (its health
-- bar shows the breaking). Never pushed around by Dota's pathing (a wall's own obstruction stood on it: it was shoved
-- aside, its hitbox and collision with it). Blocks Dota built itself (the fountain market) and blocks near a fountain
-- are invulnerable: fountains shoot neutrals.
modifier_mc_block = class( {} )

function modifier_mc_block:IsHidden() return true end
function modifier_mc_block:IsPurgable() return false end
function modifier_mc_block:CheckState()
	local st = self:GetStackCount()
	return { [MODIFIER_STATE_NO_HEALTH_BAR] = st < 2, [MODIFIER_STATE_NO_UNIT_COLLISION] = st % 2 == 1,
		[MODIFIER_STATE_FLYING_FOR_PATHING_PURPOSES_ONLY] = true,
		[MODIFIER_STATE_INVULNERABLE] = IsServer() and self:GetParent().mc_protected == true }
end

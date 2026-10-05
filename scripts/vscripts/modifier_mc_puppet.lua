-- Steve's stand-in for Dota's players (MCBridge:Puppet): an invisible, clickable hero following his hero (which draws
-- nothing: his own camera sits inside it). Orders on it and attacks landing on it go to Steve (MC:OrderFilter,
-- MC:DamageFilter); Dire sees Minecraft's Steve on it (a particle), and his health on its bar. No collision, not on the minimap; never
-- dies (damage past the filter: an execute, a pure loss).
modifier_mc_puppet = class( {} )

function modifier_mc_puppet:IsHidden() return true end
function modifier_mc_puppet:IsPurgable() return false end
function modifier_mc_puppet:CheckState()
	return { [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
		[MODIFIER_STATE_NOT_ON_MINIMAP] = true, [MODIFIER_STATE_DISARMED] = true }
end
-- its model through a modifier, like a hex: Dota then hides the hero's cosmetics too (they are drawn by each client,
-- out of the server's reach: Axe's armour hung in front of Steve's camera)
function modifier_mc_puppet:DeclareFunctions() return { MODIFIER_PROPERTY_MIN_HEALTH, MODIFIER_PROPERTY_MODEL_CHANGE } end
function modifier_mc_puppet:GetMinHealth() return 1 end
function modifier_mc_puppet:GetModifierModelChange() return "models/mc/steve_ghost.vmdl" end

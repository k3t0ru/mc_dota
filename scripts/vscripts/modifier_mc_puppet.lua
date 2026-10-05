-- Steve's stand-in for Dota's players (MCBridge:Puppet): an invisible, clickable hero following his hero (which draws
-- nothing: his own camera sits inside it). Orders on it and attacks landing on it go to Steve (MC:OrderFilter,
-- MC:DamageFilter); Dire sees Minecraft's Steve on it (a particle). No bar, no collision, not on the minimap; never
-- dies (damage past the filter: an execute, a pure loss).
modifier_mc_puppet = class( {} )

function modifier_mc_puppet:IsHidden() return true end
function modifier_mc_puppet:IsPurgable() return false end
function modifier_mc_puppet:CheckState()
	return { [MODIFIER_STATE_NO_HEALTH_BAR] = true, [MODIFIER_STATE_NO_UNIT_COLLISION] = true,
		[MODIFIER_STATE_NOT_ON_MINIMAP] = true, [MODIFIER_STATE_DISARMED] = true }
end
function modifier_mc_puppet:DeclareFunctions() return { MODIFIER_PROPERTY_MIN_HEALTH } end
function modifier_mc_puppet:GetMinHealth() return 1 end

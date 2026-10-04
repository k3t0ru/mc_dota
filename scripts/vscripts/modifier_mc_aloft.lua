-- Steve up more than 3 blocks (a pillar): out of every Dota unit's reach, like out of a Minecraft player's: not a target
-- for the enemy (on him and his stand-in, MCBridge:Puppet)
modifier_mc_aloft = class( {} )

function modifier_mc_aloft:IsHidden() return true end
function modifier_mc_aloft:IsPurgable() return false end
function modifier_mc_aloft:CheckState() return { [MODIFIER_STATE_UNTARGETABLE_ENEMY] = true } end

-- A unit standing on a 1-high Minecraft block: drawn that much higher (stack count = Dota units); Dota's ground stays below
modifier_mc_lift = class( {} )

function modifier_mc_lift:IsHidden() return true end
function modifier_mc_lift:IsPurgable() return false end
function modifier_mc_lift:DeclareFunctions() return { MODIFIER_PROPERTY_VISUAL_Z_DELTA } end
function modifier_mc_lift:GetVisualZDelta() return self:GetStackCount() end

-- On fire from Minecraft (MCBridge:Burn): Dota's look of burning, and Minecraft's fire icon. (The damage comes from
-- Minecraft: its stand-in burns there.)
modifier_mc_burning = class( {} )

function modifier_mc_burning:IsDebuff() return true end
function modifier_mc_burning:IsPurgable() return true end
function modifier_mc_burning:GetTexture() return "mc/fire" end
function modifier_mc_burning:GetEffectName() return "particles/units/heroes/hero_huskar/huskar_burning_spear_debuff.vpcf" end
function modifier_mc_burning:GetEffectAttachType() return PATTACH_ABSORIGIN_FOLLOW end

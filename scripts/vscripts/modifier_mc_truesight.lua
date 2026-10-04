-- A soul torch's sentry ward: shows invisible enemies around it (Dota's true sight), like the sentry item does
modifier_mc_truesight = class( {} )

function modifier_mc_truesight:IsHidden() return true end
function modifier_mc_truesight:IsPurgable() return false end
function modifier_mc_truesight:IsAura() return true end
function modifier_mc_truesight:GetModifierAura() return "modifier_truesight" end
function modifier_mc_truesight:GetAuraRadius() return 900 end
function modifier_mc_truesight:GetAuraSearchTeam() return DOTA_UNIT_TARGET_TEAM_ENEMY end
function modifier_mc_truesight:GetAuraSearchType() return DOTA_UNIT_TARGET_HERO + DOTA_UNIT_TARGET_BASIC + DOTA_UNIT_TARGET_OTHER end
function modifier_mc_truesight:GetAuraSearchFlags() return DOTA_UNIT_TARGET_FLAG_INVULNERABLE end

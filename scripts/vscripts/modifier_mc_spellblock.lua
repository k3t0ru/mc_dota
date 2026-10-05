-- Steve's spell block (a shield enchanted with mcdota:spell_block in his hand, Minecraft's side: Progress.java): stops
-- one enemy's targeted spell like Linken's Sphere, while Minecraft says it's ready ("sb 1"), then Minecraft cools it down
modifier_mc_spellblock = class( {} )

function modifier_mc_spellblock:IsHidden() return true end
function modifier_mc_spellblock:IsPurgable() return false end
function modifier_mc_spellblock:RemoveOnDeath() return false end
function modifier_mc_spellblock:DeclareFunctions() return { MODIFIER_PROPERTY_ABSORB_SPELL } end
function modifier_mc_spellblock:GetAbsorbSpell( params )
	if not IsServer() or not MCBridge or not MCBridge.spellBlockReady then return 0 end
	local ab = params.ability
	local caster = ab and ab.GetCaster and ab:GetCaster()
	if not caster or caster:GetTeamNumber() == self:GetParent():GetTeamNumber() then return 0 end
	MCBridge.spellBlockReady = false
	MCBridge:Send( "sbused" )
	local at = MCBridge.puppet and not MCBridge.puppet:IsNull() and MCBridge.puppet or self:GetParent()
	local fx = ParticleManager:CreateParticle( "particles/items_fx/immunity_sphere.vpcf", PATTACH_ABSORIGIN_FOLLOW, at )
	ParticleManager:ReleaseParticleIndex( fx )
	EmitSoundOnLocationWithCaster( at:GetAbsOrigin(), "DOTA_Item.LinkensSphere.Activate", self:GetParent() )
	return 1
end

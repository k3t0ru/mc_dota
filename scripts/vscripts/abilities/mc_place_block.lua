-- Steve: place a cobblestone (or log) block from the inventory on the grid
mc_place_block = class( {} )

local USES = { item_mc_cobblestone = "npc_mc_block_cobble", item_mc_log = "npc_mc_block_log" }

function mc_place_block:OnSpellStart()
	local hero = self:GetCaster()
	local p = self:GetCursorPosition()
	p = GetGroundPosition( Vector( math.floor( p.x / GRID + 0.5 ) * GRID, math.floor( p.y / GRID + 0.5 ) * GRID, 0 ), nil )

	if #FindUnitsInRadius( hero:GetTeam(), p, nil, 64, DOTA_UNIT_TARGET_TEAM_BOTH, DOTA_UNIT_TARGET_ALL,
		DOTA_UNIT_TARGET_FLAG_INVULNERABLE, FIND_ANY_ORDER, false ) > 0 then
		GameRules:SendCustomMessage( "#mc_occupied", hero:GetPlayerID(), 0 )
		return
	end
	for slot = 0, 8 do
		local it = hero:GetItemInSlot( slot )
		local block = it and USES[ it:GetAbilityName() ]
		if block then
			local c = it:GetCurrentCharges()
			if c > 1 then it:SetCurrentCharges( c - 1 ) else hero:RemoveItem( it ) end
			MC:SpawnBlock( block, p )
			EmitSoundOnLocationWithCaster( p, "Hero_EarthSpirit.StoneRemnant.Impact", hero )
			return
		end
	end
	GameRules:SendCustomMessage( "#mc_no_blocks", hero:GetPlayerID(), 0 )
end

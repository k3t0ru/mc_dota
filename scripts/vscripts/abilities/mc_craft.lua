-- Every recipe is an ability on the player's crafting table. Ability name -> result + ingredients.
RECIPES = {
	mc_craft_pickaxe_wood    = { "item_mc_pickaxe_wood",    { item_mc_log = 3 } },
	mc_craft_pickaxe_stone   = { "item_mc_pickaxe_stone",   { item_mc_cobblestone = 3, item_mc_log = 1 } },
	mc_craft_pickaxe_iron    = { "item_mc_pickaxe_iron",    { item_mc_iron = 3, item_mc_log = 1 } },
	mc_craft_pickaxe_diamond = { "item_mc_pickaxe_diamond", { item_mc_diamond = 3, item_mc_log = 1 } },
	mc_craft_sword_iron      = { "item_mc_sword_iron",      { item_mc_iron = 2, item_mc_log = 1 } },
	mc_craft_sword_diamond   = { "item_mc_sword_diamond",   { item_mc_diamond = 2, item_mc_log = 1 } },
	mc_craft_torch           = { "item_mc_torch",           { item_mc_coal = 1, item_mc_log = 1 } },
}

local function count( hero, name )
	local n = 0
	for slot = 0, 8 do
		local it = hero:GetItemInSlot( slot )
		if it and it:GetAbilityName() == name then n = n + math.max( it:GetCurrentCharges(), 1 ) end
	end
	return n
end

local function take( hero, name, n )
	for slot = 0, 8 do
		local it = hero:GetItemInSlot( slot )
		if n > 0 and it and it:GetAbilityName() == name then
			local c = math.max( it:GetCurrentCharges(), 1 )
			if c > n then it:SetCurrentCharges( c - n ); n = 0
			else n = n - c; hero:RemoveItem( it ) end
		end
	end
end

local function craft( self )
	local table = self:GetCaster()
	local hero = table:GetOwner()
	local result, cost = unpack( RECIPES[ self:GetAbilityName() ] )
	local pid = hero:GetPlayerID()

	if ( hero:GetAbsOrigin() - table:GetAbsOrigin() ):Length2D() > 600 then
		GameRules:SendCustomMessage( "#mc_too_far", pid, 0 )
		return
	end
	for name, n in pairs( cost ) do
		if count( hero, name ) < n then
			GameRules:SendCustomMessage( "#mc_missing_" .. name, pid, 0 )
			return
		end
	end
	for name, n in pairs( cost ) do take( hero, name, n ) end
	hero:AddItemByName( result )
	EmitSoundOn( "General.Buy", hero )
end

for name in pairs( RECIPES ) do
	_G[ name ] = class( { OnSpellStart = craft } )
end

-- Loaded by BOTH the server and the client script VMs (addon_game_mode.lua is server only). Lua modifiers must be
-- linked in both, or the client says "unknown modifier type" and their visuals (lift, hidden health bars) never show.
LinkLuaModifier( "modifier_mc_block", "modifier_mc_block", LUA_MODIFIER_MOTION_NONE )
LinkLuaModifier( "modifier_mc_lift", "modifier_mc_lift", LUA_MODIFIER_MOTION_NONE )

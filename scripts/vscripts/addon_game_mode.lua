-- The game mode lives in mc_main.lua: loaded here under pcall, so an error while loading is printed in full ("[mc] LOAD
-- ERROR ..." in Dota's console.log; Dota itself only said "error in error handling")
local ok, err = pcall( require, "mc_main" )
if not ok then print( "[mc] LOAD ERROR " .. tostring( err ) ) end

# Checks the addon's Lua before a launch (pip install lupa). A broken addon_game_mode.lua loads NOTHING in Dota, silently:
# the hero pick comes back, no bridge. Two checks:
#  1. syntax of every file;
#  2. a dry run of addon_game_mode.lua's top level (and what it requires) with Dota's API stubbed: Dota's names are
#     dummies, but our own globals (MC, MCBridge, ...) exist only once the script assigns them, so using one too early
#     fails here like it does in Dota ("attempt to index a nil value").
# Usage: python tools/check_lua.py
import glob, os, re, sys
from lupa import LuaRuntime

root = os.path.join(os.path.dirname(__file__), "..", "scripts", "vscripts")
files = sorted(glob.glob(os.path.join(root, "**", "*.lua"), recursive=True))
lua = LuaRuntime()
bad = 0

check = lua.eval("function(src, name) local f, err = load(src, name); return err end")
for p in files:
    err = check(open(p, encoding="utf-8").read(), "@" + os.path.relpath(p))
    if err:
        bad += 1
        print("ERROR", err)

if not bad:
    ours = set()
    for p in files:
        for m in re.finditer(r"^(?:_G\.)?([A-Za-z_]\w*)\s*=", open(p, encoding="utf-8").read(), re.M):
            ours.add(m.group(1))
    lua.globals().OURS = lua.table_from({n: True for n in ours})
    lua.globals().ROOT = root
    err = lua.execute(r'''
        local dummy
        dummy = setmetatable( {}, { __index = function() return dummy end, __call = function() return dummy end,
            __newindex = function() end, __concat = function() return "" end, __tostring = function() return "dummy" end } )
        local env = setmetatable( {}, { __index = function( t, k )
            if _G[ k ] ~= nil and k ~= "require" then return _G[ k ] end
            if OURS[ k ] then return nil end -- ours: only after the script assigned it
            return dummy -- Dota's API
        end } )
        env._G = env
        env.class = function( t ) return t or {} end
        env.require = function( name )
            local f = assert( loadfile( ROOT .. "/" .. name .. ".lua", "t", env ) )
            return f()
        end
        local main = assert( loadfile( ROOT .. "/mc_main.lua", "t", env ) )
        local ok, e = pcall( main )
        if not ok then return tostring( e ) end
    ''')
    if err:
        bad += 1
        print("ERROR running mc_main.lua top level:", err)

print("lua ok" if not bad else f"{bad} problem(s)")
sys.exit(1 if bad else 0)

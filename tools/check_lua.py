# Syntax-check the addon's Lua (Dota runs Lua 5.1-ish; a compile error silently drops the whole game mode, which once
# brought back Dota's 90 s hero pick). Usage: python tools/check_lua.py   (needs: pip install lupa)
import glob, os, sys
from lupa import LuaRuntime
lua = LuaRuntime()
check = lua.eval("function(src, name) local f, err = load(src, name); return err end")
bad = 0
for p in sorted(glob.glob(os.path.join(os.path.dirname(__file__), "..", "scripts", "vscripts", "**", "*.lua"), recursive=True)):
    err = check(open(p, encoding="utf-8").read(), "@" + os.path.relpath(p))
    if err:
        bad += 1
        print("ERROR", err)
print("lua ok" if not bad else f"{bad} file(s) with errors")
sys.exit(1 if bad else 0)

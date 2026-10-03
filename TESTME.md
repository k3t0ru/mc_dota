# What to check by hand

Things Claude could not check alone (they need a real person playing), newest first. Strike them out or tell Claude.

## 2026-10-03 (13:25)
- [ ] **Smoothness.** Turning and walking should feel much calmer than before: in the measurements, camera unevenness
      went from 0.25–0.40 down to 0.04–0.05. Do your eyes still hurt? If so, when exactly: turning, walking, hand/HUD,
      or everything at once?
- [ ] **Mouse.** Now captured by a system hook (the cursor stands still at the screen centre). Check: menus/inventory
      with the cursor, focus switching (Alt+Tab out of the game and back), that the mouse is never "stuck" outside the game.
- [ ] **TNT and flint and steel** (fletcher, 6 and 2 emeralds). The explosion damages enemies (checked: 22–25 HP = 220–250
      Dota damage), doesn't deny allies, and leaves no crater in the ground or the market. Check that it's fun to use.
- [ ] **No digging** the ground (verified by holding the button 3 s). Blocks you placed yourself can still be broken: check.
- [ ] **Coin sound** on a kill (General.Coins): I can't hear it, so check that it plays and isn't too loud.
- [ ] **192 emeralds at the start** of every match is a test value (`TEST_EMERALDS` in Progress.java); set it to 0 for real games.
- [ ] Villagers in the stalls no longer turn toward you (they shook): they just stand facing the counter.

## Earlier, still unchecked by you
- [ ] Wheel switches the hotbar (verified by synthesized wheel notches).
- [ ] Green emerald number over a killed creep, no yellow Dota gold (verified on a screenshot).
- [ ] Melee lands on the creep Dota highlights under the crosshair; iron sword = 6.0 damage (verified).
- [ ] Denies: "!" over the creep, no XP or emeralds, no sweep splash.
- [ ] Shield against a tower/creep hit, death penalty (verified: 64 → 61 emeralds after a TNT death), respawn timer.
- [ ] Repair at the toolsmith (sneak + right click), selling materials, the secret trader at Dota's secret shop.

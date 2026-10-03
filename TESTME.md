# What to check by hand

Things Claude could not check alone (they need a real person playing), newest first. Strike them out or tell Claude.

## 2026-10-03 (22:00)
- [ ] **Walking bob** at the market (traders/stalls): should be gone or much smaller.
- [ ] **Creeps and towers attack you** after a death right away (they also do from the very start now).
- [ ] **Sharper textures** (Dota's texture quality is forced to high for this mode).
- [ ] High-ground vision from 4 blocks up.

## 2026-10-03 (20:30)
- [ ] **Whole map visible** (fog of war hides units as in Dota). The striped dark wall on the horizon is Dota's map edge.
- [ ] **No invisible walls** at the Dire T4s / Dire top T1-T2 (I walked through x=128 / z=-128 where it was).
- [ ] **Selling**: open any trader -> offers to buy what you carry (gear by durability). Mouse wheel scrolls the list.
- [ ] **Prices**: everything one at a time (except 1-emerald stacks). No buckets, no grindstone.
- [ ] **Fountain** heals and feeds you quickly. **Roshan**: only the totem, no Aegis in Dota.
- [ ] **Fire Aspect** sword sets creeps on fire; neutrals drop raw beef, cooked if they died burning.
- [ ] **Pillar up** on a half-step (jump + place under you). Sharper block textures. No zombie flashes.
- [ ] After dying/respawning, do creeps and towers attack you again? (couldn't reproduce)
- [ ] Traders/stalls jittering up and down while walking: still there?

## 2026-10-03 (19:25)
- [ ] **Sword damage**: wooden ~55, iron ~147, diamond ~214, netherite ~300, netherite + Sharpness V ~650 per full
      swing (crits x1.5). Roshan with a maxed netherite sword should take ~10 s. Tell me if it feels off.
- [ ] **Blocks on slopes** sit on the ground now (half sunk), not floating. Breaking one brings the step back.
- [ ] **Burning creeps**: flames only at their feet.
- [ ] **Clock** (fletcher, 2 emeralds): Dota's time + Day/Night top-left while it's in your inventory.
- [ ] **Water / lava buckets** (fletcher): lava burns creeps.

## 2026-10-03 (17:45)
- [ ] **Looking up** works now (Dota's camera tilts up too). Check: crossing the horizon is smooth, hitting flying
      things, ender pearls, elytra climbing.
- [ ] **XP bar = your level** (health grows with it); enchanting/anvil need the level but don't take it.
- [ ] **Alt+Tab**: the cursor is free outside the game; click into the picture to play again.
- [ ] **Enemy side of the map** (Dire jungle/base): ground should match, no dirt strips, no invisible walls.
- [ ] Fire is animated; creeps die in fire faster. Names over the traders. Death title stays with a countdown.
- [ ] No Kunkka model after respawn. Creeps no longer attack your blocks; the fountain doesn't shoot blocks near it.
- [ ] Jumping: was it broken only after dying? (I couldn't reproduce it; a stale "dead" save state is now reset.)

## 2026-10-03 (16:50)
- [ ] **Blocks**: every Minecraft block now has its own look in Dota (anvils, fences, glass, torches, fire, logs on
      their side, slabs, leaves...). Look for blocks that look wrong or are turned the wrong way.
- [ ] **Ground** should match Dota's everywhere now (± a quarter block). Tell me where it doesn't.
- [ ] **Fire** lights everywhere and burns creeps; creeps walk through fire, not over it.
- [ ] **Crits / sweeps** always show their particles; the sweep hits enemies around the target.
- [ ] **Roshan's boss bar** in the pit (not tested by me: I didn't go to Roshan), towers' bar while hitting them.
- [ ] **Elytra**: fireworks at the secret shop.
- [ ] **Steve**: no Kunkka voice lines, no Dota level-up sound (max health still grows with your level).
- [ ] **High ground**: stand 3+ blocks up (a pillar) → you should see further (Dota's vision over trees/cliffs).
- [ ] No black stripes far away, no zombie flashing on creeps.

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

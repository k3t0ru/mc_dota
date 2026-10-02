# Generates resource/addon_english.txt and addon_russian.txt. Edit strings here, then: python tools/gen_lang.py
import os

R = os.path.join(os.path.dirname(__file__), "..", "resource")

T = {  # token -> (en, ru)
    "addon_game_name": ("Minecraft Dungeons x Dota", "Minecraft Dungeons x Dota"),
    "npc_dota_hero_kunkka": ("Steve", "Стив"),
    "mc_need_better_pickaxe": ("You need a better pickaxe for this block.", "Для этого блока нужна кирка получше."),
    "mc_too_far": ("Get closer to your crafting table.", "Подойди ближе к верстаку."),
    "mc_occupied": ("Something is already there.", "Тут уже что-то есть."),
    "mc_no_blocks": ("No cobblestone or logs to place.", "Нет булыжника или брёвен."),
    "mc_missing_item_mc_log": ("Not enough logs.", "Не хватает брёвен."),
    "mc_missing_item_mc_cobblestone": ("Not enough cobblestone.", "Не хватает булыжника."),
    "mc_missing_item_mc_coal": ("Not enough coal.", "Не хватает угля."),
    "mc_missing_item_mc_iron": ("Not enough iron.", "Не хватает железа."),
    "mc_missing_item_mc_diamond": ("Not enough diamonds.", "Не хватает алмазов."),
    "npc_mc_crafting_table": ("Crafting Table", "Верстак"),
    "npc_mc_zombie": ("Zombie", "Зомби"),
    "npc_mc_skeleton": ("Skeleton", "Скелет"),
    "npc_mc_block_log": ("Log", "Бревно"),
    "npc_mc_block_stone": ("Stone", "Камень"),
    "npc_mc_block_cobble": ("Cobblestone", "Булыжник"),
    "npc_mc_block_coal": ("Coal Ore", "Угольная руда"),
    "npc_mc_block_iron": ("Iron Ore", "Железная руда"),
    "npc_mc_block_diamond": ("Diamond Ore", "Алмазная руда"),
}

A = {  # ability/item -> (en name, ru name, en desc, ru desc)
    "mc_place_block": ("Place Block", "Поставить блок", "Places cobblestone (or a log) from your inventory.", "Ставит булыжник (или бревно) из инвентаря."),
    "mc_craft_pickaxe_wood": ("Wooden Pickaxe", "Деревянная кирка", "3 logs", "3 бревна"),
    "mc_craft_pickaxe_stone": ("Stone Pickaxe", "Каменная кирка", "3 cobblestone + 1 log", "3 булыжника + 1 бревно"),
    "mc_craft_pickaxe_iron": ("Iron Pickaxe", "Железная кирка", "3 iron + 1 log", "3 железа + 1 бревно"),
    "mc_craft_pickaxe_diamond": ("Diamond Pickaxe", "Алмазная кирка", "3 diamonds + 1 log", "3 алмаза + 1 бревно"),
    "mc_craft_sword_iron": ("Iron Sword", "Железный меч", "2 iron + 1 log", "2 железа + 1 бревно"),
    "mc_craft_sword_diamond": ("Diamond Sword", "Алмазный меч", "2 diamonds + 1 log", "2 алмаза + 1 бревно"),
    "mc_craft_torch": ("Torch", "Факел", "1 coal + 1 log. More vision at night.", "1 уголь + 1 бревно. Больше обзора ночью."),
    "item_mc_log": ("Log", "Бревно", "", ""),
    "item_mc_cobblestone": ("Cobblestone", "Булыжник", "", ""),
    "item_mc_coal": ("Coal", "Уголь", "", ""),
    "item_mc_iron": ("Iron", "Железо", "", ""),
    "item_mc_diamond": ("Diamond", "Алмаз", "", ""),
    "item_mc_pickaxe_wood": ("Wooden Pickaxe", "Деревянная кирка", "Mines stone and coal.", "Добывает камень и уголь."),
    "item_mc_pickaxe_stone": ("Stone Pickaxe", "Каменная кирка", "Mines iron.", "Добывает железо."),
    "item_mc_pickaxe_iron": ("Iron Pickaxe", "Железная кирка", "Mines diamonds.", "Добывает алмазы."),
    "item_mc_pickaxe_diamond": ("Diamond Pickaxe", "Алмазная кирка", "Mines everything, fast.", "Добывает всё и быстро."),
    "item_mc_sword_iron": ("Iron Sword", "Железный меч", "", ""),
    "item_mc_sword_diamond": ("Diamond Sword", "Алмазный меч", "", ""),
    "item_mc_torch": ("Torch", "Факел", "More vision at night.", "Больше обзора ночью."),
}

for i, lang in ((0, "english"), (1, "russian")):
    L = ['"lang"', "{", f'\t"Language"\t"{lang}"', '\t"Tokens"', "\t{"]
    L += [f'\t\t"{k}"\t"{v[i]}"' for k, v in T.items()]
    for k, v in A.items():
        L.append(f'\t\t"DOTA_Tooltip_ability_{k}"\t"{v[i]}"')
        if v[2 + i]:
            L.append(f'\t\t"DOTA_Tooltip_ability_{k}_Description"\t"{v[2 + i]}"')
    L += ["\t}", "}", ""]
    with open(os.path.join(R, f"addon_{lang}.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(L))
print("ok")

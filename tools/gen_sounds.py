# Minecraft's sounds in Dota, for Dota's players (Steve hears Minecraft's own): his hits, a mace's smash, wind charges,
# throws, arrows, the mobs. From Minecraft's assets (tools/mcjar.py: Mojang's files, local, never shipped), Ogg -> WAV
# (Dota's compiler takes no Ogg). Output: content/sounds/mc/<path>.wav, content/soundevents/mc_sounds.vsndevts with an
# event "MC.<minecraft event>" each (several files: Dota picks one at random). Then compile with resourcecompiler.
import io, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mcjar
import soundfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "content")
EVENTS = [
    "entity.player.attack.strong", "entity.player.attack.weak", "entity.player.attack.crit", "entity.player.attack.sweep",
    "entity.player.attack.knockback", "entity.player.hurt", "entity.player.death",
    "item.mace.smash_ground", "item.mace.smash_ground_heavy", "item.mace.smash_air",
    "entity.wind_charge.wind_burst", "entity.wind_charge.throw", "entity.ender_pearl.throw", "entity.player.teleport",
    "entity.arrow.shoot", "entity.arrow.hit", "entity.generic.explode",
    "entity.zombie.ambient", "entity.zombie.hurt", "entity.zombie.death",
    "entity.skeleton.ambient", "entity.skeleton.hurt", "entity.skeleton.death", "entity.skeleton.shoot",
    "entity.spider.ambient", "entity.spider.hurt", "entity.spider.death",
]
sounds = json.loads(mcjar.asset("minecraft/sounds.json"))
lines = ['<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:generic:version{7412167c-06e9-4698-aff2-e63eb59037e7} -->', "{"]
made = 0
for ev in EVENTS:
    entry = sounds.get(ev)
    if not entry:
        print("no such sound:", ev)
        continue
    files = []
    for snd in entry["sounds"]:
        name = snd if isinstance(snd, str) else snd["name"]
        if not isinstance(snd, str) and snd.get("type") == "event": continue
        wav = os.path.join(ROOT, "sounds", "mc", name.replace("minecraft:", "") + ".wav")
        if not os.path.exists(wav):
            data, rate = soundfile.read(io.BytesIO(mcjar.asset("minecraft/sounds/" + name.replace("minecraft:", "") + ".ogg")))
            os.makedirs(os.path.dirname(wav), exist_ok=True)
            soundfile.write(wav, data, rate, subtype="PCM_16")
        files.append('"sounds/mc/' + name.replace("minecraft:", "") + '.vsnd"')
    lines.append(f'\t"MC.{ev}" = {{ type = "dota_update_default" vsnd_files = [ {", ".join(files)} ] volume = 1.0 }}')
    made += 1
lines.append("}")
os.makedirs(os.path.join(ROOT, "soundevents"), exist_ok=True)
with open(os.path.join(ROOT, "soundevents", "mc_sounds.vsndevts"), "w") as f:
    f.write("\n".join(lines) + "\n")
print("sounds:", made, "events")

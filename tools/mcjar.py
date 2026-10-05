# Minecraft's client jar, for the asset generators (textures and models come from it: Mojang's files, used locally,
# never shipped). The one Fabric's build already downloaded, else Mojang's own download (players without Minecraft).
import glob, json, os, urllib.request

VERSION = "1.21.11"
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".cache")


def path():
    env = os.environ.get("MC_JAR")
    if env and os.path.exists(env):
        return env
    jars = sorted(glob.glob(os.path.expanduser("~/.gradle/caches/fabric-loom/*/minecraft-client.jar")))
    if jars:
        return jars[-1]
    mine = os.path.join(CACHE, f"minecraft-{VERSION}-client.jar")
    if not os.path.exists(mine):
        os.makedirs(CACHE, exist_ok=True)
        print(f"downloading Minecraft {VERSION} (its textures, from Mojang)...")
        manifest = json.load(urllib.request.urlopen("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"))
        url = next(v["url"] for v in manifest["versions"] if v["id"] == VERSION)
        client = json.load(urllib.request.urlopen(url))["downloads"]["client"]["url"]
        urllib.request.urlretrieve(client, mine + ".part")
        os.replace(mine + ".part", mine)
    return mine


# Minecraft's assets (sounds and such: not in the jar, under hashed names from an index): Fabric's download if this PC has
# it, else Mojang's own, kept in tools/.cache/assets
LOOM_ASSETS = os.path.expanduser("~/.gradle/caches/fabric-loom/assets")
_index = None


def asset_index():
    global _index
    if _index is None:
        found = sorted(glob.glob(os.path.join(LOOM_ASSETS, "indexes", "*.json")) + glob.glob(os.path.join(CACHE, "assets", "indexes", "*.json")))
        if not found:
            os.makedirs(os.path.join(CACHE, "assets", "indexes"), exist_ok=True)
            manifest = json.load(urllib.request.urlopen("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"))
            url = next(v["url"] for v in manifest["versions"] if v["id"] == VERSION)
            ai = json.load(urllib.request.urlopen(url))["assetIndex"]
            dest = os.path.join(CACHE, "assets", "indexes", ai["id"] + ".json")
            urllib.request.urlretrieve(ai["url"], dest)
            found = [dest]
        _index = json.load(open(found[-1]))["objects"]
    return _index


def asset(name):
    """The bytes of an asset, e.g. "minecraft/sounds/entity/player/attack/strong1.ogg"."""
    h = asset_index()[name]["hash"]
    for base in (os.path.join(LOOM_ASSETS, "objects"), os.path.join(CACHE, "assets", "objects")):
        f = os.path.join(base, h[:2], h)
        if os.path.exists(f):
            return open(f, "rb").read()
    f = os.path.join(CACHE, "assets", "objects", h[:2], h)
    os.makedirs(os.path.dirname(f), exist_ok=True)
    urllib.request.urlretrieve(f"https://resources.download.minecraft.net/{h[:2]}/{h}", f)
    return open(f, "rb").read()


if __name__ == "__main__":
    print(path())

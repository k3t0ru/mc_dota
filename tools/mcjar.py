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


if __name__ == "__main__":
    print(path())

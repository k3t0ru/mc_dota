# One launcher for everything: checks and fetches what's needed, prepares the assets, starts the game.
#   python tools/mcdota.py host     the Minecraft player (Steve, Radiant): Dota + the bridge + Minecraft
#   python tools/mcdota.py player   a Dota player (Dire): Dota, joining the host
#   python tools/mcdota.py prepare  a Dota player's part without the game: updates, checks, downloads, assets
# (play_host.bat / play_dota.bat do the same by double click.) Settings: settings.ini next to this folder (made on the
# first run, with comments). Windows only (Dota's tools are).
import configparser, glob, hashlib, json, os, shutil, subprocess, sys, time, urllib.request, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(ROOT, "tools")
CACHE = os.path.join(TOOLS, ".cache")
SETTINGS = os.path.join(ROOT, "settings.ini")
ADDON = "mc_dungeons"

DEFAULT_SETTINGS = """; Minecraft x Dota settings. "auto" = found by itself.
[common]
; Dota 2 folder (with game\\bin\\win64\\dota2.exe), e.g. D:\\SteamLibrary\\steamapps\\common\\dota 2 beta
dota_dir = auto
; where to get updates from (a git address); empty = don't update
repo_url = https://github.com/k3t0ru/mc_dota.git

[host]
; the Minecraft player's screen: Dota's window and Minecraft's picture have this size
resolution = 1920x1080
; Minecraft frames a second = how often Dota's camera moves (30 on weak computers)
minecraft_fps = 60
; Dota's frame limit (0 = none)
dota_fps = 0
; dota = the real Dota map
map = dota
; JDK 21 folder; auto = found, or downloaded (Eclipse Temurin)
java_home = auto

[player]
; how Dota opens: fullscreen, borderless (a window without a frame over the whole screen), windowed
window = fullscreen
; Dota's resolution, e.g. 1920x1080; auto = the screen's own
resolution = auto
; the host's address (same network, or a VPN like ZeroTier/Radmin; the host's UDP port 27015 must be reachable)
host_ip = 192.168.0.10
"""


def say(msg): print(f"[mcdota] {msg}", flush=True)


def fail(msg):
    say("ОШИБКА: " + msg)
    input("Enter - закрыть")
    sys.exit(1)


def settings():
    if not os.path.exists(SETTINGS):
        open(SETTINGS, "w", encoding="utf-8").write(DEFAULT_SETTINGS)
        say(f"создан {SETTINGS}: проверь настройки")
    c = configparser.ConfigParser(inline_comment_prefixes=(";",))
    c.read_string(DEFAULT_SETTINGS)
    c.read(SETTINGS, encoding="utf-8")
    return c


# ---------------------------------------------------------------- checks ------------------------------------------
def pip_needs(mods):
    missing = []
    for mod, pkg in mods:
        try: __import__(mod)
        except ImportError: missing.append(pkg)
    if missing:
        say("ставлю Python-пакеты: " + ", ".join(missing))
        subprocess.check_call([sys.executable, "-m", "pip", "install", "--user", "-q"] + missing)


def git_update(cfg):
    url = cfg["common"]["repo_url"].strip()
    if not url or not shutil.which("git") or not os.path.isdir(os.path.join(ROOT, ".git")):
        return
    remotes = subprocess.run(["git", "remote"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    if "origin" not in remotes: subprocess.run(["git", "remote", "add", "origin", url], cwd=ROOT)
    say("обновляюсь из " + url)
    head = lambda: subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout
    before = head()
    r = subprocess.run(["git", "pull", "--ff-only"], cwd=ROOT)
    if r.returncode: say("обновиться не вышло (локальные изменения?), играю с тем, что есть")
    elif head() != before: # this very script may have changed: run the new one
        say("обновился, перезапускаюсь")
        sys.exit(subprocess.call([sys.executable] + sys.argv))


def find_dota(cfg):
    d = cfg["common"]["dota_dir"].strip()
    cands = [d] if d and d != "auto" else []
    try:
        import winreg
        k = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam")
        steam = winreg.QueryValueEx(k, "SteamPath")[0]
        vdf = os.path.join(steam, "steamapps", "libraryfolders.vdf")
        libs = [steam] + [l.split('"')[3] for l in open(vdf, encoding="utf-8") if '"path"' in l]
        cands += [os.path.join(l.replace("\\\\", "\\"), "steamapps", "common", "dota 2 beta") for l in libs]
    except Exception:
        pass
    cands += [r"C:\Program Files (x86)\Steam\steamapps\common\dota 2 beta"]
    for c in cands:
        if os.path.exists(os.path.join(c, "game", "bin", "win64", "dota2.exe")):
            return c
    fail("не нашёл Dota 2: впиши dota_dir в settings.ini")


def check_tools(dota):
    if not os.path.exists(os.path.join(dota, "game", "bin", "win64", "resourcecompiler.exe")) or not os.path.isdir(os.path.join(dota, "content")):
        fail("нужен DLC «Dota 2 Workshop Tools»: Steam > Dota 2 > Свойства > Дополнительный контент, поставь и запусти снова")


def find_java(cfg):
    j = cfg["host"]["java_home"].strip()
    cands = [j] if j and j != "auto" else []
    cands += [os.environ.get("JAVA_HOME", "")]
    for base in (r"C:\Program Files\Java", r"C:\Program Files\Eclipse Adoptium", r"C:\Program Files\Microsoft"):
        cands += sorted(glob.glob(os.path.join(base, "jdk-21*")), reverse=True)
    cands += sorted(glob.glob(os.path.join(CACHE, "jdk21", "*")), reverse=True)
    for c in cands:
        if c and os.path.exists(os.path.join(c, "bin", "java.exe")) and "21" in os.path.basename(c.rstrip("\\/")):
            return c
    say("скачиваю JDK 21 (Eclipse Temurin)...")
    os.makedirs(os.path.join(CACHE, "jdk21"), exist_ok=True)
    z = os.path.join(CACHE, "jdk21.zip")
    urllib.request.urlretrieve("https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse", z)
    zipfile.ZipFile(z).extractall(os.path.join(CACHE, "jdk21"))
    os.remove(z)
    return find_java(cfg)


def link_addon(dota):
    # the addon inside Dota: game side = this folder, content side = its content folder (junctions)
    for side, target in (("game", ROOT), ("content", os.path.join(ROOT, "content"))):
        p = os.path.join(dota, side, "dota_addons", ADDON)
        if os.path.lexists(p) and os.path.normcase(os.path.realpath(p)) != os.path.normcase(os.path.realpath(target)):
            # an older copy of the project (Dota would load ITS assets): point to this one. A link goes (its target
            # stays); a real folder is kept aside
            say(f"аддон в Доте вёл в {os.path.realpath(p)}: переключаю на эту папку")
            if os.path.islink(p) or getattr(os.path, "isjunction", lambda _: False)(p) or os.path.realpath(p) != os.path.abspath(p):
                os.rmdir(p)
            else:
                os.rename(p, p + "_old_" + time.strftime("%Y%m%d%H%M%S"))
        if not os.path.exists(p):
            os.makedirs(os.path.dirname(p), exist_ok=True)
            subprocess.check_call(["cmd", "/c", "mklink", "/J", p, target], stdout=subprocess.DEVNULL)
    # the real Dota map, copied from this Dota (never shipped)
    os.makedirs(os.path.join(ROOT, "maps"), exist_ok=True)
    m = os.path.join(ROOT, "maps", "dota.vpk")
    if not os.path.exists(m):
        shutil.copy(os.path.join(dota, "game", "dota", "maps", "dota.vpk"), m)


# ---------------------------------------------------------------- assets ------------------------------------------
GENERATORS = ["gen_blocks.py", "gen_mcblocks.py", "gen_villager.py", "gen_signs.py", "gen_mobs.py", "gen_steve.py",
              "gen_sky.py", "gen_tree_crack.py"]


def assets(dota):
    # made from Minecraft's own textures (a jar from Mojang) and compiled by Dota's tools; again only when they changed
    sys.path.insert(0, TOOLS)
    import mcjar
    jar = mcjar.path()
    h = hashlib.sha1(os.path.basename(jar).encode())
    for g in GENERATORS + ["mcjar.py"]:
        h.update(open(os.path.join(TOOLS, g), "rb").read())
    for d in ("particles", "panorama"):
        for f in sorted(glob.glob(os.path.join(ROOT, "content", d, "**", "*.*"), recursive=True)):
            if os.path.basename(f) != "version.js": h.update(open(f, "rb").read())
    rc = os.path.join(dota, "game", "bin", "win64", "resourcecompiler.exe")
    content = os.path.join(dota, "content", "dota_addons", ADDON)
    version(rc, content)
    stamp = os.path.join(CACHE, "assets.stamp")
    if os.path.exists(stamp) and open(stamp).read() == h.hexdigest() and not missing_compiled():
        say("ресурсы готовы")
        return
    env = dict(os.environ, MC_JAR=jar)
    for g in GENERATORS:
        say("готовлю " + g)
        subprocess.check_call([sys.executable, os.path.join(TOOLS, g)], cwd=ROOT, env=env, stdout=subprocess.DEVNULL)
    say("компилирую ресурсы для Dota (первый раз ~15-20 минут)...")
    for pat in ("models\\mcb\\*.vmdl", "models\\*.vmdl", "particles\\*.vpcf", "panorama\\*.xml", "panorama\\*.js"):
        r = subprocess.run([rc, "-fshallow2", "-r", "-i", os.path.join(content, pat)], capture_output=True, text=True, errors="ignore")
        bad = [l for l in r.stdout.splitlines() if "failed" in l or "rror" in l]
        if bad: say("  " + pat + ": " + " | ".join(l.strip() for l in bad[-3:]))
    gone = missing_compiled()
    if gone: fail("Dota не скомпилировала: " + ", ".join(gone) + " (ошибки компиляции выше)")
    os.makedirs(CACHE, exist_ok=True)
    open(stamp, "w").write(h.hexdigest())


def version(rc, content):
    # this copy's commit, for the server (Lua) and for each player's screen (Panorama): a Dota player whose copy differs
    # from the host's gets told in the chat (an old copy drew error models, Kunkka, sideways mobs)
    v = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip() or "?"
    open(os.path.join(ROOT, "scripts", "vscripts", "mc_version.lua"), "w").write(f'MC_VERSION = "{v}"\n')
    js = os.path.join(ROOT, "content", "panorama", "scripts", "custom_game", "version.js")
    text = f'"use strict";\n// written by tools/mcdota.py\nGameEvents.SendCustomGameEventToServer( "mc_version", {{ v: "{v}" }} );\n'
    if not os.path.exists(js) or open(js).read() != text or not os.path.exists(os.path.join(ROOT, "panorama", "scripts", "custom_game", "version.vjs_c")):
        open(js, "w").write(text)
        subprocess.run([rc, "-i", os.path.join(content, "panorama", "scripts", "custom_game", "version.js")], capture_output=True)


# what Dota draws from this addon, compiled: missing = error models, an invisible Steve, no HUD
COMPILED = ["models/mc/mob_zombie.vmdl_c", "models/mc/steve.vmdl_c", "models/mc/sky.vmdl_c", "particles/mc/steve_idle.vpcf_c", "models/mc/steve_ghost.vmdl_c",
            "panorama/layout/custom_game/custom_ui_manifest.vxml_c", "panorama/scripts/custom_game/fpcam.vjs_c",
            "panorama/layout/custom_game/hero_select.vxml_c", "panorama/images/custom_game/steve_face_png.vtex_c"]


def missing_compiled():
    return [f for f in COMPILED if not os.path.exists(os.path.join(ROOT, f))]


# ---------------------------------------------------------------- processes ---------------------------------------
def ps(query):
    out = subprocess.run(["powershell", "-NoProfile", "-Command", query], capture_output=True, text=True).stdout
    return [int(x) for x in out.split() if x.strip().isdigit()]


def kill(pids):
    for p in pids: subprocess.run(["taskkill", "/PID", str(p), "/F"], capture_output=True)


def dota_pids(): return ps("(Get-Process dota2 -ErrorAction SilentlyContinue).Id")
def mc_pids(): return ps("Get-CimInstance Win32_Process -Filter \"name='java.exe'\" | Where-Object { $_.CommandLine -like '*fabric.dli*' } | ForEach-Object { $_.ProcessId }")
def bridge_pids(): return ps("Get-CimInstance Win32_Process -Filter \"name like 'python%.exe'\" | Where-Object { $_.CommandLine -like '*bridge.py*' } | ForEach-Object { $_.ProcessId }")


def wait_for(path, words, seconds, start=0):
    for _ in range(seconds):
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                f.seek(start)
                text = f.read()
            for w in words:
                if w in text: return w
        except OSError:
            pass
        time.sleep(1)
    return None


# the bridge and Minecraft outlive this window (closing it, or it ending, took the bridge along)
DETACHED = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP


def spawn(args, **kw):
    try: return subprocess.Popen(args, creationflags=DETACHED | subprocess.CREATE_BREAKAWAY_FROM_JOB, **kw)
    except OSError: return subprocess.Popen(args, creationflags=DETACHED, **kw) # (a job that forbids breaking away)


def build_mc(java):
    # the first build downloads Minecraft and Fabric (minutes); later ones take seconds
    say("собираю мод Minecraft (первый раз долго: скачивается Minecraft и Fabric)")
    r = subprocess.run(["cmd", "/c", os.path.join(ROOT, "mcmod", "gradlew.bat"), "--no-daemon", "-q", "build"],
                       cwd=os.path.join(ROOT, "mcmod"), env=dict(os.environ, JAVA_HOME=java))
    if r.returncode: fail("мод Minecraft не собрался (см. выше)")


def prepare(cfg):
    say("всё готово, теперь play_dota.bat")


def host(cfg, dota):
    pip_needs([("PIL", "pillow"), ("lupa", "lupa")])
    java = find_java(cfg)
    build_mc(java)
    res = cfg["host"]["resolution"].strip()
    w, h = res.lower().split("x")
    # Lua first: an error in it silently drops the whole game mode
    if subprocess.run([sys.executable, os.path.join(TOOLS, "check_lua.py")], cwd=ROOT).returncode:
        fail("ошибка в Lua-скриптах (см. выше)")
    kill(mc_pids() + dota_pids() + bridge_pids())
    for i in range(60): # a Dota that hung can take a while to go
        if not dota_pids(): break
        if i == 5: say("жду, пока закроется старая Dota...")
        time.sleep(1)
    else:
        fail("старая Dota не закрывается: закрой её в диспетчере задач (или перезагрузи ПК) и запусти снова")
    say("мост Minecraft <-> Dota")
    log = open(os.path.join(ROOT, "bridge", "bridge.log"), "w")
    spawn([sys.executable, "-u", os.path.join(ROOT, "bridge", "bridge.py")], cwd=ROOT, stdout=log, stderr=log)
    dlog = os.path.join(dota, "game", "dota", "console.log")
    try: os.remove(dlog)
    except OSError: pass
    dstart = os.path.getsize(dlog) if os.path.exists(dlog) else 0 # (a log still held open: read past its old end)
    say("запускаю Dota: когда все подключатся, нажми в лобби кнопку старта (Minecraft запустится после неё)")
    subprocess.Popen([os.path.join(dota, "game", "bin", "win64", "dota2.exe"), "-novid", "-console", "-condebug", "-windowed",
                      "-noborder", "-w", w, "-h", h, "+dota_camera_edgemove", "0", "+dota_camera_speed", "0", "+dota_camera_lock", "0",
                      "+dota_camera_fov_min", "90", "+dota_camera_fov_max", "90", "+dota_camera_z_interp_speed", "4",
                      "+fps_max", cfg["host"]["dota_fps"], "+engine_no_focus_sleep", "0", "+fog_enable", "0",
                      "+dota_hud_disable_damage_numbers", "1", "+r_farz", "40000", "+r_texture_stream_mip_bias", "0",
                      "+dota_camera_zfar_zoomed_in", "40000", "+dota_camera_zfar_zoomed_out", "40000", "+snd_mute_losefocus", "0",
                      "+snd_musicvolume", "0", "+sv_cheats", "1", "+dota_disable_unit_ring", "1", "+dota_hero_indicators_max_distance", "0", "+dota_launch_custom_game", ADDON, cfg["host"]["map"]])
    # Minecraft: a fresh world each game (Dota rebuilds it), its first run downloads Minecraft and Fabric
    run = os.path.join(ROOT, "mcmod", "run")
    os.makedirs(os.path.join(run, "saves", "mcdota"), exist_ok=True)
    for f, t in (("level.dat", os.path.join(run, "saves", "mcdota", "level.dat")), ("options.txt", os.path.join(run, "options.txt"))):
        if not os.path.exists(t): shutil.copy(os.path.join(TOOLS, "template", f), t)
    for d in ("region", "entities", "poi"):
        shutil.rmtree(os.path.join(run, "saves", "mcdota", d), ignore_errors=True)
    r = wait_for(dlog, ["Script Runtime Error", "Error running script", "[mc] state "], 6 * 3600, dstart)
    if r != "[mc] state ": fail("ошибка Lua в Dota: см. " + dlog if r else "игра так и не началась")
    say("игра началась: запускаю Minecraft")
    kill(mc_pids()) # (one left from before would hold the world: "no access to the world")
    try: os.remove(os.path.join(run, "logs", "latest.log")) # (the last game's "joined" is in it)
    except OSError: pass
    env = dict(os.environ, JAVA_HOME=java, DOTA_SIZE=res, MC_FPS=cfg["host"]["minecraft_fps"])
    mlog = open(os.path.join(run, "gradle_run.log"), "w")
    spawn(["cmd", "/c", os.path.join(ROOT, "mcmod", "gradlew.bat"), "--no-daemon", "runClient"], cwd=os.path.join(ROOT, "mcmod"), env=env,
          stdout=mlog, stderr=mlog)
    r = wait_for(os.path.join(run, "logs", "latest.log"), ["joined the game", "has crashed"], 1200)
    say("Minecraft: " + (r or "не дождался (см. mcmod/run/gradle_run.log)"))
    say("готово. Минкрафт и Дота работают; это окно можно закрыть")


def player(cfg, dota):
    ip = cfg["player"]["host_ip"].strip()
    say(f"подключаюсь к хосту {ip}")
    mode = cfg["player"]["window"].strip().lower()
    args = {"fullscreen": ["-fullscreen"], "windowed": ["-windowed"]}.get(mode, ["-windowed", "-noborder"])
    res = cfg["player"]["resolution"].strip().lower()
    if "x" in res: args += ["-w", res.split("x")[0], "-h", res.split("x")[1]]
    elif mode == "borderless":  # a frameless window the screen's size
        import ctypes
        u = ctypes.windll.user32
        u.SetProcessDPIAware() # (the real pixels, not the scaled ones)
        args += ["-w", str(u.GetSystemMetrics(0)), "-h", str(u.GetSystemMetrics(1))]
    subprocess.Popen([os.path.join(dota, "game", "bin", "win64", "dota2.exe"), "-novid", "-console", "-condebug"] + args + ["+connect", ip])
    say("Dota запускается. Если что-то не так: пришли хосту " + os.path.join(dota, "game", "dota", "console.log"))


def main():
    role = sys.argv[1] if len(sys.argv) > 1 else "host"
    cfg = settings()
    if sys.version_info < (3, 10): fail("нужен Python 3.10+")
    if not shutil.which("git"): say("git не найден: обновления пропущены (https://git-scm.com)")
    git_update(cfg)
    pip_needs([("PIL", "pillow")])
    dota = find_dota(cfg)
    say("Dota: " + dota)
    check_tools(dota)
    link_addon(dota)
    assets(dota)
    {"host": host, "player": player}.get(role, lambda c, d: prepare(c))(cfg, dota)


if __name__ == "__main__":
    main()

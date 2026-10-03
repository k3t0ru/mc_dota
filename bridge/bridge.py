# Minecraft <-> Dota relay. Coordinates are Minecraft blocks; 1 block = 64 Dota units, MC (0,0) = Dota "anchor".
#
# Dota POSTs /sync every server frame:          Minecraft mod POSTs /mc every client tick:
#   anchor <x> <y> <z>                            me <name> <x> <y> <z> <yaw> <hp> <maxhp>
#   hero <id> <name> <x> <z> <hp> <maxhp>         hit <heroid> <amount>        (MC hp units)
#   dmg <amount> <attackerid> (Dota hit Steve)    set <x> <y> <z> <kind>       (block placed in MC)
#   block <x> <y> <z> <kind> / unblock <x> <y> <z>  break <x> <y> <z>          (block gone in MC)
#   reset               (new Dota game: clear MC's arena)
#   void <x> <z>        (outside the Dota map: bottomless column)   border <size> (MC world border, centred on 0,0)
#   h <x> <z> <hh> <low> (terrain: column height and its lowest neighbour's, half blocks above the flat floor)
#   boss none|<color> <hp> <max> <name> (Minecraft boss bar)   fx crit|sweep|hit <unit id> (hit effects)
#   mcfov <deg> (Minecraft's vertical fov = Dota's measured one)   spawnat <x> <y> <z> (Steve's spawn point)   delay <ms> (Dota camera playback delay: Minecraft's overlay waits as long)   trader <x> <z> <profession>
#   dead <respawn s> <emeralds lost> / respawn (Steve's Dota hero died / is back)   MC -> Dota: died <emeralds lost>
#   MC -> Dota: swing <damage> (a melee click: lands on the unit Dota highlights under the crosshair)
#   loot <emeralds> <gold> [<item> <n>]... (Steve killed a unit; leftover gold carries over in Lua)   lvl <n> (Steve's Dota level = MC max health)   xp <points>
# hero lines may carry a 7th field: the MC y the unit stands at (any Dota unit, creeps too)
# Dota gets back: steve <name> <x> <z> <hp> <maxhp> <yaw> <y>, hit .., mcblock <x> <y> <z> <kind> <solid>, mcbreak <x> <y> <z>,
#                 cam <lookX> <lookY> <yaw> <pitch> <dist> <lookZ>   (lookZ absolute; Lua turns it into a height offset)
# The mod gets back: hero .., dmg <amount>, block .., unblock .., reset, h ..
# Testing: POST /cmd with Minecraft commands, one per line (runs as the server, e.g. tp/give/time);
#          POST /dota with Dota console commands (e.g. dota_create_unit npc_dota_creep_badguys_melee enemy).
# The mod also sends its camera over UDP :27101 every frame: "<x> <y> <z> <yaw> <pitch>" (MC eye).
# Run: python bridge/bridge.py
import math, os, socket, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

POSELOG = open(os.environ["MCDOTA_POSELOG"], "w", buffering=1) if os.environ.get("MCDOTA_POSELOG") else None
GROUND_Y = 0  # MC feet level on flat ground (MC_FLOOR in addon_game_mode.lua)
SCALE = 96  # Dota units per MC block (GRID in addon_game_mode.lua): Steve stands as tall as a Dota hero
CAM_DIST = 40  # Dota camera sits this far behind its look-at point; small = first person
MIN_PITCH = float(os.environ.get("MCDOTA_MIN_PITCH", -89))  # straight up flips the camera
# Looking up: Dota takes a negative pitch for a top-down view, but the same angle as 360 - pitch is a real upward camera
# (verified: probe projections exact at 340 and 315, a block above lines up with the crosshair). Sent signed (so
# Panorama can blend poses across the horizon); fpcam.js turns it into 360 - x.
YAW_SIGN, YAW_OFFSET = -1, 180  # Dota yaw = YAW_OFFSET + YAW_SIGN * MC yaw (calibration knob)


class Relay:
    def __init__(self):
        self.lock = threading.Lock()
        self.anchor = None  # Dota position of MC (0, GROUND_Y, 0)
        self.cam = None  # latest MC eye pose
        self.me = None  # latest "steve ..." line for Dota
        self.heroes = {}  # id -> "hero ..." line for MC
        self.to_dota, self.to_mc = [], []

    def dota(self, body):
        with self.lock:
            heroes = {}
            for line in body.splitlines():
                p = line.split()
                if not p:
                    continue
                if p[0] == "anchor" and len(p) == 4:
                    self.anchor = tuple(float(v) for v in p[1:])
                elif p[0] == "hero":
                    heroes[p[1]] = line
                elif p[0] in ("dmg", "block", "unblock", "reset", "h", "xp", "void", "border", "loot", "lvl", "delay", "trader", "dead", "respawn", "spawnat", "mcfov", "boss", "fx", "time", "fountain"):
                    self.to_mc.append(line)
                    if p[0] in ("reset", "border"):
                        print("to mc:", line, flush=True)
            self.heroes = heroes
            out = self.to_dota + ([self.me] if self.me else [])
            self.to_dota = []
            cam = self.dota_cam()
            if cam:
                out.append("cam " + cam)
            return "\n".join(out)

    def mc(self, body):
        with self.lock:
            for line in body.splitlines():
                p = line.split()
                if not p:
                    continue
                if p[0] == "me" and len(p) == 8:
                    name, x, y, z, yaw, hp, mx = p[1:]
                    self.me = f"steve {name} {x} {z} {hp} {mx} {yaw} {y}"
                elif p[0] in ("hit", "crack", "died", "swing"):
                    self.to_dota.append(line)
                elif p[0] == "set":
                    self.to_dota.append("mcblock " + " ".join(p[1:]))
                elif p[0] == "break":
                    self.to_dota.append("mcbreak " + " ".join(p[1:]))
            out = list(self.heroes.values()) + self.to_mc
            self.to_mc = []
            return "\n".join(out)

    def dota_cam(self):
        """MC eye -> Dota camera: look-at point, yaw, pitch, distance, look-at height (absolute)."""
        if not (self.cam and self.anchor):
            return ""
        x, y, z, yaw, pitch, sent = self.cam
        ax, ay, az = self.anchor
        ex, ey, ez = ax + x * SCALE, ay - z * SCALE, az + (y - GROUND_Y) * SCALE
        t, p = math.radians(yaw), math.radians(pitch)
        hx, hy = -math.sin(t), -math.cos(t)  # MC facing in Dota's x/y
        lx, ly = ex + CAM_DIST * math.cos(p) * hx, ey + CAM_DIST * math.cos(p) * hy
        lz = ez - CAM_DIST * math.sin(p)
        return f"{lx:.1f} {ly:.1f} {YAW_OFFSET + YAW_SIGN * yaw:.2f} {max(pitch, MIN_PITCH):.2f} {CAM_DIST} {lz:.1f} {sent:.2f}"


def main():
    relay = Relay()

    def udp():  # camera poses from the Fabric mod, every frame
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("127.0.0.1", 27101))
        while True:
            data = sock.recv(256).decode().split()
            if len(data) == 6:  # x y z yaw pitch millis (wall clock, so Panorama can measure the camera's lag)
                relay.cam = tuple(float(v) for v in data)
                if POSELOG:  # testing: every pose as it arrives (MCDOTA_POSELOG=<file>)
                    POSELOG.write("%.2f %s%s" % (time.perf_counter() * 1000, " ".join(data), os.linesep))
    threading.Thread(target=udp, daemon=True).start()

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
            if self.path == "/dota":  # dev/testing: each line is a Dota server console command (cheats are on in dev runs)
                with relay.lock:
                    relay.to_dota += ["dev " + l for l in body.splitlines() if l.strip()]
                reply = b"ok"
            elif self.path == "/cmd":  # dev/testing: each line is a Minecraft command (e.g. "tp @p 3 2 5 90 10")
                with relay.lock:
                    relay.to_mc += ["cmd " + l for l in body.splitlines() if l.strip()]
                reply = b"ok"
            else:
                reply = (relay.mc(body) if self.path == "/mc" else relay.dota(body)).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        def log_message(self, *a):
            pass

    print("bridge on http://127.0.0.1:27100 (/sync for Dota, /mc for Minecraft), camera UDP :27101", flush=True)
    # no address reuse: on Windows it lets a second bridge bind the same port and split the traffic between them
    # (Dota's messages went to one bridge, Minecraft polled another); now a second copy fails to start instead
    ThreadingHTTPServer.allow_reuse_address = False
    ThreadingHTTPServer(("127.0.0.1", 27100), H).serve_forever()


if __name__ == "__main__":
    main()

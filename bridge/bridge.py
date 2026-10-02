# Minecraft <-> Dota bridge. Talks RCON to a vanilla Minecraft server and HTTP to the Dota custom game.
# Dota POSTs /sync ~10x/s with lines:   hero <id> <name> <x> <z> <hp> <maxhp>   (MC coordinates)
#                                        dmg <player> <amount>                   (Dota hit a Steve, MC hp units)
# and gets back lines:                   steve <player> <x> <z> <hp> <maxhp> <yaw>
#                                        hit <heroid> <amount>                   (a Steve hit a hero, MC hp units)
# Also: Dota sends "anchor <x> <y> <z>" (where MC 0,0 is on the Dota map). The Fabric mod sends its camera over UDP
# :27101 as "<x> <y> <z> <yaw> <pitch>" (MC eye), and Dota's Panorama GETs /cam to put Dota's camera at that eye.
# Run: python bridge/bridge.py   (reads rcon.password from mc_server/server.properties)
import math, os, re, socket, struct, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
PROPS = os.path.join(HERE, "..", "mc_server", "server.properties")
GROUND_Y = -60  # flat world surface
HERO_HP = 1024  # MC health of a hero stand-in; damage is read as the drop from this, then reset
SCALE = 64  # Dota units per MC block (same as mc_bridge.lua)
CAM_DIST = 40  # Dota camera sits this far behind its look-at point; small = first person
MIN_PITCH = 5
YAW_SIGN, YAW_OFFSET = -1, 180  # Dota yaw = YAW_OFFSET + YAW_SIGN * MC yaw (calibration knob)


class Rcon:
    def __init__(self, port, password):
        self.s = socket.create_connection(("127.0.0.1", port))
        self.lock = threading.Lock()
        self.cmd(password, kind=3)

    def cmd(self, text, kind=2):
        with self.lock:
            body = text.encode() + b"\0\0"
            self.s.sendall(struct.pack("<iii", len(body) + 8, 1, kind) + body)
            n = struct.unpack("<i", self._read(4))[0]
            data = self._read(n)
            if kind == 3 and struct.unpack("<i", data[:4])[0] == -1:
                raise SystemExit("RCON auth failed")
            return data[8:-2].decode("utf-8", "replace")

    def _read(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.s.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("RCON closed")
            buf += chunk
        return buf


NUM = r"(-?[\d.]+(?:E-?\d+)?)[dfFD]?"


def numbers(text):
    return [float(x) for x in re.findall(NUM, text.split(":", 1)[-1])]


class Bridge:
    def __init__(self, rcon):
        self.rcon = rcon
        self.heroes = set()  # hero ids that have a stand-in in MC
        self.anchor = None  # Dota position of MC (0, GROUND_Y, 0)
        self.cam = None  # latest MC eye pose
        for rule in ("doMobSpawning false", "spawn_mobs false", "doDaylightCycle false", "advance_time false"):
            rcon.cmd("gamerule " + rule)  # old and new gamerule names; the wrong one just errors
        rcon.cmd("difficulty easy")  # peaceful forbids summoning the hero stand-ins
        rcon.cmd("forceload add -160 -160 159 159")  # arena stays loaded with no player nearby
        rcon.cmd("kill @e[tag=dota]")
        for x in range(-160, 160, 24):  # Minecraft's ground becomes invisible barriers so Dota's map shows (see Arena.java)
            rcon.cmd(f"fill {x} -64 -160 {x + 23} -61 159 minecraft:barrier")

    def sync(self, body):
        out = []
        for line in body.splitlines():
            p = line.split()
            if p and p[0] == "hero" and len(p) == 7:
                out += self.hero(p[1], p[2], float(p[3]), float(p[4]))
            elif p and p[0] == "anchor" and len(p) == 4:
                self.anchor = tuple(float(v) for v in p[1:])
            elif p and p[0] == "dmg" and len(p) == 3:
                self.rcon.cmd(f"damage {p[1]} {float(p[2]):.2f} minecraft:mob_attack")
        players = self.rcon.cmd("list").split(":", 1)[-1]
        for name in filter(None, (n.strip() for n in players.split(","))):
            pos = numbers(self.rcon.cmd(f"data get entity {name} Pos"))
            hp = numbers(self.rcon.cmd(f"data get entity {name} Health"))
            rot = numbers(self.rcon.cmd(f"data get entity {name} Rotation"))
            if len(pos) == 3 and hp:
                out.append(f"steve {name} {pos[0]:.2f} {pos[2]:.2f} {hp[0]:.1f} 20 {rot[0] if rot else 0:.0f}")
        cam = self.dota_cam()  # Panorama can't do HTTP any more, so the camera rides along with the sync reply
        if cam:
            out.append("cam " + cam)
        if os.environ.get("MC_FAKE_STEVE"):  # test without a Minecraft client: a Steve walking in a circle
            t = time.time() / 4
            out.append(f"steve FakeSteve {6 * math.cos(t):.2f} {6 * math.sin(t):.2f} 20 20 {math.degrees(t) % 360:.0f}")
        return "\n".join(out)

    def dota_cam(self):
        """MC eye -> Dota camera: look-at point, yaw, pitch, distance, height offset above the anchor's ground."""
        if not (self.cam and self.anchor):
            return ""
        x, y, z, yaw, pitch = self.cam
        ax, ay, az = self.anchor
        ex, ey, ez = ax + x * SCALE, ay - z * SCALE, az + (y - GROUND_Y) * SCALE
        t, p = math.radians(yaw), math.radians(pitch)
        hx, hy = -math.sin(t), -math.cos(t)  # MC facing in Dota's x/y
        lx, ly = ex + CAM_DIST * math.cos(p) * hx, ey + CAM_DIST * math.cos(p) * hy
        lz = ez - CAM_DIST * math.sin(p)
        dota_pitch = max(pitch, MIN_PITCH)  # Dota's camera misbehaves at <= 0 (looks straight down); it can't look up
        return f"{lx:.1f} {ly:.1f} {YAW_OFFSET + YAW_SIGN * yaw:.2f} {dota_pitch:.2f} {CAM_DIST} {lz - az:.1f}"

    def hero(self, hid, name, x, z):
        sel = f"@e[tag=dota_{hid},limit=1]"
        if hid not in self.heroes:
            self.heroes.add(hid)
            self.rcon.cmd(
                f'summon minecraft:husk {x} {GROUND_Y} {z} {{NoAI:1b,Silent:1b,PersistenceRequired:1b,'
                f'Tags:["dota","dota_{hid}"],CustomName:"{name}",CustomNameVisible:1b,'
                f'attributes:[{{id:"minecraft:max_health",base:{HERO_HP}}}],Health:{HERO_HP}f}}')
        self.rcon.cmd(f"tp {sel} {x} {GROUND_Y} {z}")
        hp = numbers(self.rcon.cmd(f"data get entity {sel} Health"))
        if not hp:  # stand-in died in MC (or got lost): respawn next tick
            self.heroes.discard(hid)
            return []
        if hp[0] < HERO_HP:
            self.rcon.cmd(f"data merge entity {sel} {{Health:{HERO_HP}f}}")
            return [f"hit {hid} {HERO_HP - hp[0]:.2f}"]
        return []


def main():
    props = dict(l.strip().split("=", 1) for l in open(PROPS) if "=" in l and not l.startswith("#"))
    bridge = Bridge(Rcon(int(props["rcon.port"]), props["rcon.password"]))

    def udp():  # camera poses from the Fabric mod, every frame
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.bind(("127.0.0.1", 27101))
        while True:
            data = sock.recv(256).decode().split()
            if len(data) == 5:
                bridge.cam = tuple(float(v) for v in data)
    threading.Thread(target=udp, daemon=True).start()

    class H(BaseHTTPRequestHandler):
        def do_GET(self):  # Panorama polls the camera
            reply = bridge.dota_cam().encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        def do_POST(self):
            body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
            try:
                reply, code = bridge.sync(body).encode(), 200
            except Exception as e:  # keep the bridge alive; Dota just retries next tick
                reply, code = f"error {e}".encode(), 500
            self.send_response(code)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(reply)))
            self.end_headers()
            self.wfile.write(reply)

        def log_message(self, *a):
            pass

    print("bridge on http://127.0.0.1:27100/sync", flush=True)
    ThreadingHTTPServer(("127.0.0.1", 27100), H).serve_forever()


if __name__ == "__main__":
    main()

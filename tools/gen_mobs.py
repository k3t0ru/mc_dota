# Radiant's creeps as Minecraft mobs (Dota models): zombie (melee), skeleton (ranged), a spider jockey (siege: a
# skeleton riding a spider), zombie in gold armour (the flag bearer). Geometry and UVs follow Minecraft's entity models and
# ModelPart.Cube (like tools/gen_villager.py), textures from the local Minecraft jar (Mojang's: local, gitignored).
# Skinned models with bones (head, body, arms, legs, the spider's legs) and animations Dota itself plays on the client:
# idle, run, attack (activities ACT_DOTA_IDLE / RUN / ATTACK), smooth at any frame rate. (They were pose frames swapped by
# Lua: server ticks, sent over the network, uneven: they jerked.) Source's SMD format, compiled by ModelDoc.
# Output: content/models/mc/mob_<name>.vmdl + mob_<name>[_<anim>].smd, content/materials/mc/mob_<tex>.{png,vmat}.
# Faces Dota +X, feet at 0, 16 model pixels = one block (GRID 96).
import glob, io, math, os, zipfile
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "content")
MAT, MDL = os.path.join(ROOT, "materials", "mc"), os.path.join(ROOT, "models", "mc")
PX, UP = 96 / 16, 8
FWD = -math.pi / 2  # arms held forward (zombies, the skeleton's bow arm)
FPS = 30

import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import mcjar
jar = zipfile.ZipFile(mcjar.path())
def png(p): return Image.open(io.BytesIO(jar.read("assets/minecraft/textures/" + (p[3:] if p.startswith("../") else "entity/" + p)))).convert("RGBA")

# box: (texture, (u, v), min, size, inflation, pivot, turn, bone); y down, the face looks to -z, feet at y 24. A "sprite"
# (an item: the skeleton's bow) is a flat picture: ("item:<texture>", None, min, size with one 0, 0, pivot, turn, bone).
# A pose = (leg, arm): legs swing by `leg`, arms by `arm` (an attack). Each bone's turn in a pose comes from its first box.
def humanoid(t, arms=FWD, inflate=0.0, legs=True, head=True, body=True, leg=0.0, arm=0.0):
    b = []
    if head: b += [(t, (0, 0), (-4, -8, -4), (8, 8, 8), inflate, (0, 0, 0), 0, "head")]
    if body: b += [(t, (16, 16), (-4, 0, -2), (8, 12, 4), inflate, (0, 0, 0), 0, "body")]
    if arms is not None:
        b += [(t, (40, 16), (-3, -2, -2), (4, 12, 4), inflate, (-5, 2, 0), arms + arm, "arm_r"),
              (t, (40, 16), (-1, -2, -2), (4, 12, 4), inflate, (5, 2, 0), arms + arm, "arm_l")]
    if legs:
        b += [(t, (0, 16), (-2, 0, -2), (4, 12, 4), inflate, (-1.9, 12, 0), leg, "leg_r"),
              (t, (0, 16), (-2, 0, -2), (4, 12, 4), inflate, (1.9, 12, 0), -leg, "leg_l")]
    return b


def bow(pivot, turn, hand):
    # the bow in the right hand at the end of an arm held forward: an upright picture, its length along the arm's way
    # (the bow is drawn diagonally in its picture: a quarter turn of that upright, its grip in the hand). Its string is
    # its own: two threads from the bow's tips to the left hand (hand = the left arm's pivot and turn), stretched as the
    # hand pulls back. (Minecraft's bow_pulling pictures swapped by moving the unshown ones away: the swaps showed.)
    x, y, z = pivot
    off, rot = (x, y + 1, z - 10), (turn + 0.785, 0, 0)
    return [("item:bow_nostring", None, (0, -8, -8), (0, 16, 16), 0, off, rot, "arm_r"),
            ("@string", None, STRING_TIPS[0], STRING_TIPS[1], hand, off, rot, "arm_r")]


def skeleton(leg=0.0, arm=0.0, dy=0, legs_pose=None):
    # arm: the bow's draw, 0 = held, 1 = the string pulled: both arms forward like Minecraft's aiming skeleton, the left
    # hand on the string, pulling it back toward the chin
    a = min(1, arm)
    left, lz = (FWD, 0.5, 0), 3.5 * a  # (the left shoulder draws back: a straight arm can't bend at the elbow)
    b = [("skeleton", (0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, dy, 0), 0, "head"),
         ("skeleton", (16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, dy, 0), 0, "body"),
         ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (-5, 2 + dy, 0), FWD, "arm_r"),
         ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (5, 2 + dy, lz), left, "arm_l")]
    b += bow((-5, 2 + dy, 0), 0, ((5, 2 + dy, lz), left))
    if legs_pose: b += legs_pose
    else:
        b += [("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (-2, 12 + dy, 0), leg, "leg_r"),
              ("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (2, 12 + dy, 0), -leg, "leg_l")]
    return b


def spider_jockey(leg=0.0, arm=0.0):
    b = [("spider", (32, 4), (-4, -4, -8), (8, 8, 8), 0, (0, 15, -3), 0, "s_head"),
         ("spider", (0, 0), (-3, -3, -3), (6, 6, 6), 0, (0, 15, 0), 0, "s_neck"),
         ("spider", (0, 12), (-5, -4, -6), (10, 8, 12), 0, (0, 15, 9), 0, "s_body")]
    for i, (z, ry, rz) in enumerate(((2, 0.7854, 0.7854), (1, 0.3927, 0.5809), (0, -0.3927, 0.5809), (-1, -0.7854, 0.7854))):
        for side in (-1, 1):
            swing = leg * (1 if (i + (side > 0)) % 2 else -1)  # alternate legs step together
            lift = abs(leg) * 0.35 * (1 if swing > 0 else 0)  # a stepping leg comes up a little
            b.append(("spider", (18, 0), (-15, -1, -1) if side < 0 else (-1, -1, -1), (16, 2, 2), 0, (4 * side, 15, z),
                      (0, (ry + swing) * -side, (rz + lift) * side), f"s_leg{i}{'r' if side < 0 else 'l'}"))
    # the rider: sitting on the spider's back, legs forward
    b += skeleton(arm=arm / 0.8, dy=-1, legs_pose=[("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (-2, 11, 2), (-1.4, 0.3, 0), "leg_r"),
                                             ("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (2, 11, 2), (-1.4, -0.3, 0), "leg_l")])
    return b


def pig(leg):
    t = "pig"
    return [(t, (0, 0), (-4, -4, -8), (8, 8, 8), 0, (0, 12, -6), 0, "head"),
            (t, (16, 16), (-2, 0, -9), (4, 3, 1), 0, (0, 12, -6), 0, "head"),
            (t, (28, 8), (-5, -10, -7), (10, 16, 8), 0, (0, 11, 2), math.pi / 2, "body"),
            (t, (0, 16), (-2, 0, -2), (4, 6, 4), 0, (-3, 18, 7), leg, "leg0"),
            (t, (0, 16), (-2, 0, -2), (4, 6, 4), 0, (3, 18, 7), -leg, "leg1"),
            (t, (0, 16), (-2, 0, -2), (4, 6, 4), 0, (-3, 18, -5), -leg, "leg2"),
            (t, (0, 16), (-2, 0, -2), (4, 6, 4), 0, (3, 18, -5), leg, "leg3")]


def chicken(leg):
    t = "chicken"
    return [(t, (0, 0), (-2, -6, -2), (4, 6, 3), 0, (0, 15, -4), 0, "head"),
            (t, (14, 0), (-2, -4, -4), (4, 2, 2), 0, (0, 15, -4), 0, "head"),
            (t, (14, 4), (-1, -2, -3), (2, 2, 2), 0, (0, 15, -4), 0, "head"),
            (t, (0, 9), (-3, -4, -3), (6, 8, 6), 0, (0, 16, 0), math.pi / 2, "body"),
            (t, (26, 0), (-1, 0, -3), (3, 5, 3), 0, (-2, 19, 1), leg, "leg0"),
            (t, (26, 0), (-1, 0, -3), (3, 5, 3), 0, (1, 19, 1), -leg, "leg1"),
            (t, (24, 13), (0, 0, -3), (1, 4, 6), 0, (-4, 13, 0), (0, 0, abs(leg)), "wing0"),
            (t, (24, 13), (-1, 0, -3), (1, 4, 6), 0, (4, 13, 0), (0, 0, -abs(leg)), "wing1")]


def zombie(leg, arm):
    return humanoid("zombie", leg=leg, arm=arm + 0.12 * leg) + [("zombie", (32, 0), (-4, -8, -4), (8, 8, 8), 0.5, (0, 0, 0), 0, "head")]


def zombie_gold(leg, arm):
    return zombie(leg, arm) + humanoid("gold", inflate=1.0, legs=False, arm=arm + 0.12 * leg) + \
        [("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (-1.9, 12, 0), leg, "leg_r"),
         ("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (1.9, 12, 0), -leg, "leg_l")]


def held_transform(pivot):
    # Minecraft's third-person right hand (ItemInHandLayer + the "handheld" display): from the arm's pivot, turned
    # -90 about x and 180 about y, moved (1, 2, -10) px, then (0, 4, 0.5) px, turned (0, -90, 55) degrees (x, y, z),
    # scaled 0.85, the item's picture centred. The picture here: x across, y down the picture, z along it.
    def rx(a): c, s_ = math.cos(a), math.sin(a); return [[1, 0, 0], [0, c, -s_], [0, s_, c]]
    def ry(a): c, s_ = math.cos(a), math.sin(a); return [[c, 0, s_], [0, 1, 0], [-s_, 0, c]]
    def rz(a): c, s_ = math.cos(a), math.sin(a); return [[c, -s_, 0], [s_, c, 0], [0, 0, 1]]
    A = mat_mul(rx(math.radians(-90)), ry(math.radians(180)))
    D = mat_mul(rx(0), mat_mul(ry(math.radians(-90)), rz(math.radians(55))))
    P = [[0, 0, 1], [0, -1, 0], [1, 0, 0]]  # (picture x along, y down) -> item (x right, y up, z out)
    rot = mat_mul(A, mat_mul(D, [[0.85 * v for v in row] for row in P]))
    c = mat_vec(A, (1, 6, -9.5))
    return tuple(p + q for p, q in zip(pivot, c)), rot


def steve(leg, arm, mode="stand", elytra=False, item=None):
    # Minecraft's PlayerModel (wide arms) with its outer layers, in its poses (the Dota players' view of Steve,
    # MCBridge:Puppet): walking (arms swing against the legs), a hit (the right arm swings), sneaking (bent forward,
    # Minecraft's crouch offsets), drawing a bow (both arms forward), elytra flight (lying forward, wings spread).
    # elytra: worn (folded on his back, spread in flight)
    t = "steve"
    hy, by, ay, ly, lz, bend, lift = 0, 0, 2, 12, 0, 0, 0
    if mode == "sneak": hy, by, ay, ly, lz, bend, lift = 4.2, 3.2, 5.2, 12.2, 4, 0.5, 0.4
    rarm, larm = -0.8 * leg + lift, 0.8 * leg + lift
    body_rot = bend
    rx = lx = 0
    if mode == "swing":
        tt = arm
        by_ = math.sin(math.sqrt(tt) * 2 * math.pi) * 0.2
        f = 1 - (1 - tt) ** 4
        rarm = (-(math.sin(f * math.pi) * 1.2 + math.sin(tt * math.pi) * 0.525), 3 * by_, -0.4 * math.sin(tt * math.pi))
        larm = (by_, by_, 0)
        body_rot = (0, by_, 0)
        rx, lx = math.sin(by_) * 5, -math.sin(by_) * 5  # (the shoulders turn with the body: their z)
    if mode == "bow": rarm, larm = (FWD, -0.1, 0), (FWD, 0.5, 0)
    if mode == "fly": rarm, larm = 0.0, 0.0
    b = [(t, (0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, hy, 0), 0, "head"),
         (t, (32, 0), (-4, -8, -4), (8, 8, 8), 0.5, (0, hy, 0), 0, "head"),
         (t, (16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, by, 0), body_rot, "body"),
         (t, (16, 32), (-4, 0, -2), (8, 12, 4), 0.25, (0, by, 0), body_rot, "body"),
         (t, (40, 16), (-3, -2, -2), (4, 12, 4), 0, (-5, ay, rx), rarm, "arm_r"),
         (t, (40, 32), (-3, -2, -2), (4, 12, 4), 0.25, (-5, ay, rx), rarm, "arm_r"),
         (t, (32, 48), (-1, -2, -2), (4, 12, 4), 0, (5, ay, lx), larm, "arm_l"),
         (t, (48, 48), (-1, -2, -2), (4, 12, 4), 0.25, (5, ay, lx), larm, "arm_l"),
         (t, (0, 16), (-2, 0, -2), (4, 12, 4), 0, (-1.9, ly, lz), leg, "leg_r"),
         (t, (0, 32), (-2, 0, -2), (4, 12, 4), 0.25, (-1.9, ly, lz), leg, "leg_r"),
         (t, (16, 48), (-2, 0, -2), (4, 12, 4), 0, (1.9, ly, lz), -leg, "leg_l"),
         (t, (0, 48), (-2, 0, -2), (4, 12, 4), 0.25, (1.9, ly, lz), -leg, "leg_l")]
    if item:  # the item in his right hand: its picture upright along the arm's side, the handle in the hand, pointing forward
        off, rot = held_transform((-5, ay, rx))
        b.append(("item:" + item, None, (0, -8, -8), (0, 16, 16), 0, off, rot, "arm_r"))
    if elytra:  # Minecraft's ElytraModel, on the back (2 px behind the body)
        x, z = (0.349, -math.pi / 2) if mode == "fly" else (0.2618 + bend, -0.2618)
        b += [("elytra", (22, 0), (-10, 0, 0), (10, 20, 2), 1.0, (5, by, 2), (x, 0, z), "wing_l"),
              ("elytra", (22, 0), (0, 0, 0), (10, 20, 2), 1.0, (-5, by, 2), (x, 0, -z), "wing_r")]
    if mode == "fly":  # the whole body lying forward, head first, turned about its middle
        g, c = mc_rot(math.pi / 2), (0, 12, 0)
        out = []
        for tex, uv, mn, size, inf, piv, rot, bone in b:
            d = mat_vec(g, tuple(q - o for q, o in zip(piv, c)))
            out.append((tex, uv, mn, size, inf, tuple(o + q for o, q in zip(c, d)), mat_mul(g, mc_rot(rot)), bone))
        b = out
    return b


MOB_BUILD = {"pig": lambda leg, arm: pig(leg), "chicken": lambda leg, arm: chicken(leg), "zombie": zombie, "skeleton": lambda leg, arm: skeleton(leg, arm / 0.8), "spider_jockey": spider_jockey,
             "zombie_gold": zombie_gold}
TEXTURES = {"zombie": "zombie/zombie.png", "skeleton": "skeleton/skeleton.png", "spider": "spider/spider.png",
            "gold": "equipment/humanoid/gold.png", "item:bow": "../item/bow.png", "steve": "player/wide/steve.png",
            "elytra": "equipment/wings/elytra.png", "pig": "pig/temperate_pig.png", "chicken": "chicken/temperate_chicken.png",
            "item:bow_pulling_0": "../item/bow_pulling_0.png", "item:bow_pulling_1": "../item/bow_pulling_1.png",
            "item:bow_pulling_2": "../item/bow_pulling_2.png"}
# what Steve may hold, shown in his hand to Dota's players (Minecraft's item pictures): his tools and weapons, what the
# traders sell. A model of him for each (and with an elytra); "bow_pulling_2" is the bow while he draws it.
HELD = {}
for tier in ("wooden", "stone", "iron", "golden", "diamond", "netherite"):
    for tool in ("sword", "pickaxe", "axe", "shovel", "hoe"):
        HELD[f"{tier}_{tool}"] = f"{tier}_{tool}"
for i in ("bow", "bow_pulling_0", "bow_pulling_1", "bow_pulling_2", "flint_and_steel", "ender_pearl", "firework_rocket", "potion", "splash_potion", "golden_apple",
          "bread", "cooked_beef", "golden_carrot", "emerald", "arrow", "elytra", "stick", "diamond", "iron_ingot", "flint",
          "book", "enchanted_book", "feather", "string", "paper", "leather", "gunpowder", "lapis_lazuli", "netherite_ingot",
          "mace", "wind_charge", "shield"):
    HELD[i] = i
HELD.update({"torch": "../block/torch", "soul_torch": "../block/soul_torch", "crossbow": "crossbow_standby", "clock": "clock_00"})
HELD = {k: v for k, v in HELD.items() if f"assets/minecraft/textures/item/{v}.png".replace("item/../", "") in jar.namelist()}
for k, v in HELD.items():
    TEXTURES["item:" + k] = "../" + ("item/" + v if not v.startswith("../") else v[3:]) + ".png"
for elytra in (False, True):
    for item in [None] + list(HELD):
        MOB_BUILD["steve" + ("_elytra" if elytra else "") + (f"__{item}" if item else "")] = \
            (lambda e, it: lambda leg, arm, mode="stand": steve(leg, arm, mode, e, it))(elytra, item)

# animations: (activity, seconds, looping, pose at a moment 0..1) -- like Minecraft's: a walk is a sine of the legs (arms
# swaying with them for zombies), idle arms bob slowly, an attack swings the arms down (zombies) or draws the bow
WALK = 0.75  # one stride (both legs) at a creep's pace: ~3.4 blocks a second, Minecraft's 2.4 blocks a stride
ANIMS = [
    ("idle", "ACT_DOTA_IDLE", 3.0, True, lambda k: (0, 0.06 * math.sin(2 * math.pi * k))),
    ("run", "ACT_DOTA_RUN", WALK, True, lambda k: (0.75 * math.sin(2 * math.pi * k), 0)),
    ("attack", "ACT_DOTA_ATTACK", 0.6, False, lambda k: (0, 0.9 * math.sin(math.pi * min(1, k / 0.8)))),
    ("stunned", "ACT_DOTA_DISABLED", 3.0, True, lambda k: (0, 0.06 * math.sin(2 * math.pi * k))),
]
# Steve's own: what Minecraft's player does (the pose in Minecraft's "me" line, MCBridge:Puppet)
STEVE_ANIMS = [
    ("sneak_idle", "", 3.0, True, lambda k: (0, 0, "sneak")),
    ("sneak_run", "", 1.2, True, lambda k: (0.5 * math.sin(2 * math.pi * k), 0, "sneak")),
    ("fly", "", 1.0, True, lambda k: (0.08 * math.sin(2 * math.pi * k), 0, "fly")),
    ("bow", "", 1.0, True, lambda k: (0, 0, "bow")),
    # (Minecraft's swing takes 0.3 s; then it holds still: Dota's particle ran it twice in the time Lua shows it)
    ("attack", "ACT_DOTA_ATTACK", 0.6, False, lambda k: (0, min(1, 2 * k), "swing")),
]
def anims_for(name):
    if not name.startswith("steve"): return ANIMS
    return [a for a in ANIMS if a[0] != "attack"] + STEVE_ANIMS


# --- space: Minecraft model pixels (y down, face -z) -> Dota units (z up, face +X) ---
def mat_mul(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def mat_t(a): return [list(r) for r in zip(*a)]
def mat_vec(a, v): return tuple(sum(a[i][k] * v[k] for k in range(3)) for i in range(3))


def mc_rot(rot):
    """rot: an x turn, or (x, y, z) turns applied like Minecraft's ModelPart (Rz * Ry * Rx), as a matrix."""
    if isinstance(rot, list): return rot
    rx, ry, rz = rot if isinstance(rot, tuple) else (rot, 0, 0)
    c, s = math.cos(rx), math.sin(rx); X = [[1, 0, 0], [0, c, -s], [0, s, c]]
    c, s = math.cos(ry), math.sin(ry); Y = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    c, s = math.cos(rz), math.sin(rz); Z = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    return mat_mul(Z, mat_mul(Y, X))


# Minecraft (x, y, z) -> the SMD's space: x, z across, -y up (the face, Minecraft -z, to -Y). Dota's import then turns the
# model a quarter, (x, y) -> (-y, x), like it did the OBJs: the face ends up looking to Dota +X. (Turned here as well,
# the mobs walked sideways.) Hitboxes are in the final space: TURN.
M = [[1, 0, 0], [0, 0, 1], [0, -1, 0]]
def TURN(p): return (-p[1], p[0], p[2])


def dota_point(p, off, rot):
    x, y, z = mat_vec(mc_rot(rot), p)
    q = mat_vec(M, (x + off[0], y + off[1] - 24, z + off[2]))
    return (q[0] * PX, q[1] * PX, q[2] * PX)


def dota_pivot(off):
    q = mat_vec(M, (off[0], off[1] - 24, off[2]))
    return (q[0] * PX, q[1] * PX, q[2] * PX)


def euler(m):
    """A Dota-space rotation matrix as Source's SMD angles (x, y, z radians: R = Rz * Ry * Rx)."""
    y = math.asin(max(-1, min(1, -m[2][0])))
    if abs(m[2][0]) < 0.9999:
        return (math.atan2(m[2][1], m[2][2]), y, math.atan2(m[1][0], m[0][0]))
    return (math.atan2(-m[1][2], m[1][1]), y, 0.0)


def bones_of(boxes):
    order, first = [], {}
    for b in boxes:
        if b[7] not in first:
            first[b[7]] = b
            order.append(b[7])
    return order, first


def mesh_smd(boxes, sizes, order):
    # (every bone at the top: a root bone was dropped by the compiler and the vertices' bones shifted by one)
    lines = ["version 1", "nodes"] + [f'{i} "{n}" -1' for i, n in enumerate(order)] + ["end", "skeleton", "time 0"]
    first = bones_of(boxes)[1]
    for i, n in enumerate(order):
        x, y, z = dota_pivot(first[n][5])
        lines.append(f"{i} {x:.4f} {y:.4f} {z:.4f} 0 0 0")
    lines += ["end", "triangles"]
    lo, hi = [1e9] * 3, [-1e9] * 3
    for tex, uv0, (x0, y0, z0), (w, h, d), g, off, rot, bone in boxes:
        if tex == "@string":
            hoff, hrot = g
            hand = dota_point((0, 10, 0), hoff, hrot)
            hb, bb = order.index("arm_l"), order.index(bone)
            for tip_local in ((x0, y0, z0), (w, h, d)):
                tip = dota_point(tip_local, off, rot)
                dvec = [q - p for p, q in zip(tip, hand)]
                for axis in ((0, 0, 1), (1, 0, 0)):
                    wv = (dvec[1] * axis[2] - dvec[2] * axis[1], dvec[2] * axis[0] - dvec[0] * axis[2], dvec[0] * axis[1] - dvec[1] * axis[0])
                    ln = math.sqrt(sum(c * c for c in wv)) or 1
                    wv = [c / ln * 0.25 * PX for c in wv]
                    quad = [([tip[k] - wv[k] for k in range(3)], bb), ([tip[k] + wv[k] for k in range(3)], bb),
                            ([hand[k] + wv[k] for k in range(3)], hb), ([hand[k] - wv[k] for k in range(3)], hb)]
                    for tri in ((0, 1, 2), (0, 2, 3)):
                        lines.append("materials/mc/mob_string.vmat")
                        for k in tri:
                            (vx, vy, vz), vb = quad[k]
                            lines.append(f"{vb} {vx:.4f} {vy:.4f} {vz:.4f} 0 0 1 0.5 0.5")
            continue
        tw, th = sizes[tex]
        bi = order.index(bone)
        quads = []
        centre = dota_point((x0 + w / 2, y0 + h / 2, z0 + d / 2), off, rot)
        if uv0 is None:  # a sprite: the whole picture on a flat quad (both sides drawn: the material renders backfaces)
            if w == 0:  # (all the items are pictures across x: extruded along x)
                t = d / 16 / 2
                for xs in (x0 - t, x0 + t):
                    c = [(xs, y0, z0), (xs, y0, z0 + d), (xs, y0 + h, z0 + d), (xs, y0 + h, z0)]
                    quads.append(([dota_point(q, off, rot) for q in c], [(0, 1), (1, 1), (1, 0), (0, 0)]))
                img = IMAGES[tex]
                W, Hh = img.size
                a = img.split()[3].load()
                solid = lambda i, j: 0 <= i < W and 0 <= j < Hh and a[i, j] > 127
                for j in range(Hh):
                    for i in range(W):
                        if not solid(i, j): continue
                        za, zb = z0 + i * d / W, z0 + (i + 1) * d / W
                        ya, yb = y0 + j * h / Hh, y0 + (j + 1) * h / Hh
                        uv = ((i + 0.5) / W, 1 - (j + 0.5) / Hh)
                        for di, dj, c in ((-1, 0, [(x0 - t, ya, za), (x0 + t, ya, za), (x0 + t, yb, za), (x0 - t, yb, za)]),
                                          (1, 0, [(x0 - t, ya, zb), (x0 - t, yb, zb), (x0 + t, yb, zb), (x0 + t, ya, zb)]),
                                          (0, -1, [(x0 - t, ya, za), (x0 - t, ya, zb), (x0 + t, ya, zb), (x0 + t, ya, za)]),
                                          (0, 1, [(x0 - t, yb, za), (x0 + t, yb, za), (x0 + t, yb, zb), (x0 - t, yb, zb)])):
                            if not solid(i + di, j + dj):
                                quads.append(([dota_point(q, off, rot) for q in c], [uv] * 4))
            else:
                if d == 0: c = [(x0, y0, z0), (x0 + w, y0, z0), (x0 + w, y0 + h, z0), (x0, y0 + h, z0)]
                else: c = [(x0, y0, z0), (x0 + w, y0, z0), (x0 + w, y0, z0 + d), (x0, y0, z0 + d)]
                quads.append(([dota_point(q, off, rot) for q in c], [(0, 1), (1, 1), (1, 0), (0, 0)]))
        else:
            u, v = uv0
            x1, y1, z1 = x0 + w + g, y0 + h + g, z0 + d + g
            x0, y0, z0 = x0 - g, y0 - g, z0 - g
            c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
            u0, u1, u2, u3, u4, u5 = u, u + d, u + d + w, u + d + w + w, u + d + w + d, u + d + w + d + w
            v0, v1, v2 = v, v + d, v + d + h
            for idx, (ua, va, ub, vb) in [((5, 1, 2, 6), (u2, v1, u4, v2)), ((0, 4, 7, 3), (u0, v1, u1, v2)),
                                          ((5, 4, 0, 1), (u1, v0, u2, v1)), ((2, 3, 7, 6), (u2, v1, u3, v0)),
                                          ((1, 0, 3, 2), (u1, v1, u2, v2)), ((4, 5, 6, 7), (u4, v1, u5, v2))]:
                pts = [dota_point(c[k], off, rot) for k in idx][::-1]
                tcs = [(tu / tw, 1 - tv / th) for tu, tv in ((ub, va), (ua, va), (ua, vb), (ub, vb))][::-1]
                quads.append((pts, tcs))
        for pts, tcs in quads:
            for p in pts:
                for k in range(3): lo[k], hi[k] = min(lo[k], p[k]), max(hi[k], p[k])
            a, b, c3 = pts[0], pts[1], pts[2]
            n = ((b[1] - a[1]) * (c3[2] - a[2]) - (b[2] - a[2]) * (c3[1] - a[1]),
                 (b[2] - a[2]) * (c3[0] - a[0]) - (b[0] - a[0]) * (c3[2] - a[2]),
                 (b[0] - a[0]) * (c3[1] - a[1]) - (b[1] - a[1]) * (c3[0] - a[0]))
            ln = math.sqrt(sum(x * x for x in n)) or 1
            n = tuple(x / ln for x in n)
            mid = [sum(p[k] for p in pts) / 4 for k in range(3)]
            if uv0 is not None and sum((mid[k] - centre[k]) * n[k] for k in range(3)) < 0: n = tuple(-x for x in n)
            for tri in ((0, 1, 2), (0, 2, 3)):
                lines.append("materials/mc/mob_" + tex.replace("item:", "") + ".vmat")
                for k in tri:
                    p, t = pts[k], tcs[k]
                    lines.append(f"{bi} {p[0]:.4f} {p[1]:.4f} {p[2]:.4f} {n[0]:.4f} {n[1]:.4f} {n[2]:.4f} {t[0]:.5f} {t[1]:.5f}")
    lines.append("end")
    return "\n".join(lines) + "\n", (lo, hi)


def anim_smd(build, order, rest, pose, seconds, looping):
    # each bone: its turn in this pose relative to the rest pose (the mesh is the rest pose), about its own pivot
    fps = anim_fps(seconds, looping)
    frames = max(2, round(seconds * fps)) + (1 if looping else 0)
    first_rest = bones_of(rest)[1]
    lines = ["version 1", "nodes"] + [f'{i} "{n}" -1' for i, n in enumerate(order)] + ["end", "skeleton"]
    for f in range(frames):
        k = f / (frames - 1) if not looping else f / (frames - 1)
        boxes = build(*pose(k))
        first = bones_of(boxes)[1]
        lines.append(f"time {f}")
        for i, n in enumerate(order):
            r0, r1 = mc_rot(first_rest[n][6]), mc_rot(first[n][6])
            delta = mat_mul(M, mat_mul(mat_mul(r1, mat_t(r0)), mat_t(M)))
            ax, ay, az = euler(delta)
            x, y, z = dota_pivot(first[n][5])
            lines.append(f"{i} {x:.4f} {y:.4f} {z:.4f} {ax:.5f} {ay:.5f} {az:.5f}")
    lines.append("end")
    return "\n".join(lines) + "\n"


def anim_fps(seconds, looping): return FPS


def kv_vec(v): return "[ " + ", ".join(f"{x:.2f}" for x in v) + " ]"


def vmdl(name, used, lo, hi, attachments, material=None):
    remaps = " ".join(f'{{ from = "materials/mc/mob_{t}.vmat" to = "{material or f"materials/mc/mob_{t}.vmat"}" }},' for t in used)
    anims = ""
    for an, act, seconds, looping, _ in anims_for(name):
        anims += f"""					{{
						_class = "AnimFile"
						name = "{an}"
						activity_name = "{act}"
						activity_weight = 1
						weight_list_name = ""
						fade_in_time = 0.2
						fade_out_time = 0.2
						looping = {'true' if looping else 'false'}
						delta = false
						worldSpace = false
						hidden = false
						anim_markup_ordered = false
						disable_compression = false
						source_filename = "models/mc/mob_{name}_{an}.smd"
						start_frame = -1
						end_frame = -1
						framerate = {anim_fps(seconds, looping)}.0
						take = 0
						reverse = false
					}},
"""
    att = ""
    for an, bone, o in attachments:
        att += f"""					{{
						_class = "Attachment"
						name = "{an}"
						parent_bone = "{bone}"
						relative_origin = {kv_vec(o)}
						relative_angles = [ 0.0, 0.0, 0.0 ]
						weight = 1.0
						ignore_rotation = false
					}},
"""
    return f"""<!-- kv3 encoding:text:version{{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d}} format:modeldoc32:version{{c5dcef98-b629-46ab-88e3-a17c005c935e}} -->
{{
	rootNode =
	{{
		_class = "RootNode"
		children =
		[
			{{
				_class = "MaterialGroupList"
				children =
				[
					{{
						_class = "DefaultMaterialGroup"
						remaps = [ {remaps} ]
						use_global_default = false
						global_default_material = ""
					}},
				]
			}},
			{{
				_class = "RenderMeshList"
				children = [ {{ _class = "RenderMeshFile" filename = "models/mc/mob_{name}.smd" import_scale = 1.0 }} ]
			}},
			{{
				_class = "AnimationList"
				children =
				[
{anims}				]
				default_root_bone_name = ""
			}},
			{{
				_class = "AttachmentList"
				children =
				[
{att}				]
			}},
			{{
				_class = "HitboxSetList"
				children =
				[
					{{
						_class = "HitboxSet"
						name = "default"
						children =
						[
							{{
								_class = "Hitbox"
								name = "body"
								parent_bone = ""
								surface_property = ""
								translation_only = false
								group_id = 0
								hitbox_mins = {kv_vec(lo)}
								hitbox_maxs = {kv_vec(hi)}
							}},
						]
					}},
				]
			}},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}}
}}
"""


os.makedirs(MAT, exist_ok=True); os.makedirs(MDL, exist_ok=True)
for old in set(glob.glob(os.path.join(MDL, "mob_*_[wa][0-9]*.*")) + glob.glob(os.path.join(MDL, "mob_*.obj"))):
    os.remove(old)  # (the pose-frame models)
sizes, IMAGES = {}, {}
_bow = png("../item/bow.png")
_px = _bow.load()
_string = [(i, j) for j in range(_bow.height) for i in range(_bow.width)
           if _px[i, j][3] > 127 and 50 <= min(_px[i, j][:3]) and max(_px[i, j][:3]) <= 90 and max(_px[i, j][:3]) - min(_px[i, j][:3]) < 8]
_nostring = _bow.copy()
for i, j in _string: _nostring.putpixel((i, j), (0, 0, 0, 0))
_string.sort(key=lambda q: q[1])  # (top tip first)
# the tips: the string's ends, in the bow picture's own place (its box: (0, -8, -8), 16 x 16; x across, z = u, y = v)
STRING_TIPS = [(0, -8 + (j + 0.5), -8 + (i + 0.5)) for i, j in (_string[0], _string[-1])] if _string else [(0, -7, -7), (0, 7, 7)]
for tex, img in (("item:bow_nostring", _nostring), ("string", Image.new("RGBA", (4, 4), (215, 215, 215, 255)))):
    TEXTURES[tex] = None
    IMAGES[tex] = img
for tex, path in TEXTURES.items():
    img = IMAGES[tex] if path is None else png(path)
    sizes[tex] = img.size
    IMAGES[tex] = img
    tex = tex.replace("item:", "")
    big = img.resize((img.width * UP, img.height * UP), Image.NEAREST)
    big.convert("RGB").save(os.path.join(MAT, f"mob_{tex}.png"))
    big.split()[3].save(os.path.join(MAT, f"mob_{tex}_alpha.png"))
    with open(os.path.join(MAT, f"mob_{tex}.vmat"), "w") as f:
        f.write(f'Layer0\n{{\n\tshader "global_lit_simple.vfx"\n\tF_SPECULAR 0\n\tF_ALPHA_TEST 1\n\tF_RENDER_BACKFACES 1\n'
                f'\tg_flAlphaTestReference "0.500"\n\tTextureColor "materials/mc/mob_{tex}.png"\n'
                f'\tTextureTranslucency "materials/mc/mob_{tex}_alpha.png"\n}}\n')
for name, build in MOB_BUILD.items():
    rest = build(0, 0)
    order, first = bones_of(rest)
    smd, (lo0, hi0) = mesh_smd(rest, sizes, order)
    a, b = TURN(lo0), TURN(hi0)
    lo, hi = tuple(min(x, y) for x, y in zip(a, b)), tuple(max(x, y) for x, y in zip(a, b))
    with open(os.path.join(MDL, f"mob_{name}.smd"), "w") as f:
        f.write(smd)
    for an, act, seconds, looping, pose in anims_for(name):
        with open(os.path.join(MDL, f"mob_{name}_{an}.smd"), "w") as f:
            f.write(anim_smd(build, order, rest, pose, seconds, looping))
    used = []
    for b in rest:
        t = b[0].replace("item:", "")
        if t not in used and not t.startswith("@"): used.append(t)
    # attachments: where a ranged attack leaves (the bow) and where attacks hit (the chest), relative to their bones
    def rel(bone, point_mc):
        p, q = dota_pivot(point_mc), dota_pivot(first[bone][5])
        return tuple(a - b for a, b in zip(p, q))
    chest = (0, 6 + (-1 if name == "spider_jockey" else 0), 0)
    att = [("attach_hitloc", "body", rel("body", chest))]
    if "arm_r" in first and name in ("skeleton", "spider_jockey"):
        hand = dota_point((0, 10, 0), first["arm_r"][5], first["arm_r"][6])
        att += [("attach_attack1", "arm_r", tuple(a - b for a, b in zip(hand, dota_pivot(first["arm_r"][5]))))]
    with open(os.path.join(MDL, f"mob_{name}.vmdl"), "w") as f:
        f.write(vmdl(name, used, lo, hi, att))
    if name == "steve":
        # his hero wears an invisible copy: Dota's players can click it, his own camera sits inside it (every pixel
        # alpha-tested away). attach_feet: where his visible model (a Dire-only particle) stands, lifted with the hero.
        feet = tuple(a - b for a, b in zip(dota_pivot((0, 24, 0)), dota_pivot(first["body"][5])))
        with open(os.path.join(MDL, "steve_ghost.vmdl"), "w") as f:
            f.write(vmdl(name, used, lo, hi, att + [("attach_feet", "body", feet)], "materials/mc/ghost.vmat"))
PARTICLE = """<!-- kv3 encoding:text:version{{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d}} format:generic:version{{7412167c-06e9-4698-aff2-e63eb59037e7}} -->
{{
	_class = "CParticleSystemDefinition"
	m_bShouldHitboxesFallbackToRenderBounds = false
	m_nMaxParticles = 1
	m_flConstantRadius = 1.0
	m_flConstantLifespan = 100000.0
	m_Renderers =
	[
		{{
			_class = "C_OP_RenderModels"
			m_bOrientZ = true
			m_bSuppressTint = true
			m_ModelList = [ {{ m_model = resource:"models/mc/mob_{model}.vmdl" }} ]
			m_bAnimated = true
			m_bForceLoopingAnimation = {loop}
			m_nLOD = 1
		}},
	]
	m_Operators =
	[
		{{ _class = "C_OP_RemapCPOrientationToYaw" m_nCP = 0 m_flRotOffset = 90.0 }},
		{{ _class = "C_OP_SetToCP" m_nControlPointNumber = 0 }},
	]
	m_Initializers =
	[
		{{ _class = "C_INIT_CreateWithinSphere" m_nControlPointNumber = 0 }},
		{{ _class = "C_INIT_RandomNamedModelSequence" m_bModelFromRenderer = true m_names = [ "{anim}" ] m_nFieldOutput = 13 }},
	]
	m_Emitters = [ {{ _class = "C_OP_InstantaneousEmitter" m_nParticlesToEmit = 1 }} ]
}}
"""
PDIR = os.path.join(ROOT, "particles", "mc", "steve")
os.makedirs(PDIR, exist_ok=True)
for model in [m for m in MOB_BUILD if m.startswith("steve")] + ["pig", "chicken"]:
    for an, act, seconds, looping, _ in anims_for(model):
        with open(os.path.join(PDIR, f"{model}_{an}.vpcf"), "w") as f:
            f.write(PARTICLE.format(model=model, anim=an, loop="true" if looping else "false"))
with open(os.path.join(ROOT, "..", "scripts", "vscripts", "mc_held.lua"), "w") as f:
    f.write("-- written by tools/gen_mobs.py: items Steve is drawn holding (models/mc/mob_steve__<item>)\nMC_HELD = { "
            + ", ".join(f'{k} = true' for k in HELD) + " }\n")
Image.new("RGB", (4, 4), (0, 0, 0)).save(os.path.join(MAT, "ghost.png"))
Image.new("L", (4, 4), 0).save(os.path.join(MAT, "ghost_alpha.png"))
with open(os.path.join(MAT, "ghost.vmat"), "w") as f:
    f.write("\n".join(['Layer0', '{', '\tshader "global_lit_simple.vfx"', '\tF_ALPHA_TEST 1', '\tg_flAlphaTestReference "0.500"',
                       '\tTextureColor "materials/mc/ghost.png"', '\tTextureTranslucency "materials/mc/ghost_alpha.png"', '}', '']))
print("mobs:", ", ".join(MOB_BUILD), "anims:", ", ".join(a[0] for a in ANIMS))

# Minecraft's effect icons for Dota's buff bar (modifier_mc_potion, modifier_mc_burning: GetTexture "mc/<name>"),
# referenced by hero_select.xml so they get compiled
ICONS = os.path.join(ROOT, "panorama", "images", "spellicons", "mc")
os.makedirs(ICONS, exist_ok=True)
for name, path in (("slowness", "mob_effect/slowness.png"), ("weakness", "mob_effect/weakness.png"), ("fire", "block/fire_0.png")):
    icon = Image.open(io.BytesIO(jar.read("assets/minecraft/textures/" + path))).convert("RGBA")
    icon = icon.crop((0, 0, icon.width, icon.width))  # (fire: the first frame of its strip)
    back = Image.new("RGBA", icon.size, (40, 40, 40, 255))
    back.alpha_composite(icon)
    back.resize((128, 128), Image.NEAREST).convert("RGB").save(os.path.join(ICONS, name + ".png"))

# a Minecraft block column's Dota unit (MC:SpawnBlock): drawn by nothing (Dota draws the blocks as props), but with a
# block's hitbox, two high, so Dota's players can click it to attack (hidden with NoDraw, it couldn't be clicked)
H = GRID_UNITS = 96
cube = [(-48, -48, 0), (48, -48, 0), (48, 48, 0), (-48, 48, 0), (-48, -48, 2 * H), (48, -48, 2 * H), (48, 48, 2 * H), (-48, 48, 2 * H)]
lines = ["version 1", "nodes", '0 "root" -1', "end", "skeleton", "time 0", "0 0 0 0 0 0 0", "end", "triangles"]
for q in ((0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
    for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
        lines.append("materials/mc/ghost.vmat")
        lines += [f"0 {cube[i][0]} {cube[i][1]} {cube[i][2]} 0 0 1 0 0" for i in tri]
lines.append("end")
with open(os.path.join(MDL, "block_ghost.smd"), "w") as f:
    f.write("\n".join(lines) + "\n")
with open(os.path.join(MDL, "block_ghost.vmdl"), "w") as f:
    f.write(f"""<!-- kv3 encoding:text:version{{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d}} format:modeldoc32:version{{c5dcef98-b629-46ab-88e3-a17c005c935e}} -->
{{
	rootNode =
	{{
		_class = "RootNode"
		children =
		[
			{{ _class = "RenderMeshList" children = [ {{ _class = "RenderMeshFile" filename = "models/mc/block_ghost.smd" import_scale = 1.0 }} ] }},
			{{
				_class = "HitboxSetList"
				children =
				[
					{{
						_class = "HitboxSet"
						name = "default"
						children = [ {{ _class = "Hitbox" name = "body" parent_bone = "" surface_property = "" translation_only = false group_id = 0
							hitbox_mins = [ -48.0, -48.0, -48.0 ] hitbox_maxs = [ 48.0, 48.0, {2 * H + 48}.0 ] }}, ]
					}},
				]
			}},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}}
}}
""")


# Steve's projectiles in flight, for Dota's players (MCBridge "proj"): Minecraft's item pictures, extruded, 8 px, centred;
# the arrow turned to point along its flight (the particle's forward)
for name, turn in (("wind_charge", 0), ("ender_pearl", 0), ("arrow", 3 * math.pi / 4)):
    boxes = [("item:" + name, None, (0, -4, -4), (0, 8, 8), 0, (0, 24, 0), turn, "root")]
    smd, _ = mesh_smd(boxes, sizes, ["root"])
    with open(os.path.join(MDL, f"item_{name}.smd"), "w") as f:
        f.write(smd)
    with open(os.path.join(MDL, f"item_{name}.vmdl"), "w") as f:
        f.write(f"""<!-- kv3 encoding:text:version{{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d}} format:modeldoc32:version{{c5dcef98-b629-46ab-88e3-a17c005c935e}} -->
{{
	rootNode =
	{{
		_class = "RootNode"
		children = [ {{ _class = "RenderMeshList" children = [ {{ _class = "RenderMeshFile" filename = "models/mc/item_{name}.smd" import_scale = 1.0 }} ] }}, ]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}}
}}
""")
    with open(os.path.join(PDIR, f"proj_{name}.vpcf"), "w") as f:
        f.write(PARTICLE.format(model="item_" + name, anim="", loop="false").replace("models/mc/mob_item_", "models/mc/item_")
                .replace('{ _class = "C_INIT_RandomNamedModelSequence" m_bModelFromRenderer = true m_names = [ "" ] m_nFieldOutput = 13 },', ""))

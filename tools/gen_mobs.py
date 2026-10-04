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


def bow(pivot, turn):
    # the bow in the hand at the end of an arm held forward: an upright picture, its length along the arm's way
    x, y, z = pivot
    # (the bow is drawn diagonally in its picture: a quarter turn of that upright, its grip in the hand)
    return [("item:bow", None, (0, -8, -8), (0, 16, 16), 0, (x, y + 1, z - 10), (turn + 0.785, 0, 0), "arm_r")]


def skeleton(leg=0.0, arm=0.0, dy=0, legs_pose=None):
    # arm: the bow's draw, 0 = held, 1 = the string pulled (the left hand comes up to the bow, then back to the chin)
    left = (FWD + 0.5 - 0.5 * min(1, arm * 2), -0.6 * arm, 0)
    b = [("skeleton", (0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, dy, 0), 0, "head"),
         ("skeleton", (16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, dy, 0), 0, "body"),
         ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (-5, 2 + dy, 0), FWD, "arm_r"),
         ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (5, 2 + dy, 0), left, "arm_l")]
    b += bow((-5, 2 + dy, 0), 0)
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


def zombie(leg, arm):
    return humanoid("zombie", leg=leg, arm=arm + 0.12 * leg) + [("zombie", (32, 0), (-4, -8, -4), (8, 8, 8), 0.5, (0, 0, 0), 0, "head")]


def zombie_gold(leg, arm):
    return zombie(leg, arm) + humanoid("gold", inflate=1.0, legs=False, arm=arm + 0.12 * leg) + \
        [("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (-1.9, 12, 0), leg, "leg_r"),
         ("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (1.9, 12, 0), -leg, "leg_l")]


MOB_BUILD = {"zombie": zombie, "skeleton": lambda leg, arm: skeleton(leg, arm / 0.8), "spider_jockey": spider_jockey,
             "zombie_gold": zombie_gold}
TEXTURES = {"zombie": "zombie/zombie.png", "skeleton": "skeleton/skeleton.png", "spider": "spider/spider.png",
            "gold": "equipment/humanoid/gold.png", "item:bow": "../item/bow.png"}

# animations: (activity, seconds, looping, pose at a moment 0..1) -- like Minecraft's: a walk is a sine of the legs (arms
# swaying with them for zombies), idle arms bob slowly, an attack swings the arms down (zombies) or draws the bow
WALK = 0.75  # one stride (both legs) at a creep's pace: ~3.4 blocks a second, Minecraft's 2.4 blocks a stride
ANIMS = [
    ("idle", "ACT_DOTA_IDLE", 3.0, True, lambda k: (0, 0.06 * math.sin(2 * math.pi * k))),
    ("run", "ACT_DOTA_RUN", WALK, True, lambda k: (0.75 * math.sin(2 * math.pi * k), 0)),
    ("attack", "ACT_DOTA_ATTACK", 0.6, False, lambda k: (0, 0.9 * math.sin(math.pi * min(1, k / 0.8)))),
    ("stunned", "ACT_DOTA_DISABLED", 3.0, True, lambda k: (0, 0.06 * math.sin(2 * math.pi * k))),
]


# --- space: Minecraft model pixels (y down, face -z) -> Dota units (z up, face +X) ---
def mat_mul(a, b): return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]
def mat_t(a): return [list(r) for r in zip(*a)]
def mat_vec(a, v): return tuple(sum(a[i][k] * v[k] for k in range(3)) for i in range(3))


def mc_rot(rot):
    """rot: an x turn, or (x, y, z) turns applied like Minecraft's ModelPart (Rz * Ry * Rx), as a matrix."""
    rx, ry, rz = rot if isinstance(rot, tuple) else (rot, 0, 0)
    c, s = math.cos(rx), math.sin(rx); X = [[1, 0, 0], [0, c, -s], [0, s, c]]
    c, s = math.cos(ry), math.sin(ry); Y = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    c, s = math.cos(rz), math.sin(rz); Z = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    return mat_mul(Z, mat_mul(Y, X))


# Minecraft (x, y, z) -> Dota: x, z across, -y up; then a quarter turn so the face (Minecraft -z) looks to Dota +X
# (the OBJ version's import did that turn itself)
M = [[0, 0, -1], [1, 0, 0], [0, -1, 0]]


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
        tw, th = sizes[tex]
        bi = order.index(bone)
        quads = []
        centre = dota_point((x0 + w / 2, y0 + h / 2, z0 + d / 2), off, rot)
        if uv0 is None:  # a sprite: the whole picture on a flat quad (both sides drawn: the material renders backfaces)
            if w == 0: c = [(x0, y0, z0), (x0, y0, z0 + d), (x0, y0 + h, z0 + d), (x0, y0 + h, z0)]
            elif d == 0: c = [(x0, y0, z0), (x0 + w, y0, z0), (x0 + w, y0 + h, z0), (x0, y0 + h, z0)]
            else: c = [(x0, y0, z0), (x0 + w, y0, z0), (x0 + w, y0, z0 + d), (x0, y0, z0 + d)]
            quads.append(([dota_point(p, off, rot) for p in c], [(0, 1), (1, 1), (1, 0), (0, 0)]))
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
    frames = max(2, round(seconds * FPS)) + (1 if looping else 0)
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


def kv_vec(v): return "[ " + ", ".join(f"{x:.2f}" for x in v) + " ]"


def vmdl(name, used, lo, hi, attachments):
    remaps = " ".join(f'{{ from = "materials/mc/mob_{t}.vmat" to = "materials/mc/mob_{t}.vmat" }},' for t in used)
    anims = ""
    for an, act, seconds, looping, _ in ANIMS:
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
						framerate = {FPS}.0
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
sizes = {}
for tex, path in TEXTURES.items():
    img = png(path)
    sizes[tex] = img.size
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
    smd, (lo, hi) = mesh_smd(rest, sizes, order)
    with open(os.path.join(MDL, f"mob_{name}.smd"), "w") as f:
        f.write(smd)
    for an, act, seconds, looping, pose in ANIMS:
        with open(os.path.join(MDL, f"mob_{name}_{an}.smd"), "w") as f:
            f.write(anim_smd(build, order, rest, pose, seconds, looping))
    used = []
    for b in rest:
        t = b[0].replace("item:", "")
        if t not in used: used.append(t)
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
print("mobs:", ", ".join(MOB_BUILD), "anims:", ", ".join(a[0] for a in ANIMS))

# Radiant's creeps as Minecraft mobs (Dota models): zombie (melee), skeleton (ranged), a spider jockey (siege: a
# skeleton riding a spider), zombie in gold armour (the flag bearer). Geometry and UVs follow Minecraft's entity models and
# ModelPart.Cube (like tools/gen_villager.py), textures from the local Minecraft jar (Mojang's: local, gitignored).
# Output: content/models/mc/mob_<name>.{obj,vmdl}, content/materials/mc/mob_<tex>.{png,vmat}. Faces Dota +X, feet at 0,
# 16 model pixels = one block (GRID 96). Animation: pose frames (POSES), swapped by Lua.
import glob, io, math, os, zipfile
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "content")
MAT, MDL = os.path.join(ROOT, "materials", "mc"), os.path.join(ROOT, "models", "mc")
PX, UP = 96 / 16, 8
FWD = -math.pi / 2  # arms held forward (zombies, the skeleton's bow arm)

jar = zipfile.ZipFile(sorted(glob.glob(os.path.expanduser("~/.gradle/caches/fabric-loom/*/minecraft-client.jar")))[-1])
def png(p): return Image.open(io.BytesIO(jar.read("assets/minecraft/textures/" + (p[3:] if p.startswith("../") else "entity/" + p)))).convert("RGBA")

# box: (texture, (u, v), min, size, inflation, pivot, turn); y down, the face looks to -z, feet at y 24. A "sprite"
# (an item: the skeleton's bow) is a flat picture: ("item:<texture>", None, min, size with one 0, 0, pivot, turn).
# Poses (frames swapped by Lua, MC:AnimateMobs): legs swing by `leg`, arms by `arm` (an attack: arms swung down).
def humanoid(t, arms=FWD, inflate=0.0, legs=True, head=True, body=True, leg=0.0, arm=0.0):
    b = []
    if head: b += [(t, (0, 0), (-4, -8, -4), (8, 8, 8), inflate, (0, 0, 0), 0)]
    if body: b += [(t, (16, 16), (-4, 0, -2), (8, 12, 4), inflate, (0, 0, 0), 0)]
    if arms is not None:
        b += [(t, (40, 16), (-3, -2, -2), (4, 12, 4), inflate, (-5, 2, 0), arms + arm),
              (t, (40, 16), (-1, -2, -2), (4, 12, 4), inflate, (5, 2, 0), arms + arm)]
    if legs:
        b += [(t, (0, 16), (-2, 0, -2), (4, 12, 4), inflate, (-1.9, 12, 0), leg),
              (t, (0, 16), (-2, 0, -2), (4, 12, 4), inflate, (1.9, 12, 0), -leg)]
    return b


def bow(pivot, turn):
    # the bow in the hand at the end of an arm held forward: an upright picture, its length along the arm's way
    x, y, z = pivot
    # (the bow is drawn diagonally in its picture: a quarter turn of that upright, its grip in the hand)
    return [("item:bow", None, (0, -8, -8), (0, 16, 16), 0, (x, y + 1, z - 10), (turn + 0.785, 0, 0))]


def skeleton(leg=0.0, arm=0.0, dy=0, legs_pose=None):
    # arm: the bow's draw, 0 = held, 1 = the string pulled (the left hand comes up to the bow, then back to the chin)
    left = (FWD + 0.5 - 0.5 * min(1, arm * 2), -0.6 * arm, 0)
    b = [("skeleton", (0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, dy, 0), 0),
         ("skeleton", (16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, dy, 0), 0),
         ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (-5, 2 + dy, 0), FWD),
         ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (5, 2 + dy, 0), left)]
    b += bow((-5, 2 + dy, 0), 0)
    if legs_pose: b += legs_pose
    else:
        b += [("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (-2, 12 + dy, 0), leg),
              ("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (2, 12 + dy, 0), -leg)]
    return b


def spider_jockey(leg=0.0, arm=0.0):
    b = [("spider", (32, 4), (-4, -4, -8), (8, 8, 8), 0, (0, 15, -3), 0),
         ("spider", (0, 0), (-3, -3, -3), (6, 6, 6), 0, (0, 15, 0), 0),
         ("spider", (0, 12), (-5, -4, -6), (10, 8, 12), 0, (0, 15, 9), 0)]
    for i, (z, ry, rz) in enumerate(((2, 0.7854, 0.7854), (1, 0.3927, 0.5809), (0, -0.3927, 0.5809), (-1, -0.7854, 0.7854))):
        for side in (-1, 1):
            swing = leg * (1 if (i + (side > 0)) % 2 else -1)  # alternate legs step together
            b.append(("spider", (18, 0), (-15, -1, -1) if side < 0 else (-1, -1, -1), (16, 2, 2), 0, (4 * side, 15, z),
                      (0, (ry + swing) * -side, rz * side)))
    # the rider: sitting on the spider's back, legs forward
    b += skeleton(arm=arm / 0.8, dy=-1, legs_pose=[("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (-2, 11, 2), (-1.4, 0.3, 0)),
                                             ("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (2, 11, 2), (-1.4, -0.3, 0))])
    return b


MOB_BUILD = {
    "zombie": lambda leg, arm: humanoid("zombie", leg=leg, arm=arm + 0.12 * leg) + [("zombie", (32, 0), (-4, -8, -4), (8, 8, 8), 0.5, (0, 0, 0), 0)],
    "skeleton": lambda leg, arm: skeleton(leg, arm / 0.8),
    "spider_jockey": spider_jockey,
    "zombie_gold": lambda leg, arm: humanoid("zombie", leg=leg, arm=arm + 0.12 * leg) + humanoid("gold", inflate=1.0, legs=False, arm=arm + 0.12 * leg) +
        [("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (-1.9, 12, 0), leg), ("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (1.9, 12, 0), -leg)],
}
# frames: the model itself (standing), walk w0..w3, attack a0..a1 (MC:AnimateMobs plays them)
# walk: 8 frames of a sine; attack: 3 frames (zombies: arms swung down and back; skeletons: the bow drawn)
POSES = {"": (0, 0)}
POSES.update({f"_w{k}": (0.6 * math.sin(k * math.pi / 6), 0) for k in range(12)})
POSES.update({"_a0": (0, 0.4), "_a1": (0, 0.8), "_a2": (0, 0.3)})
MOBS = {name + suffix: build(leg, arm) for name, build in MOB_BUILD.items() for suffix, (leg, arm) in POSES.items()}
TEXTURES = {"zombie": "zombie/zombie.png", "skeleton": "skeleton/skeleton.png", "spider": "spider/spider.png",
            "gold": "equipment/humanoid/gold.png", "item:bow": "../item/bow.png"}


def dota(p, offset, rot):
    """rot: an x turn, or (x, y, z) turns applied like Minecraft's ModelPart (Rz * Ry * Rx)."""
    rx, ry, rz = rot if isinstance(rot, tuple) else (rot, 0, 0)
    x, y, z = p
    c, s = math.cos(rx), math.sin(rx)
    y, z = y * c - z * s, y * s + z * c
    c, s = math.cos(ry), math.sin(ry)
    x, z = x * c + z * s, -x * s + z * c
    c, s = math.cos(rz), math.sin(rz)
    x, y = x * c - y * s, x * s + y * c
    x, y, z = x + offset[0], y + offset[1], z + offset[2]
    return (x * PX, z * PX, (24 - y) * PX)  # (the villager's mapping turned around: faces Dota +X)


def mesh(boxes, sizes):
    verts, uvs, faces = [], [], {}
    for tex, uv0, (x0, y0, z0), (w, h, d), g, off, rot in boxes:
        tw, th = sizes[tex]
        if uv0 is None:  # a sprite: the whole picture on a flat quad (both sides drawn: the material renders backfaces)
            if w == 0: c = [(x0, y0, z0), (x0, y0, z0 + d), (x0, y0 + h, z0 + d), (x0, y0 + h, z0)]
            elif d == 0: c = [(x0, y0, z0), (x0 + w, y0, z0), (x0 + w, y0 + h, z0), (x0, y0 + h, z0)]
            else: c = [(x0, y0, z0), (x0 + w, y0, z0), (x0 + w, y0, z0 + d), (x0, y0, z0 + d)]
            face = []
            for corner, (tu, tv) in zip(c, ((0, 0), (1, 0), (1, 1), (0, 1))):
                verts.append(dota(corner, off, rot))
                uvs.append((tu, 1 - tv))
                face.append(len(verts))
            faces.setdefault(tex, []).append(face)
            continue
        u, v = uv0
        x1, y1, z1 = x0 + w + g, y0 + h + g, z0 + d + g
        x0, y0, z0 = x0 - g, y0 - g, z0 - g
        c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        u0, u1, u2, u3, u4, u5 = u, u + d, u + d + w, u + d + w + w, u + d + w + d, u + d + w + d + w
        v0, v1, v2 = v, v + d, v + d + h
        quads = [((5, 1, 2, 6), (u2, v1, u4, v2)), ((0, 4, 7, 3), (u0, v1, u1, v2)), ((5, 4, 0, 1), (u1, v0, u2, v1)),
                 ((2, 3, 7, 6), (u2, v1, u3, v0)), ((1, 0, 3, 2), (u1, v1, u2, v2)), ((4, 5, 6, 7), (u4, v1, u5, v2))]
        for idx, (ua, va, ub, vb) in quads:
            face = []
            for corner, (tu, tv) in zip(idx, ((ub, va), (ua, va), (ua, vb), (ub, vb))):
                verts.append(dota(c[corner], off, rot))
                uvs.append((tu / tw, 1 - tv / th))
                face.append(len(verts))
            faces.setdefault(tex, []).append(face[::-1])  # (turned around: the winding flips)
    obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in verts] + [f"vt {a:.5f} {b:.5f}" for a, b in uvs]
    for tex, fs in faces.items():
        obj.append(f"usemtl mob_{tex.replace('item:', '')}")
        obj += ["f " + " ".join(f"{i}/{i}" for i in f) for f in fs]
    xs, ys, zs = [v[0] for v in verts], [v[1] for v in verts], [v[2] for v in verts]
    return "\n".join(obj) + "\n", list(faces), ((min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs)))


VMDL = """<!-- kv3 encoding:text:version{{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d}} format:modeldoc32:version{{c5dcef98-b629-46ab-88e3-a17c005c935e}} -->
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
								hitbox_mins = [ {mins} ]
								hitbox_maxs = [ {maxs} ]
							}},
						]
					}},
				]
			}},
			{{
				_class = "RenderMeshList"
				children = [ {{ _class = "RenderMeshFile" filename = "models/mc/mob_{name}.obj" import_scale = 1.0 }} ]
			}},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}}
}}
"""

os.makedirs(MAT, exist_ok=True); os.makedirs(MDL, exist_ok=True)
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
for name, boxes in MOBS.items():
    obj, used, (lo, hi) = mesh(boxes, sizes)
    with open(os.path.join(MDL, f"mob_{name}.obj"), "w") as f:
        f.write(obj)
    used = [t.replace("item:", "") for t in used]
    remaps = " ".join(f'{{ from = "mob_{t}.vmat" to = "materials/mc/mob_{t}.vmat" }},' for t in used)
    with open(os.path.join(MDL, f"mob_{name}.vmdl"), "w") as f:
        f.write(VMDL.format(remaps=remaps, name=name, mins=", ".join(f"{v:.1f}" for v in lo), maxs=", ".join(f"{v:.1f}" for v in hi)))
print("mobs:", ", ".join(MOBS))

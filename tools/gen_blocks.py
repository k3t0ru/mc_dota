# Generates our own Minecraft-style block assets (16x16 pixel textures, cube mesh, vmat, vmdl) into content/.
# Then compile: tools/build_assets.ps1. Nothing here is copied from Minecraft.
import os, random
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "content")
MAT, MDL = os.path.join(ROOT, "materials", "mc"), os.path.join(ROOT, "models", "mc")
os.makedirs(MAT, exist_ok=True); os.makedirs(MDL, exist_ok=True)
S, UP, SIZE = 16, 16, 128  # texture px, nearest upscale factor (crisp pixels), block size in Dota units


def jitter(c, r, d):
    k = r.randint(-d, d)
    return tuple(max(0, min(255, v + k)) for v in c)


def stone(r):
    return [[jitter((96, 96, 98), r, 14) for _ in range(S)] for _ in range(S)]


def cobble(r):
    seeds = [(r.randrange(S), r.randrange(S), r.randint(70, 120)) for _ in range(10)]
    px = [[None] * S for _ in range(S)]
    for y in range(S):
        for x in range(S):
            d = sorted(((min(abs(x - sx), S - abs(x - sx)) ** 2 + min(abs(y - sy), S - abs(y - sy)) ** 2, g) for sx, sy, g in seeds))
            g = d[0][1] if d[1][0] - d[0][0] > 2 else 45  # dark mortar between stones
            px[y][x] = jitter((g, g, g), r, 8)
    return px


def ore(color):
    def f(r):
        px = stone(r)
        for _ in range(5):
            cx, cy = r.randrange(1, S - 2), r.randrange(1, S - 2)
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
                if r.random() < 0.85:
                    px[cy + dy][cx + dx] = jitter(color, r, 20)
        return px
    return f


def log(r):
    px = []
    for y in range(S):
        row = []
        for x in range(S):
            base = (102, 76, 46) if x % 4 else (72, 52, 30)  # vertical bark grooves
            row.append(jitter(base, r, 10))
        px.append(row)
    return px


def planks(r):
    return [[jitter((70, 50, 28) if y % 4 == 3 or (x == (y // 4 * 5) % S) else (168, 132, 82), r, 8) for x in range(S)] for y in range(S)]


def crafting_table(r):
    px = planks(r)
    for x in range(S):  # dark frame with a "grid" on top like a workbench
        px[0][x] = px[1][x] = (60, 40, 22)
    for x, y in ((3, 6), (4, 7), (5, 8), (11, 6), (11, 7), (11, 8), (10, 9), (12, 9)):  # little saw and hammer
        px[y][x] = (150, 150, 155)
    return px


BLOCKS = {
    "stone": stone, "cobblestone": cobble, "log": log, "planks": planks, "crafting_table": crafting_table,
    "coal_ore": ore((30, 30, 30)), "iron_ore": ore((216, 175, 147)), "diamond_ore": ore((95, 230, 225)),
}

# unit cube, origin at bottom centre; one quad per face with full 0..1 UVs
h = SIZE / 2
V = [(x, y, z) for x in (-h, h) for y in (-h, h) for z in (0, SIZE)]
FACES = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
obj = [f"v {x} {y} {z}" for x, y, z in V] + ["vt 0 0", "vt 1 0", "vt 1 1", "vt 0 1", "usemtl block"]
obj += ["f " + " ".join(f"{i + 1}/{t + 1}" for t, i in enumerate(face)) for face in FACES]
with open(os.path.join(MDL, "block.obj"), "w") as f:
    f.write("\n".join(obj) + "\n")

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
						remaps = [ {{ from = "block.vmat" to = "materials/mc/{name}.vmat" }} ]
						use_global_default = true
						global_default_material = "materials/mc/{name}.vmat"
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
								name = "block"
								parent_bone = ""
								surface_property = ""
								translation_only = false
								group_id = 0
								hitbox_mins = [ -64.0, -64.0, 0.0 ]
								hitbox_maxs = [ 64.0, 64.0, 128.0 ]
							}},
						]
					}},
				]
			}},
			{{
				_class = "RenderMeshList"
				children =
				[
					{{
						_class = "RenderMeshFile"
						filename = "models/mc/block.obj"
						import_scale = 1.0
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

VMAT = """Layer0
{{
	shader "global_lit_simple.vfx"
	F_SPECULAR 0
	g_vColorTint "[1.000000 1.000000 1.000000 0.000000]"
	TextureColor "materials/mc/{name}.png"
}}
"""

for name, fn in BLOCKS.items():
    r = random.Random(name)
    px = fn(r)
    img = Image.new("RGB", (S, S))
    img.putdata([c for row in px for c in row])
    img.resize((S * UP, S * UP), Image.NEAREST).save(os.path.join(MAT, f"{name}.png"))
    with open(os.path.join(MAT, f"{name}.vmat"), "w") as f:
        f.write(VMAT.format(name=name))
    with open(os.path.join(MDL, f"{name}.vmdl"), "w") as f:
        f.write(VMDL.format(name=name))
print("ok:", ", ".join(BLOCKS))

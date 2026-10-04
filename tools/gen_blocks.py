# Generates the block assets (cube mesh with top/side/bottom materials, vmat, vmdl) into content/.
# Textures: Minecraft's own, read from the local Minecraft jar on this PC (Mojang's files: they stay local, gitignored,
# never published); without the jar, our procedural 16x16 lookalikes. Then compile: tools/build_assets.sh.
import glob, io, os, random, zipfile
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


def dirt(r):
    return [[jitter((121, 85, 58) if r.random() > 0.15 else (90, 62, 40), r, 10) for _ in range(S)] for _ in range(S)]


def sand(r):
    return [[jitter((219, 207, 163), r, 12) for _ in range(S)] for _ in range(S)]


def flat(color):  # plain jittered colour (wool without the Minecraft jar)
    return lambda r: [[jitter(color, r, 10) for _ in range(S)] for _ in range(S)]


BLOCKS = {
    "dirt": dirt, "sand": sand,
    # the fountain market's stalls (MC:SpawnTraders)
    "spruce_planks": lambda r: [[jitter((114, 84, 48), r, 8) for _ in range(S)] for _ in range(S)],
    "red_wool": flat((160, 39, 34)), "white_wool": flat((233, 236, 236)), "blue_wool": flat((53, 57, 157)),
    "stone": stone, "cobblestone": cobble, "log": log, "planks": planks, "crafting_table": crafting_table,
    "coal_ore": ore((30, 30, 30)), "iron_ore": ore((216, 175, 147)), "diamond_ore": ore((95, 230, 225)),
}

# unit cube, origin at bottom centre; one quad per face with full 0..1 UVs
# Minecraft texture names per block: (top, side, bottom)
FACES_MC = {
    "stone": ("stone",) * 3, "cobblestone": ("cobblestone",) * 3, "dirt": ("dirt",) * 3, "sand": ("sand",) * 3,
    "log": ("oak_log_top", "oak_log", "oak_log_top"), "planks": ("oak_planks",) * 3,
    "crafting_table": ("crafting_table_top", "crafting_table_front", "oak_planks"),
    "coal_ore": ("coal_ore",) * 3, "iron_ore": ("iron_ore",) * 3, "diamond_ore": ("diamond_ore",) * 3,
    "spruce_planks": ("spruce_planks",) * 3, "red_wool": ("red_wool",) * 3, "white_wool": ("white_wool",) * 3,
    "blue_wool": ("blue_wool",) * 3,
}


def minecraft_jar():
    import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import mcjar
    return zipfile.ZipFile(mcjar.path())


# cube 128 units, origin at bottom centre; per face: material group and (u, v) per corner, v up the image
h = SIZE / 2
def quad(mat, pts):  # pts: 4 corners (x, y, z) counter-clockwise seen from outside; uv follows the same order
    return mat, pts
CUBE = [
    quad("top", [(-h, -h, SIZE), (h, -h, SIZE), (h, h, SIZE), (-h, h, SIZE)]),
    quad("bottom", [(-h, h, 0), (h, h, 0), (h, -h, 0), (-h, -h, 0)]),
    quad("side", [(-h, -h, 0), (h, -h, 0), (h, -h, SIZE), (-h, -h, SIZE)]),
    quad("side", [(h, -h, 0), (h, h, 0), (h, h, SIZE), (h, -h, SIZE)]),
    quad("side", [(h, h, 0), (-h, h, 0), (-h, h, SIZE), (h, h, SIZE)]),
    quad("side", [(-h, h, 0), (-h, -h, 0), (-h, -h, SIZE), (-h, h, SIZE)]),
]
UV = [(0, 0), (1, 0), (1, 1), (0, 1)]
obj, n = ["vt 0 0", "vt 1 0", "vt 1 1", "vt 0 1"], 0
for mat, pts in CUBE:
    obj.append(f"usemtl {mat}")
    obj += [f"v {x} {z} {-y}" for x, y, z in pts]  # OBJ is Y-up; ModelDoc makes it Z-up
    obj.append("f " + " ".join(f"{n + i + 1}/{i + 1}" for i in range(4)))
    n += 4
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
						remaps = [
							{{ from = "top.vmat" to = "materials/mc/{name}_top.vmat" }},
							{{ from = "side.vmat" to = "materials/mc/{name}_side.vmat" }},
							{{ from = "bottom.vmat" to = "materials/mc/{name}_bottom.vmat" }},
						]
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
	TextureColor "materials/mc/{tex}.png"
}}
"""

jar = minecraft_jar()
print("textures:", "Minecraft jar" if jar else "procedural")
for name, fn in BLOCKS.items():
    for face, mc_name in zip(("top", "side", "bottom"), FACES_MC.get(name, (None,) * 3)):
        tex = f"{name}_{face}"
        img = None
        if jar and mc_name:
            try:
                img = Image.open(io.BytesIO(jar.read(f"assets/minecraft/textures/block/{mc_name}.png"))).convert("RGB").crop((0, 0, S, S))
            except KeyError:
                pass
        if img is None:
            px = fn(random.Random(name))
            img = Image.new("RGB", (S, S))
            img.putdata([c for row in px for c in row])
        img.resize((S * UP, S * UP), Image.NEAREST).save(os.path.join(MAT, f"{tex}.png"))
        with open(os.path.join(MAT, f"{tex}.vmat"), "w") as f:
            f.write(VMAT.format(tex=tex))
    with open(os.path.join(MDL, f"{name}.vmdl"), "w") as f:
        f.write(VMDL.format(name=name))
# breaking cracks: a slightly bigger alpha-tested cube per stage, drawn over the block Dota renders
CRACK_VMAT = """Layer0
{{
	shader "global_lit_simple.vfx"
	F_SPECULAR 0
	F_ALPHA_TEST 1
	g_flAlphaTestReference "0.500"
	TextureColor "materials/mc/crack_{n}.png"
	TextureTranslucency "materials/mc/crack_{n}_alpha.png"
}}
"""
if jar:
    for n in range(10):
        img = Image.open(io.BytesIO(jar.read(f"assets/minecraft/textures/block/destroy_stage_{n}.png"))).convert("RGBA").crop((0, 0, S, S))
        big = img.resize((S * UP, S * UP), Image.NEAREST)
        big.convert("RGB").save(os.path.join(MAT, f"crack_{n}.png"))
        big.split()[3].save(os.path.join(MAT, f"crack_{n}_alpha.png"))
        for face in ("top", "side", "bottom"):
            with open(os.path.join(MAT, f"crack_{n}_{face}.vmat"), "w") as f:
                f.write(CRACK_VMAT.format(n=n))
        with open(os.path.join(MDL, f"crack_{n}.vmdl"), "w") as f:
            f.write(VMDL.format(name=f"crack_{n}"))
    print("cracks: 10 stages")
print("ok:", ", ".join(BLOCKS))

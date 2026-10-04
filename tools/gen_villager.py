# Generates blocky villager models for the traders (Dota draws them; Minecraft only keeps an invisible villager to trade
# with, because anything Minecraft draws lags behind Dota's world). Geometry and UVs follow Minecraft's VillagerModel
# and ModelPart.Cube; the texture is Minecraft's own villager + plains type + profession, read from the local Minecraft
# jar (Mojang's files: they stay local, gitignored, never published). Then compile: tools/build_assets.sh.
import glob, io, math, os, zipfile
from PIL import Image

ROOT = os.path.join(os.path.dirname(__file__), "..", "content")
MAT, MDL = os.path.join(ROOT, "materials", "mc"), os.path.join(ROOT, "models", "mc")
os.makedirs(MAT, exist_ok=True); os.makedirs(MDL, exist_ok=True)
PX = 96 / 16  # Dota units per Minecraft model pixel (one block = GRID 96)
TEX, UP = 64, 8  # villager texture size, nearest upscale (crisp pixels)
PROFESSIONS = ("fletcher", "librarian", "toolsmith", "mason", "weaponsmith", "cleric")  # cleric = our witch (witch.png)  # TRADERS in addon_game_mode.lua

# (texture u, v), box min (x, y, z) and size (w, h, d) in model pixels (y points DOWN, the face looks to -z),
# inflation, and the part pose: offset and x rotation (radians)
BOXES = [
    ((0, 0), (-4, -10, -4), (8, 10, 8), 0, (0, 0, 0), 0),  # head
    ((32, 0), (-4, -10, -4), (8, 10, 8), 0.51, (0, 0, 0), 0),  # hat layer
    ((24, 0), (-1, -1, -6), (2, 4, 2), 0, (0, -2, 0), 0),  # nose
    ((16, 20), (-4, 0, -3), (8, 12, 6), 0, (0, 0, 0), 0),  # body
    ((0, 38), (-4, 0, -3), (8, 20, 6), 0.5, (0, 0, 0), 0),  # robe
    ((44, 22), (-8, -2, -2), (4, 8, 4), 0, (0, 3, -1), -0.75),  # crossed arms: right
    ((44, 22), (4, -2, -2), (4, 8, 4), 0, (0, 3, -1), -0.75),  # left
    ((40, 38), (-4, 2, -2), (8, 4, 4), 0, (0, 3, -1), -0.75),  # middle
    ((0, 22), (-2, 0, -2), (4, 12, 4), 0, (-2, 12, 0), 0),  # right leg
    ((0, 22), (-2, 0, -2), (4, 12, 4), 0, (2, 12, 0), 0),  # left leg
]


# the witch's hat (WitchModel: brim, then three ever smaller tiers, each a little higher; their slight tilts left out),
# on a 64 x 128 texture
HAT = [
    ((0, 64), (0, 0, 0), (10, 2, 10), 0, (-5, -10.03, -5), 0),
    ((0, 76), (0, 0, 0), (7, 4, 7), 0, (-3.25, -14.03, -3), 0),
    ((0, 87), (0, 0, 0), (4, 4, 4), 0, (-1.5, -18.03, -1), 0),
    ((0, 95), (0, 0, 0), (1, 2, 1), 0.25, (0.25, -20.03, 1), 0),
]


def dota(p, offset, rot):
    """Model pixel point -> Dota units. Minecraft draws models flipped (-x, -y); its world maps to Dota as
    x -> X, z -> -Y, up -> Z. The villager then faces Dota -X (checked in game) with its feet (model y 24) at Z 0."""
    x, y, z = p
    c, s = math.cos(rot), math.sin(rot)
    y, z = y * c - z * s, y * s + z * c
    x, y, z = x + offset[0], y + offset[1], z + offset[2]
    return (-x * PX, -z * PX, (24 - y) * PX)


def mesh(boxes=BOXES, tex_h=TEX):
    verts, uvs, faces = [], [], []
    for (u, v), (x0, y0, z0), (w, h, d), g, off, rot in boxes:
        x1, y1, z1 = x0 + w + g, y0 + h + g, z0 + d + g
        x0, y0, z0 = x0 - g, y0 - g, z0 - g
        c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        u0, u1, u2, u3, u4, u5 = u, u + d, u + d + w, u + d + w + w, u + d + w + d, u + d + w + d + w
        v0, v1, v2 = v, v + d, v + d + h
        quads = [  # ModelPart.Cube: corner order and UV rectangle (ua, va, ub, vb) of each face
            ((5, 1, 2, 6), (u2, v1, u4, v2)), ((0, 4, 7, 3), (u0, v1, u1, v2)), ((5, 4, 0, 1), (u1, v0, u2, v1)),
            ((2, 3, 7, 6), (u2, v1, u3, v0)), ((1, 0, 3, 2), (u1, v1, u2, v2)), ((4, 5, 6, 7), (u4, v1, u5, v2)),
        ]
        for idx, (ua, va, ub, vb) in quads:
            face = []
            for corner, (tu, tv) in zip(idx, ((ub, va), (ua, va), (ua, vb), (ub, vb))):
                verts.append(dota(c[corner], off, rot))
                uvs.append((tu / TEX, 1 - tv / tex_h))
                face.append(len(verts))
            faces.append(face)
    obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in verts]  # OBJ is Y-up; ModelDoc makes it Z-up
    obj += [f"vt {a:.5f} {b:.5f}" for a, b in uvs]
    obj.append("usemtl villager")
    obj += ["f " + " ".join(f"{i}/{i}" for i in f) for f in faces]
    return "\n".join(obj) + "\n"


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
						remaps = [ {{ from = "villager.vmat" to = "materials/mc/villager_{prof}.vmat" }} ]
						use_global_default = false
						global_default_material = ""
					}},
				]
			}},
			{{
				_class = "RenderMeshList"
				children = [ {{ _class = "RenderMeshFile" filename = "models/mc/{obj}.obj" import_scale = 1.0 }} ]
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
	F_ALPHA_TEST 1
	F_RENDER_BACKFACES 1
	g_flAlphaTestReference "0.500"
	TextureColor "materials/mc/villager_{prof}.png"
	TextureTranslucency "materials/mc/villager_{prof}_alpha.png"
}}
"""

import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import mcjar
jar = zipfile.ZipFile(mcjar.path())
tex = lambda p: Image.open(io.BytesIO(jar.read(f"assets/minecraft/textures/entity/villager/{p}.png"))).convert("RGBA")
with open(os.path.join(MDL, "villager.obj"), "w") as f:
    f.write(mesh())
with open(os.path.join(MDL, "witch.obj"), "w") as f:
    f.write(mesh(BOXES + HAT, 128))
for prof in PROFESSIONS:
    if prof == "cleric":  # the witch trader: Minecraft's witch skin (a villager's layout, plus its hat)
        img = Image.open(io.BytesIO(jar.read("assets/minecraft/textures/entity/witch.png"))).convert("RGBA")
    else:
        img = tex("villager")
        for layer in ("type/plains", f"profession/{prof}"):
            img = Image.alpha_composite(img, tex(layer))
    big = img.resize((img.width * UP, img.height * UP), Image.NEAREST)
    big.convert("RGB").save(os.path.join(MAT, f"villager_{prof}.png"))
    big.split()[3].save(os.path.join(MAT, f"villager_{prof}_alpha.png"))
    with open(os.path.join(MAT, f"villager_{prof}.vmat"), "w") as f:
        f.write(VMAT.format(prof=prof))
    with open(os.path.join(MDL, f"villager_{prof}.vmdl"), "w") as f:
        f.write(VMDL.format(prof=prof, obj="witch" if prof == "cleric" else "villager"))
print("villagers:", ", ".join(PROFESSIONS))

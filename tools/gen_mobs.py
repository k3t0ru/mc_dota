# Radiant's creeps as Minecraft mobs (Dota models): zombie (melee), skeleton (ranged), creeper (siege: it blows up
# buildings), zombie in gold armour (the flag bearer). Geometry and UVs follow Minecraft's entity models and
# ModelPart.Cube (like tools/gen_villager.py), textures from the local Minecraft jar (Mojang's: local, gitignored).
# Output: content/models/mc/mob_<name>.{obj,vmdl}, content/materials/mc/mob_<tex>.{png,vmat}. Faces Dota +X, feet at 0,
# 16 model pixels = one block (GRID 96). Static (no animation).
import glob, io, math, os, zipfile
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "content")
MAT, MDL = os.path.join(ROOT, "materials", "mc"), os.path.join(ROOT, "models", "mc")
PX, UP = 96 / 16, 8
FWD = -math.pi / 2  # arms held forward (zombies, the skeleton's bow arm)

jar = zipfile.ZipFile(sorted(glob.glob(os.path.expanduser("~/.gradle/caches/fabric-loom/*/minecraft-client.jar")))[-1])
def png(p): return Image.open(io.BytesIO(jar.read("assets/minecraft/textures/entity/" + p))).convert("RGBA")

# box: (texture, (u, v), min, size, inflation, pivot, x rotation); y down, the face looks to -z, feet at y 24
def humanoid(t, arms=FWD, inflate=0.0, legs=True, head=True, body=True):
    b = []
    if head: b += [(t, (0, 0), (-4, -8, -4), (8, 8, 8), inflate, (0, 0, 0), 0)]
    if body: b += [(t, (16, 16), (-4, 0, -2), (8, 12, 4), inflate, (0, 0, 0), 0)]
    if arms is not None:
        b += [(t, (40, 16), (-3, -2, -2), (4, 12, 4), inflate, (-5, 2, 0), arms),
              (t, (40, 16), (-1, -2, -2), (4, 12, 4), inflate, (5, 2, 0), arms)]
    if legs:
        b += [(t, (0, 16), (-2, 0, -2), (4, 12, 4), inflate, (-1.9, 12, 0), 0),
              (t, (0, 16), (-2, 0, -2), (4, 12, 4), inflate, (1.9, 12, 0), 0)]
    return b

MOBS = {
    "zombie": humanoid("zombie") + [("zombie", (32, 0), (-4, -8, -4), (8, 8, 8), 0.5, (0, 0, 0), 0)],
    "skeleton": [("skeleton", (0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, 0, 0), 0),
                 ("skeleton", (16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, 0, 0), 0),
                 ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (-5, 2, 0), FWD),
                 ("skeleton", (40, 16), (-1, -2, -1), (2, 12, 2), 0, (5, 2, 0), -0.3),
                 ("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (-2, 12, 0), 0),
                 ("skeleton", (0, 16), (-1, 0, -1), (2, 12, 2), 0, (2, 12, 0), 0)],
    "creeper": [("creeper", (0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, 6, 0), 0),
                ("creeper", (16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, 6, 0), 0)]
               + [("creeper", (0, 16), (-2, 0, -2), (4, 6, 4), 0, (x, 18, z), 0) for x, z in ((-2, 4), (2, 4), (-2, -4), (2, -4))],
    "zombie_gold": humanoid("zombie") + humanoid("gold", inflate=1.0, legs=False) +
                   [("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (-1.9, 12, 0), 0), ("gold", (0, 16), (-2, 0, -2), (4, 12, 4), 0.6, (1.9, 12, 0), 0)],
}
TEXTURES = {"zombie": "zombie/zombie.png", "skeleton": "skeleton/skeleton.png", "creeper": "creeper/creeper.png",
            "gold": "equipment/humanoid/gold.png"}


def dota(p, offset, rot):
    x, y, z = p
    c, s = math.cos(rot), math.sin(rot)
    y, z = y * c - z * s, y * s + z * c
    x, y, z = x + offset[0], y + offset[1], z + offset[2]
    return (x * PX, z * PX, (24 - y) * PX)  # (the villager's mapping turned around: faces Dota +X)


def mesh(boxes, sizes):
    verts, uvs, faces = [], [], {}
    for tex, (u, v), (x0, y0, z0), (w, h, d), g, off, rot in boxes:
        tw, th = sizes[tex]
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
        obj.append(f"usemtl mob_{tex}")
        obj += ["f " + " ".join(f"{i}/{i}" for i in f) for f in fs]
    return "\n".join(obj) + "\n", list(faces)


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
    big = img.resize((img.width * UP, img.height * UP), Image.NEAREST)
    big.convert("RGB").save(os.path.join(MAT, f"mob_{tex}.png"))
    big.split()[3].save(os.path.join(MAT, f"mob_{tex}_alpha.png"))
    with open(os.path.join(MAT, f"mob_{tex}.vmat"), "w") as f:
        f.write(f'Layer0\n{{\n\tshader "global_lit_simple.vfx"\n\tF_SPECULAR 0\n\tF_ALPHA_TEST 1\n\tF_RENDER_BACKFACES 1\n'
                f'\tg_flAlphaTestReference "0.500"\n\tTextureColor "materials/mc/mob_{tex}.png"\n'
                f'\tTextureTranslucency "materials/mc/mob_{tex}_alpha.png"\n}}\n')
for name, boxes in MOBS.items():
    obj, used = mesh(boxes, sizes)
    with open(os.path.join(MDL, f"mob_{name}.obj"), "w") as f:
        f.write(obj)
    remaps = " ".join(f'{{ from = "mob_{t}.vmat" to = "materials/mc/mob_{t}.vmat" }},' for t in used)
    with open(os.path.join(MDL, f"mob_{name}.vmdl"), "w") as f:
        f.write(VMDL.format(remaps=remaps, name=name))
print("mobs:", ", ".join(MOBS))

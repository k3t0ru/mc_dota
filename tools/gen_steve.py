# Steve as a Dota model, for the other team's players (Dota's players see Steve; his own player sees Minecraft's).
# Geometry and UVs follow Minecraft's PlayerModel (wide arms) and ModelPart.Cube, like tools/gen_villager.py; the
# texture is Minecraft's own steve.png from the local Minecraft jar (Mojang's file: local, gitignored, never published).
# Output: content/models/mc/steve.{obj,vmdl}, content/materials/mc/steve.{png,vmat}. Faces Dota -X at yaw 0, feet at 0.
import glob, io, os, zipfile
from PIL import Image


ROOT = os.path.join(os.path.dirname(__file__), "..", "content")
MAT, MDL = os.path.join(ROOT, "materials", "mc"), os.path.join(ROOT, "models", "mc")
PX = 96 / 16 * 1.0  # Dota units per model pixel (Steve: 32 px tall = 2 blocks)
UP = 8
import math

# (u, v), box min, size, inflation, pivot, x rotation: Minecraft's PlayerModel (y down, the face looks to -z)
BOXES = [
    ((0, 0), (-4, -8, -4), (8, 8, 8), 0, (0, 0, 0), 0),  # head
    ((32, 0), (-4, -8, -4), (8, 8, 8), 0.5, (0, 0, 0), 0),  # hat layer
    ((16, 16), (-4, 0, -2), (8, 12, 4), 0, (0, 0, 0), 0),  # body
    ((16, 32), (-4, 0, -2), (8, 12, 4), 0.25, (0, 0, 0), 0),  # jacket
    ((40, 16), (-3, -2, -2), (4, 12, 4), 0, (-5, 2, 0), 0),  # right arm
    ((40, 32), (-3, -2, -2), (4, 12, 4), 0.25, (-5, 2, 0), 0),  # right sleeve
    ((32, 48), (-1, -2, -2), (4, 12, 4), 0, (5, 2, 0), 0),  # left arm
    ((48, 48), (-1, -2, -2), (4, 12, 4), 0.25, (5, 2, 0), 0),  # left sleeve
    ((0, 16), (-2, 0, -2), (4, 12, 4), 0, (-1.9, 12, 0), 0),  # right leg
    ((0, 32), (-2, 0, -2), (4, 12, 4), 0.25, (-1.9, 12, 0), 0),  # right pants
    ((16, 48), (-2, 0, -2), (4, 12, 4), 0, (1.9, 12, 0), 0),  # left leg
    ((0, 48), (-2, 0, -2), (4, 12, 4), 0.25, (1.9, 12, 0), 0),  # left pants
]
TEX = 64


def dota(p, offset, rot):
    x, y, z = p
    c, s = math.cos(rot), math.sin(rot)
    y, z = y * c - z * s, y * s + z * c
    x, y, z = x + offset[0], y + offset[1], z + offset[2]
    return (-x * PX, -z * PX, (24 - y) * PX)


def mesh():
    verts, uvs, faces = [], [], []
    for (u, v), (x0, y0, z0), (w, h, d), g, off, rot in BOXES:
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
                uvs.append((tu / TEX, 1 - tv / TEX))
                face.append(len(verts))
            faces.append(face)
    obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in verts] + [f"vt {a:.5f} {b:.5f}" for a, b in uvs]
    obj.append("usemtl steve")
    obj += ["f " + " ".join(f"{i}/{i}" for i in f) for f in faces]
    return "\n".join(obj) + "\n"


jar = zipfile.ZipFile(sorted(glob.glob(os.path.expanduser("~/.gradle/caches/fabric-loom/*/minecraft-client.jar")))[-1])
img = Image.open(io.BytesIO(jar.read("assets/minecraft/textures/entity/player/wide/steve.png"))).convert("RGBA")
big = img.resize((TEX * UP, TEX * UP), Image.NEAREST)
os.makedirs(MAT, exist_ok=True); os.makedirs(MDL, exist_ok=True)
big.convert("RGB").save(os.path.join(MAT, "steve.png"))
big.split()[3].save(os.path.join(MAT, "steve_alpha.png"))
with open(os.path.join(MAT, "steve.vmat"), "w") as f:
    f.write('Layer0\n{\n\tshader "global_lit_simple.vfx"\n\tF_SPECULAR 0\n\tF_ALPHA_TEST 1\n\tF_RENDER_BACKFACES 1\n'
            '\tg_flAlphaTestReference "0.500"\n\tTextureColor "materials/mc/steve.png"\n'
            '\tTextureTranslucency "materials/mc/steve_alpha.png"\n}\n')
with open(os.path.join(MDL, "steve.obj"), "w") as f:
    f.write(mesh())
with open(os.path.join(MDL, "steve.vmdl"), "w") as f:
    f.write("""<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc32:version{c5dcef98-b629-46ab-88e3-a17c005c935e} -->
{
	rootNode =
	{
		_class = "RootNode"
		children =
		[
			{
				_class = "MaterialGroupList"
				children =
				[
					{
						_class = "DefaultMaterialGroup"
						remaps = [ { from = "steve.vmat" to = "materials/mc/steve.vmat" } ]
						use_global_default = false
						global_default_material = ""
					},
				]
			},
			{
				_class = "RenderMeshList"
				children = [ { _class = "RenderMeshFile" filename = "models/mc/steve.obj" import_scale = 1.0 } ]
			},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}
}
""")
print("steve ok")

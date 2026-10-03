# A dark sky dome for Dota: Dota's map edge was never meant to be seen from the ground (a striped dark backdrop stood
# over the horizon). A smooth unlit sphere around the map hides it: dark navy, a little lighter toward the horizon.
# Output: content/models/mc/sky.{obj,vmdl}, content/materials/mc/sky.{png,vmat}. Lua (MC:Sky) scales it: 1 unit =
# SKY_R / 100. Then compile with resourcecompiler.
import math, os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(HERE, "..", "content")
TOP, HORIZON = (12, 17, 30), (30, 42, 64)

# the colour by height: v = 0 at the top of the dome, 1 at (and below) the horizon
H = 256
img = Image.new("RGB", (4, H))
for y in range(H):
    k = (y / (H - 1)) ** 2
    c = tuple(round(TOP[i] + (HORIZON[i] - TOP[i]) * k) for i in range(3))
    for x in range(4):
        img.putpixel((x, y), c)
os.makedirs(os.path.join(CONTENT, "materials", "mc"), exist_ok=True)
img.save(os.path.join(CONTENT, "materials", "mc", "sky.png"))
with open(os.path.join(CONTENT, "materials", "mc", "sky.vmat"), "w") as f:
    f.write('Layer0\n{\n\tshader "global_lit_simple.vfx"\n\tF_UNLIT 1\n\tF_DO_NOT_CAST_SHADOWS 1\n\tF_RENDER_BACKFACES 1\n'
            '\tF_SPECULAR 0\n\tTextureColor "materials/mc/sky.png"\n}\n')

# a UV sphere (radius 100) from the top down to 30 degrees below the horizon, faces seen from inside
R, RINGS, SEGS = 100, 24, 48
v, vt, faces = [], [], []
for i in range(RINGS + 1):
    el = math.radians(90 - i * 120 / RINGS)  # elevation: 90 at the top .. -30
    for j in range(SEGS + 1):
        az = 2 * math.pi * j / SEGS
        v.append((R * math.cos(el) * math.cos(az), R * math.cos(el) * math.sin(az), R * math.sin(el)))
        vt.append((j / SEGS, 1 - min(1.0, (90 - math.degrees(el)) / 90)))
for i in range(RINGS):
    for j in range(SEGS):
        a = i * (SEGS + 1) + j + 1
        b, c, d = a + 1, a + SEGS + 2, a + SEGS + 1
        faces.append((a, d, c, b))  # inward
obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in v] + [f"vt {a:.4f} {b:.4f}" for a, b in vt] + ["usemtl sky"]
obj += ["f " + " ".join(f"{k}/{k}" for k in q) for q in faces]
os.makedirs(os.path.join(CONTENT, "models", "mc"), exist_ok=True)
with open(os.path.join(CONTENT, "models", "mc", "sky.obj"), "w") as f:
    f.write("\n".join(obj) + "\n")
with open(os.path.join(CONTENT, "models", "mc", "sky.vmdl"), "w") as f:
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
						remaps = [ { from = "sky.vmat" to = "materials/mc/sky.vmat" } ]
						use_global_default = false
						global_default_material = ""
					},
				]
			},
			{
				_class = "RenderMeshList"
				children = [ { _class = "RenderMeshFile" filename = "models/mc/sky.obj" import_scale = 1.0 } ]
			},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}
}
""")
print("sky dome ok")

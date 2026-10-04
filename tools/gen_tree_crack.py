# Breaking cracks for Dota's trees: chopping a tree in Minecraft (its magenta log column) shows Minecraft's
# destroy_stage cracks wrapped around the Dota tree's trunk: an 8-sided tube, 2 blocks tall, in Dota units (scale 1),
# feet at 0. Uses the block cracks' materials (materials/mc/crack_<n>_side.vmat, tools/gen_blocks.py).
# Output: content/models/mc/tree_crack.obj, tree_crack_<n>.vmdl. Then compile with resourcecompiler.
import math, os

MDL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "content", "models", "mc")
R, HEIGHT, SIDES = 18, 192, 8  # trunk radius, 2 blocks of 96
TILE = 96  # one crack texture per block of height and per 96 units around

v, vt, f = [], [], []
around = 2 * math.pi * R
for i in range(SIDES):
    a0, a1 = 2 * math.pi * i / SIDES, 2 * math.pi * (i + 1) / SIDES
    u0, u1 = around * i / SIDES / TILE, around * (i + 1) / SIDES / TILE
    pts = [(R * math.cos(a0), R * math.sin(a0), 0), (R * math.cos(a1), R * math.sin(a1), 0),
           (R * math.cos(a1), R * math.sin(a1), HEIGHT), (R * math.cos(a0), R * math.sin(a0), HEIGHT)]
    uvs = [(u0, 0), (u1, 0), (u1, HEIGHT / TILE), (u0, HEIGHT / TILE)]
    base = len(v)
    v += pts
    vt += uvs
    f.append([base + 1, base + 2, base + 3, base + 4])  # outward (counter-clockwise seen from outside)
obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in v] + [f"vt {a:.4f} {b:.4f}" for a, b in vt] + ["usemtl side"]
obj += ["f " + " ".join(f"{k}/{k}" for k in q) for q in f]
with open(os.path.join(MDL, "tree_crack.obj"), "w") as fh:
    fh.write("\n".join(obj) + "\n")

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
						remaps = [ {{ from = "side.vmat" to = "materials/mc/crack_{n}_side.vmat" }} ]
						use_global_default = false
						global_default_material = ""
					}},
				]
			}},
			{{
				_class = "RenderMeshList"
				children = [ {{ _class = "RenderMeshFile" filename = "models/mc/tree_crack.obj" import_scale = 1.0 }} ]
			}},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}}
}}
"""
for n in range(10):
    with open(os.path.join(MDL, f"tree_crack_{n}.vmdl"), "w") as fh:
        fh.write(VMDL.format(n=n))
print("tree cracks: 10 stages")

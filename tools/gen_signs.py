# The traders' signs as Dota models (Minecraft's signs, drawn by Minecraft, lagged behind Dota's picture: they drifted).
# Each sign is its own model with its text baked into the board's front texture, in Minecraft's font, from the local
# Minecraft jar (Mojang's files: they stay local, gitignored, never published).
# Models: content/models/mc/sign_<id>.vmdl, centred on their block like tools/gen_mcblocks.py's (Lua: MC:Sign).
#   wall  = against the block to the north, text facing south (Minecraft's wall sign facing=south)
#   stand = on a post in the middle of the block, text facing south (rotation=0)
# Then compile: resourcecompiler on the vmdl files.
import glob, io, os, zipfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(HERE, "..", "content")
MDL, MAT = os.path.join(CONTENT, "models", "mc"), os.path.join(CONTENT, "materials", "mc")
UNIT = 8  # Dota units per Minecraft pixel (a block is 128; Lua scales it to GRID)
W, H = 1024, 512  # a board's front texture (power-of-two sizes only in Dota; the board is 24 x 12 Minecraft pixels)
FONT_PX = 10  # texture pixels per font pixel: 4 lines of 10 fill the board

SIGNS = {  # id -> kind, 4 lines (keep in step with SIGNS in addon_game_mode.lua)
	"fletcher_name": ("wall", ["", "Fletcher", "", ""]),
	"fletcher_goods": ("wall", ["Materials", "Food", "TNT, clock", ""]),
	"mason_name": ("wall", ["", "Mason", "", ""]),
	"mason_goods": ("wall", ["Building", "blocks", "", ""]),
	"librarian_name": ("wall", ["", "Librarian", "", ""]),
	"librarian_goods": ("wall", ["Enchanting", "books, tables", "", ""]),
	"toolsmith_name": ("wall", ["", "Toolsmith", "", ""]),
	"toolsmith_goods": ("wall", ["Smithing", "Repair: sneak", "+ right click", ""]),
	"secret_1": ("stand", ["", "Secret", "shop", ""]),
	"secret_2": ("stand", ["Diamonds", "Netherite", "Elytra", ""]),
}

jar = zipfile.ZipFile(sorted(glob.glob(os.path.expanduser("~/.gradle/caches/fabric-loom/*/minecraft-client.jar")))[-1])
def png(path): return Image.open(io.BytesIO(jar.read(path))).convert("RGBA")
sign_tex = png("assets/minecraft/textures/entity/signs/spruce.png")
font = png("assets/minecraft/textures/font/ascii.png")
cell = font.width // 16

def glyph(ch):
	c = ord(ch)
	if c > 255: c = ord("?")
	g = font.crop(((c % 16) * cell, (c // 16) * cell, (c % 16 + 1) * cell, (c // 16 + 1) * cell))
	cols = [x for x in range(cell) if any(g.getpixel((x, y))[3] > 0 for y in range(cell))]
	width = (max(cols) + 1) if cols else 3  # a space: 3 + 1 advance, as in Minecraft
	return g, width

def text_width(s): return sum(glyph(ch)[1] + 1 for ch in s) - 1 if s else 0

os.makedirs(MDL, exist_ok=True); os.makedirs(MAT, exist_ok=True)
# the plain wood (sides, back, post) and each sign's front with its text
wood = sign_tex.crop((2, 2, 26, 14)).resize((256, 128), Image.NEAREST)
wood.convert("RGB").save(os.path.join(MAT, "sign_wood.png"))
def vmat(name):
	with open(os.path.join(MAT, name + ".vmat"), "w") as f:
		f.write(f'Layer0\n{{\n\tshader "global_lit_simple.vfx"\n\tF_SPECULAR 0\n\tTextureColor "materials/mc/{name}.png"\n}}\n')
vmat("sign_wood")

def front(sid, lines):
	board = sign_tex.crop((2, 2, 26, 14)).resize((W, H), Image.NEAREST)
	top = (H - 4 * 10 * FONT_PX) // 2 + FONT_PX
	for i, line in enumerate(lines):
		x = (board.width - text_width(line) * FONT_PX) // 2
		y = top + i * 10 * FONT_PX
		for ch in line:
			g, w = glyph(ch)
			mask = g.split()[3].resize((cell * FONT_PX, cell * FONT_PX), Image.NEAREST)
			board.paste((0, 0, 0, 255), (x, y), mask)
			x += (w + 1) * FONT_PX
	name = "sign_" + sid
	board.convert("RGB").save(os.path.join(MAT, name + ".png"))
	vmat(name)
	return name

def box(v, uv, faces, mats, a, b, front_mat, wood_mat):
	"""A box from a to b (Minecraft px, x y z): the south face (+z) gets front_mat, the rest wood."""
	(x1, y1, z1), (x2, y2, z2) = a, b
	quads = {
		"south": ([(x1, y2, z2), (x2, y2, z2), (x2, y1, z2), (x1, y1, z2)], front_mat),
		"north": ([(x2, y2, z1), (x1, y2, z1), (x1, y1, z1), (x2, y1, z1)], wood_mat),
		"east": ([(x2, y2, z2), (x2, y2, z1), (x2, y1, z1), (x2, y1, z2)], wood_mat),
		"west": ([(x1, y2, z1), (x1, y2, z2), (x1, y1, z2), (x1, y1, z1)], wood_mat),
		"up": ([(x1, y2, z1), (x2, y2, z1), (x2, y2, z2), (x1, y2, z2)], wood_mat),
		"down": ([(x1, y1, z2), (x2, y1, z2), (x2, y1, z1), (x1, y1, z1)], wood_mat),
	}
	for corners, mat in quads.values():
		idx = []
		for p, (u, w) in zip(corners, [(0, 0), (1, 0), (1, 1), (0, 1)]):
			v.append(((p[0] - 8) * UNIT, -(p[2] - 8) * UNIT, (p[1] - 8) * UNIT))
			uv.append((u, 1 - w))
			idx.append(len(v))
		faces.setdefault(mat, []).append(idx[::-1])
		mats.add(mat)

VMDL = """<!-- kv3 encoding:text:version{e21c7f3c-8a33-41c5-9977-a76d3a32aa0d} format:modeldoc32:version{c5dcef98-b629-46ab-88e3-a17c005c935e} -->
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
						remaps =
						[
@REMAPS@						]
						use_global_default = false
						global_default_material = ""
					},
				]
			},
			{
				_class = "RenderMeshList"
				children = [ { _class = "RenderMeshFile" filename = "@OBJ@" import_scale = 1.0 } ]
			},
		]
		model_archetype = ""
		primary_associated_entity = ""
		anim_graph_name = ""
	}
}
"""

T = 4 / 3  # board thickness (Minecraft draws signs 2/3 size: 2 px -> 1.33)
for sid, (kind, lines) in SIGNS.items():
	fm = front(sid, lines)
	v, uv, faces, mats = [], [], {}, set()
	if kind == "wall":
		box(v, uv, faces, mats, (0, 4.33, 0), (16, 12.33, T), fm, "sign_wood")
	else:
		box(v, uv, faces, mats, (0, 9.33, 8 - T / 2), (16, 17.33, 8 + T / 2), fm, "sign_wood")
		box(v, uv, faces, mats, (8 - T / 2, 0, 8 - T / 2), (8 + T / 2, 9.33, 8 + T / 2), "sign_wood", "sign_wood")
	obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in v] + [f"vt {u:.4f} {w:.4f}" for u, w in uv]
	for mat, quads in faces.items():
		obj.append(f"usemtl {mat}")
		obj += ["f " + " ".join(f"{i}/{i}" for i in q) for q in quads]
	name = "sign_" + sid
	with open(os.path.join(MDL, name + ".obj"), "w") as f:
		f.write("\n".join(obj) + "\n")
	remaps = "".join(f'\t\t\t\t\t\t\t{{ from = "{m}.vmat" to = "materials/mc/{m}.vmat" }},\n' for m in sorted(mats))
	with open(os.path.join(MDL, name + ".vmdl"), "w") as f:
		f.write(VMDL.replace("@REMAPS@", remaps).replace("@OBJ@", f"models/mc/{name}.obj"))
print(f"{len(SIGNS)} signs")

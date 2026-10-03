# Every Minecraft block as a Dota model, built from Minecraft's own block models in the local Minecraft jar (Mojang's
# files: they stay local, gitignored, never published). Then compile: tools/build_assets.sh.
#
# - One Dota model per Minecraft block model (models/mcb/<name>.vmdl), centred on the block's middle so Dota can turn
#   it for a blockstate variant (x/y rotations: the prop's roll/yaw, see MC:ShowBlock).
# - Geometry: the model's "elements" (boxes) with their own rotations (fire and plants are crossed planes), per-face UVs
#   and texture rotations, Minecraft's default UVs where none are given. Models without elements (chests, beds, signs,
#   water: block entities and fluids) become a plain cube with their particle texture.
# - Materials per texture (materials/mcb/<texture>.vmat), alpha-tested when the texture has see-through pixels, both
#   sides drawn; tinted faces (grass, leaves) get Minecraft's default plains colours baked in. Animated textures: frame 1;
#   fire (FRAMES of its animation strip) gets a model per frame, <model>__f<k>, that Lua cycles (MCB_ANIM).
# - scripts/vscripts/mc_block_models.lua: blockstate variants (which model, x, y for which properties) for Lua.
import glob, io, json, os, re, zipfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CONTENT = os.path.join(HERE, "..", "content")
MDL, MAT = os.path.join(CONTENT, "models", "mcb"), os.path.join(CONTENT, "materials", "mcb")
LUA = os.path.join(HERE, "..", "scripts", "vscripts", "mc_block_models.lua")
os.makedirs(MDL, exist_ok=True); os.makedirs(MAT, exist_ok=True)
UNIT = 8  # Dota units per model pixel in model space (a block is 128; MC:ShowBlock scales the prop to GRID)
UP = 8  # nearest upscale of the 16 px textures (crisp pixels)
TINT = {0: (145, 189, 89), 1: (145, 189, 89), 2: (119, 171, 47)}  # grass / plains foliage; leaves use #77AB2F
SKIP = {"air", "cave_air", "void_air", "structure_void", "light", "barrier", "moving_piston", "piston_head"}

jar = zipfile.ZipFile(sorted(glob.glob(os.path.expanduser("~/.gradle/caches/fabric-loom/*/minecraft-client.jar")))[-1])
names = set(jar.namelist())


def strip(ref):
    return ref.split(":")[-1]


_models = {}
def model(name):
    """The model with its parents resolved: textures merged (child wins), elements from the nearest model with any."""
    name = strip(name)
    if name in _models:
        return _models[name]
    path = f"assets/minecraft/models/{name}.json"
    j = json.loads(jar.read(path)) if path in names else {}
    textures, elements = {}, None
    if "parent" in j and not strip(j["parent"]).startswith("builtin/"):
        parent = model(j["parent"])
        textures.update(parent["textures"])
        elements = parent["elements"]
    textures.update(j.get("textures", {}))
    if "elements" in j:
        elements = j["elements"]
    _models[name] = {"textures": textures, "elements": elements}
    return _models[name]


def resolve(textures, ref, depth=0):
    while ref and ref.startswith("#") and depth < 10:
        ref = textures.get(ref[1:]); depth += 1
    return strip(ref) if ref and not ref.startswith("#") else None


FRAMES = 8  # frames of an animated fire texture made into models (of its 32: every 4th)
ANIMATED = re.compile(r"^block/(soul_)?fire_\d|campfire_fire$")  # textures whose animation Dota plays: fire, soul fire, campfire flames


_tex = {}
def texture(name, tint, frame=0):
    """Writes the texture (and its alpha) once; returns (material name, has see-through pixels)."""
    key = (name, tint, frame)
    if key in _tex:
        return _tex[key]
    path = f"assets/minecraft/textures/{name}.png"
    if path not in names:
        _tex[key] = None
        return None
    img = Image.open(io.BytesIO(jar.read(path))).convert("RGBA")
    if img.height > img.width:  # animated strip: one frame
        n = img.height // img.width
        k = frame * n // FRAMES % n
        img = img.crop((0, k * img.width, img.width, (k + 1) * img.width))
    if tint is not None:
        r, g, b = TINT.get(tint, TINT[0]) if "leaves" not in name else TINT[2]
        px = [(p[0] * r // 255, p[1] * g // 255, p[2] * b // 255, p[3]) for p in img.getdata()]
        img.putdata(px)
    alpha = img.getextrema()[3][0] < 255
    mat = re.sub(r"[^a-z0-9_]", "_", name.replace("block/", "")) + ("_tint" if tint is not None else "") + (f"_f{frame}" if frame else "")
    big = img.resize((img.width * UP, img.height * UP), Image.NEAREST)
    big.convert("RGB").save(os.path.join(MAT, mat + ".png"))
    if alpha:
        big.split()[3].save(os.path.join(MAT, mat + "_alpha.png"))
    with open(os.path.join(MAT, mat + ".vmat"), "w") as f:
        f.write("Layer0\n{\n\tshader \"global_lit_simple.vfx\"\n\tF_SPECULAR 0\n")
        if alpha:
            f.write("\tF_ALPHA_TEST 1\n\tF_RENDER_BACKFACES 1\n\tg_flAlphaTestReference \"0.500\"\n"
                    f"\tTextureTranslucency \"materials/mcb/{mat}_alpha.png\"\n")
        f.write(f"\tTextureColor \"materials/mcb/{mat}.png\"\n}}\n")
    _tex[key] = (mat, alpha)
    return _tex[key]


import math
def rotate(p, rot):
    if not rot or not rot.get("angle"):
        return p
    a = math.radians(rot["angle"]); o = rot.get("origin", [8, 8, 8]); ax = rot["axis"]
    x, y, z = p[0] - o[0], p[1] - o[1], p[2] - o[2]
    c, s = math.cos(a), math.sin(a)
    if ax == "x": y, z = y * c - z * s, y * s + z * c
    elif ax == "y": x, z = x * c + z * s, -x * s + z * c
    else: x, y = x * c - y * s, x * s + y * c
    return (x + o[0], y + o[1], z + o[2])


# per face: the 4 corners (top-left, top-right, bottom-right, bottom-left as seen on the texture) and the default UV
def face_corners(d, a, b):
    (x1, y1, z1), (x2, y2, z2) = a, b
    return {
        "north": ([(x2, y2, z1), (x1, y2, z1), (x1, y1, z1), (x2, y1, z1)], (16 - x2, 16 - y2, 16 - x1, 16 - y1)),
        "south": ([(x1, y2, z2), (x2, y2, z2), (x2, y1, z2), (x1, y1, z2)], (x1, 16 - y2, x2, 16 - y1)),
        "west": ([(x1, y2, z1), (x1, y2, z2), (x1, y1, z2), (x1, y1, z1)], (z1, 16 - y2, z2, 16 - y1)),
        "east": ([(x2, y2, z2), (x2, y2, z1), (x2, y1, z1), (x2, y1, z2)], (16 - z2, 16 - y2, 16 - z1, 16 - y1)),
        "up": ([(x1, y2, z1), (x2, y2, z1), (x2, y2, z2), (x1, y2, z2)], (x1, z1, x2, z2)),
        "down": ([(x1, y1, z2), (x2, y1, z2), (x2, y1, z1), (x1, y1, z1)], (x1, 16 - z2, x2, 16 - z1)),
    }[d]

NORMAL = {"north": (0, 0, -1), "south": (0, 0, 1), "west": (-1, 0, 0), "east": (1, 0, 0), "up": (0, 1, 0), "down": (0, -1, 0)}
CUBE = [{"from": [0, 0, 0], "to": [16, 16, 16], "faces": {d: {"texture": "#particle"} for d in NORMAL}}]


animated = {}  # model -> True when it shows an ANIMATED texture


def build(name, frame=0):
    m = model(name)
    elements = m["elements"] or CUBE
    verts, uvs, faces = [], [], {}  # faces: material -> list of index quads
    for el in elements:
        a, b = el["from"], el["to"]
        for d, f in el.get("faces", {}).items():
            tex = resolve(m["textures"], f.get("texture"))
            moving = bool(tex and ANIMATED.search(tex))
            if moving and not frame:
                animated[strip(name)] = True
            t = tex and texture(tex, f.get("tintindex"), frame if moving else 0)
            if not t:
                continue
            corners, duv = face_corners(d, a, b)
            u1, v1, u2, v2 = f.get("uv", duv)
            uv = [(u1, v1), (u2, v1), (u2, v2), (u1, v2)]
            r = (f.get("rotation", 0) // 90) % 4
            uv = uv[r:] + uv[:r]  # a rotated texture: the corners take the next corner's UV
            pts = [rotate(p, el.get("rotation")) for p in corners]
            idx = []
            for p, (u, v) in zip(pts, uv):
                verts.append(((p[0] - 8) * UNIT, -(p[2] - 8) * UNIT, (p[1] - 8) * UNIT))  # Dota x, y, z (y = -MC z)
                uvs.append((u / 16, 1 - v / 16))
                idx.append(len(verts))
            # outward winding: counter-clockwise seen from the face's normal side (Minecraft's corners go clockwise)
            faces.setdefault(t[0], []).append(idx[::-1])
    if not faces:
        return None
    obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in verts] + [f"vt {u:.5f} {v:.5f}" for u, v in uvs]
    for mat, quads in faces.items():
        obj.append(f"usemtl {mat}")
        obj += ["f " + " ".join(f"{i}/{i}" for i in q) for q in quads]
    fname = re.sub(r"[^a-z0-9_]", "_", strip(name).replace("block/", "")) + (f"__f{frame}" if frame else "")
    with open(os.path.join(MDL, fname + ".obj"), "w") as f:
        f.write("\n".join(obj) + "\n")
    remaps = "".join(f'\t\t\t\t\t\t\t{{ from = "{mat}.vmat" to = "materials/mcb/{mat}.vmat" }},\n' for mat in faces)
    with open(os.path.join(MDL, fname + ".vmdl"), "w") as f:
        f.write(VMDL.replace("@REMAPS@", remaps).replace("@OBJ@", f"models/mcb/{fname}.obj"))
    return fname


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

built, table, anim = {}, {}, {}
for path in sorted(n for n in names if n.startswith("assets/minecraft/blockstates/")):
    block = path.rsplit("/", 1)[-1][:-5]
    if block in SKIP:
        continue
    j = json.loads(jar.read(path))
    variants = []
    if "variants" in j:
        for key, v in j["variants"].items():
            v = v[0] if isinstance(v, list) else v
            variants.append((key, v["model"], v.get("x", 0), v.get("y", 0)))
    else:  # multipart: the part that is always there (a fence's post), else the first part
        parts = [p for p in j["multipart"] if "when" not in p] or j["multipart"][:1]
        a = parts[0]["apply"]; a = a[0] if isinstance(a, list) else a
        variants.append(("", a["model"], a.get("x", 0), a.get("y", 0)))
    DEFAULTS = ("axis=y", "type=bottom", "half=bottom", "half=lower", "face=floor", "facing=south", "facing=north", "facing=up")
    def default_rank(key):  # variants of the default state first: a block placed without a state (stalls) uses vs[1]
        return -sum(1 for kv in key.split(",") if kv in DEFAULTS)
    variants.sort(key=lambda v: default_rank(v[0]))
    out = []
    for key, mname, x, y in variants:
        if mname not in built:
            built[mname] = build(mname)
            if built[mname] and strip(mname) in animated:  # the other frames
                for k in range(1, FRAMES):
                    build(mname, k)
                anim[built[mname]] = FRAMES
        if built[mname]:
            out.append((key, built[mname], x, y))
    if out:
        table[block] = out

with open(LUA, "w") as f:
    f.write("-- Generated by tools/gen_mcblocks.py from the local Minecraft jar: blockstate variant -> Dota model + rotation.\n")
    f.write("-- MCB[block] = { { \"prop=value,...\" (all must match the block's state), model, x, y }, ... }\n")
    f.write("MCB = {\n")
    for block, vs in sorted(table.items()):
        f.write(f'\t["{block}"] = {{ ' + ", ".join(f'{{ "{k}", "{m}", {x}, {y} }}' for k, m, x, y in vs) + " },\n")
    f.write("}\n_G.MCB = MCB\n")
    f.write("-- animated models: frames <model>__f1.. (frame 0 is <model> itself)\nMCB_ANIM = { " +
            ", ".join(f'["{m}"] = {n}' for m, n in sorted(anim.items())) + " }\n_G.MCB_ANIM = MCB_ANIM\n")
print(f"{len(anim)} animated: {sorted(anim)}")
print(f"{len(table)} blocks, {sum(1 for v in built.values() if v)} models, {len(_tex)} textures")

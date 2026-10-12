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
UP = 16  # nearest upscale of the 16 px textures (crisp pixels: at 8 Dota's filtering blurred them up close)
TINT = {0: (145, 189, 89), 1: (145, 189, 89), 2: (119, 171, 47)}  # grass / plains foliage; leaves use #77AB2F
SKIP = {"air", "cave_air", "void_air", "structure_void", "light", "barrier", "moving_piston", "piston_head"}

import sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import mcjar
jar = zipfile.ZipFile(mcjar.path())
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
    mesh = f"models/mcb/{fname}.obj"
    if "torch" in fname:
        # a torch is a ward unit's model (MC:ShowBlock), clicked to attack it: Dota picks only models with a skeleton,
        # so torches are SMDs (one bone) with a hitbox. (The same vertices: Dota's import turns an SMD like an OBJ.)
        smd = ["version 1", "nodes", '0 "root" -1', "end", "skeleton", "time 0", "0 0 0 0 0 0 0", "end", "triangles"]
        for mat, quads in faces.items():
            for q in quads:
                a0, b0, c0 = (verts[q[k] - 1] for k in range(3))
                n = ((b0[1] - a0[1]) * (c0[2] - a0[2]) - (b0[2] - a0[2]) * (c0[1] - a0[1]),
                     (b0[2] - a0[2]) * (c0[0] - a0[0]) - (b0[0] - a0[0]) * (c0[2] - a0[2]),
                     (b0[0] - a0[0]) * (c0[1] - a0[1]) - (b0[1] - a0[1]) * (c0[0] - a0[0]))
                ln = math.sqrt(sum(x * x for x in n)) or 1
                for tri in ((q[0], q[1], q[2]), (q[0], q[2], q[3])):
                    smd.append(f"{mat}.vmat")
                    for i in tri:
                        x, y, z = verts[i - 1]
                        smd.append(f"0 {x:.4f} {y:.4f} {z:.4f} {n[0] / ln:.4f} {n[1] / ln:.4f} {n[2] / ln:.4f} {uvs[i - 1][0]:.5f} {uvs[i - 1][1]:.5f}")
        smd.append("end")
        with open(os.path.join(MDL, fname + ".smd"), "w") as f:
            f.write(chr(10).join(smd) + chr(10))
        mesh = f"models/mcb/{fname}.smd"
    with open(os.path.join(MDL, fname + ".vmdl"), "w") as f:
        f.write(VMDL.replace("@REMAPS@", remaps).replace("@OBJ@", mesh).replace("@HITBOX@", HITBOX if "torch" in fname else ""))
    return fname


# a torch is a ward unit's model (MC:ShowBlock): clickable (128 units a block, centred on the block)
HITBOX = """
			{
				_class = "HitboxSetList"
				children =
				[
					{
						_class = "HitboxSet"
						name = "default"
						children =
						[
							{
								_class = "Hitbox"
								name = "body"
								parent_bone = ""
								surface_property = ""
								translation_only = false
								group_id = 0
								hitbox_mins = [ -48.0, -48.0, -64.0 ]
								hitbox_maxs = [ 48.0, 48.0, 48.0 ]
							},
						]
					},
				]
			},"""
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
			},@HITBOX@
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


# --- block entities Minecraft draws in code (no model elements): chests and beds, rebuilt here from their renderers'
# boxes (ChestModel, BedRenderer) with their entity textures (64x64, Minecraft's box UV layout)
def mc_box(x0, y0, z0, w, h, d, u, v):
    """A ModelPart cube: (direction, 4 corners, 4 UVs in texture pixels), Minecraft's own corner/UV order."""
    x1, y1, z1 = x0 + w, y0 + h, z0 + d
    c = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    f7, f8, f9, f10 = u, u + d, u + d + w, u + d + w + w
    f11, f12, f13, f14, f15 = u + d + w + d, u + d + w + d + w, v, v + d, v + d + h
    polys = [("down", (5, 4, 0, 1), (f8, f13, f9, f14)), ("up", (2, 3, 7, 6), (f9, f14, f10, f13)),
             ("west", (4, 0, 3, 7), (f7, f14, f8, f15)), ("north", (0, 1, 2, 3), (f8, f14, f9, f15)),
             ("east", (1, 5, 6, 2), (f9, f14, f11, f15)), ("south", (5, 4, 7, 6), (f11, f14, f12, f15))]
    out = []
    for dname, idx, (u1, v1, u2, v2) in polys:
        out.append((dname, [c[i] for i in idx], [(u2, v1), (u1, v1), (u1, v2), (u2, v2)]))
    return out


NL, TABS = chr(10), chr(9) * 7


def entity_model(fname, tex, boxes, size=64):
    """boxes: (box args, transform model point -> block point 0..16). Writes the model like build() does."""
    mat = texture(tex, None)[0]
    verts, uvs, quads = [], [], []
    for args, tf in boxes:
        x0, y0, z0, w, h, d = args[:6]
        mid = tf((x0 + w / 2, y0 + h / 2, z0 + d / 2))
        for _, corners, uv in mc_box(*args):
            pts = [tf(q) for q in corners]
            if w == 0 or h == 0 or d == 0:
                continue
            a, b, c3 = pts[0], pts[1], pts[2]
            n = ((b[1] - a[1]) * (c3[2] - a[2]) - (b[2] - a[2]) * (c3[1] - a[1]),
                 (b[2] - a[2]) * (c3[0] - a[0]) - (b[0] - a[0]) * (c3[2] - a[2]),
                 (b[0] - a[0]) * (c3[1] - a[1]) - (b[1] - a[1]) * (c3[0] - a[0]))
            fc = [sum(q[k] for q in pts) / 4 - mid[k] for k in range(3)]
            order = range(4) if sum(n[k] * fc[k] for k in range(3)) > 0 else range(3, -1, -1)  # outward, counter-clockwise
            idx = []
            for i in order:
                q = pts[i]
                verts.append(((q[0] - 8) * UNIT, -(q[2] - 8) * UNIT, (q[1] - 8) * UNIT))
                uvs.append((uv[i][0] / size, 1 - uv[i][1] / size))
                idx.append(len(verts))
            quads.append(idx)
    obj = [f"v {x:.3f} {z:.3f} {-y:.3f}" for x, y, z in verts] + [f"vt {u:.5f} {v:.5f}" for u, v in uvs]
    obj.append(f"usemtl {mat}")
    obj += ["f " + " ".join(f"{i}/{i}" for i in q) for q in quads]
    with open(os.path.join(MDL, fname + ".obj"), "w") as f:
        f.write(NL.join(obj) + NL)
    remaps = TABS + f'{{ from = "{mat}.vmat" to = "materials/mcb/{mat}.vmat" }},' + NL
    with open(os.path.join(MDL, fname + ".vmdl"), "w") as f:
        f.write(VMDL.replace("@REMAPS@", remaps).replace("@OBJ@", f"models/mcb/{fname}.obj").replace("@HITBOX@", ""))
    return fname


FACING_Y = {"north": 0, "east": 90, "south": 180, "west": 270}  # (models built facing north, like a furnace's)
turn = lambda q: (16 - q[0], q[1], 16 - q[2])  # ChestModel faces south: turned to face north
CHESTS = {"chest": "normal", "trapped_chest": "trapped", "ender_chest": "ender"}
for ox in ("", "exposed_", "weathered_", "oxidized_"):
    for wx in ("", "waxed_"):
        CHESTS[f"{wx}{ox}copper_chest"] = "copper" + (f"_{ox[:-1]}" if ox else "")
for block, t in CHESTS.items():
    if f"assets/minecraft/textures/entity/chest/{t}.png" not in names or block not in table:
        continue
    kinds = {"single": (t, [(1, 0, 1, 14, 10, 14, 0, 19), (1, 9, 1, 14, 5, 14, 0, 0), (7, 7, 15, 2, 4, 1, 0, 0)])}
    if f"assets/minecraft/textures/entity/chest/{t}_left.png" in names:
        kinds["left"] = (t + "_left", [(0, 0, 1, 15, 10, 14, 0, 19), (0, 9, 1, 15, 5, 14, 0, 0), (0, 7, 15, 1, 4, 1, 0, 0)])
        kinds["right"] = (t + "_right", [(1, 0, 1, 15, 10, 14, 0, 19), (1, 9, 1, 15, 5, 14, 0, 0), (15, 7, 15, 1, 4, 1, 0, 0)])
    out = []
    for kind, (tx, boxes) in kinds.items():
        m = entity_model(f"chest_{tx}", f"entity/chest/{tx}", [(b, turn) for b in boxes])
        for fc, y in FACING_Y.items():
            out.append((f"facing={fc},type={kind}" if kind != "single" or len(kinds) > 1 else f"facing={fc}", m, 0, y))
    out.sort(key=lambda e: 0 if "single" in e[0] or "type" not in e[0] else 1)
    table[block] = out
lay = lambda q: (q[0], 9 - q[2], q[1])  # BedRenderer lays the 16x16x6 slab flat, its top at 9 px; the head's end north
for color in ("white", "orange", "magenta", "light_blue", "yellow", "lime", "pink", "gray", "light_gray", "cyan",
              "purple", "blue", "brown", "green", "red", "black"):
    block = f"{color}_bed"
    if block not in table:
        continue
    out = []
    for part, v, legs in (("head", 0, (0, 6)), ("foot", 22, (12, 18))):
        lz = 0 if part == "head" else 13
        boxes = [((0, 0, 0, 16, 16, 6, 0, v), lay)] + [((lx, 0, lz, 3, 3, 3, 50, legs[i]), lambda q: q) for i, lx in enumerate((0, 13))]
        m = entity_model(f"bed_{color}_{part}", f"entity/bed/{color}", boxes)
        for fc, y in FACING_Y.items():
            out.append((f"facing={fc},part={part}", m, 0, y))
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

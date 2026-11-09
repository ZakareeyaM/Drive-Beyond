#!/usr/bin/env python3
"""Extracts whole buildings from the two building packs into small game-ready GLBs (metres, origin = centre of the
footprint on the ground, textures downscaled to <=512 px, JPEG for opaque colour maps).

  assets/buildings/pack/<id>.glb  +  tools/buildings_report.json (footprint / height for the world placement)

Usage: python3 tools/extract_buildings.py [id ...]
"""
import io, json, os, struct, sys
import numpy as np
import trimesh
from PIL import Image
from trimesh.visual import TextureVisuals
from trimesh.visual.material import PBRMaterial

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets/buildings/pack")
CITY = os.path.join(ROOT, "assets/buildings/lowpoly_city_street_pack_buildings_stylized.glb")
SOVIET = os.path.join(ROOT, "assets/buildings/soviet_panelki__voxel_style_apartment_buildings.glb")
MAXTEX = 512

# id -> (pack, [node name prefixes that form the building], yaw_deg so that the main facade faces +Z)
CITY_B = {
    "city_block_a":   ("city", ["Cube_batiment1.010"], 0),
    "city_block_b":   ("city", ["Cube.046_batiment1.007"], 0),
    "city_block_c":   ("city", ["Cube.027_batiment6.002"], 0),
    "city_mid_a":     ("city", ["Cube.003_Material.004"], 0),
    "city_mid_b":     ("city", ["Cube.002_Material.004"], 0),
    "city_mid_c":     ("city", ["Cube.047_batiment1.004"], 0),
    "city_low_a":     ("city", ["Cube.045_batiment1.008"], 0),
    "city_tower_a":   ("city", ["Cube.099_B 3"], 0),
    "city_tower_b":   ("city", ["Cube.043_B 5", "Cube.043_B 2"], 0),
    "city_tower_c":   ("city", ["Cube.100_B 1", "Cube.100_Material.040", "Cube.100_Material.041"], 0),
    "city_tower_d":   ("city", ["Cube.096_B 2"], 0),
    "soviet_panelka": ("soviet", ["Apartment"], 0),
}


def load_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    return json.loads(d[20:20 + jl]), d[20 + jl + 8:]


class Pack:
    CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
    NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}

    def __init__(self, path):
        self.J, self.BIN = load_glb(path)
        self.N = self.J["nodes"]
        self.parent = {c: i for i, n in enumerate(self.N) for c in n.get("children", [])}

    def acc(self, i):
        a = self.J["accessors"][i]
        bv = self.J["bufferViews"][a["bufferView"]]
        dt = np.dtype(self.CT[a["componentType"]])
        n = self.NC[a["type"]]
        off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", dt.itemsize * n)
        if stride == dt.itemsize * n:
            return np.frombuffer(self.BIN, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()
        arr = np.zeros((a["count"], n), dtype=dt)
        for k in range(a["count"]):
            arr[k] = np.frombuffer(self.BIN, dtype=dt, count=n, offset=off + k * stride)
        return arr

    @staticmethod
    def mat(n):
        if "matrix" in n:
            return np.array(n["matrix"], float).reshape(4, 4).T
        t = n.get("translation", [0, 0, 0]); x, y, z, w = n.get("rotation", [0, 0, 0, 1]); s = n.get("scale", [1, 1, 1])
        R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
        M = np.eye(4); M[:3, :3] = R * np.array(s); M[:3, 3] = t
        return M

    def world(self, i):
        M = self.mat(self.N[i])
        while i in self.parent:
            i = self.parent[i]
            M = self.mat(self.N[i]) @ M
        return M

    def image(self, tex_index):
        src = self.J["textures"][tex_index]["source"]
        im = self.J["images"][src]
        bv = self.J["bufferViews"][im["bufferView"]]
        return Image.open(io.BytesIO(self.BIN[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]))

    def material(self, mi, cache):
        if mi in cache:
            return cache[mi]
        m = self.J["materials"][mi]
        pbr = m.get("pbrMetallicRoughness", {})
        col = [int(round(max(0.0, min(1.0, float(c))) * 255)) for c in pbr.get("baseColorFactor", [1, 1, 1, 1])]   # trimesh wants 0..255
        img = None
        if "baseColorTexture" in pbr:
            im = self.image(pbr["baseColorTexture"]["index"])
            has_a = im.mode in ("RGBA", "LA", "P") and m.get("alphaMode", "OPAQUE") != "OPAQUE"
            im = im.convert("RGBA" if has_a else "RGB")
            if max(im.size) > MAXTEX:
                k = MAXTEX / max(im.size)
                im = im.resize((max(8, int(im.size[0] * k)), max(8, int(im.size[1] * k))), Image.LANCZOS)
            img = im
        pm = PBRMaterial(name=m.get("name", "m%d" % mi), baseColorFactor=col, baseColorTexture=img, metallicFactor=0.0, roughnessFactor=0.85,
                         alphaMode=m.get("alphaMode", "OPAQUE"), doubleSided=bool(m.get("doubleSided", False)))
        cache[mi] = pm
        return pm

    def collect(self, prefixes):
        """world-space geometry (units of the file) of every mesh node whose name equals/starts with a prefix"""
        out = []
        for i, n in enumerate(self.N):
            if "mesh" not in n:
                continue
            nm = n.get("name", "")
            if not any(nm == p or nm.startswith(p + "_") or nm.startswith(p + ".") and False for p in prefixes):
                continue
            M = self.world(i)
            for pr in self.J["meshes"][n["mesh"]]["primitives"]:
                P = self.acc(pr["attributes"]["POSITION"]).astype(np.float64)
                P = (M[:3, :3] @ P.T).T + M[:3, 3]
                Nn = self.acc(pr["attributes"]["NORMAL"]).astype(np.float64) if "NORMAL" in pr["attributes"] else None
                if Nn is not None:
                    Nn = (np.linalg.inv(M[:3, :3]).T @ Nn.T).T
                    Nn /= np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)
                uv = self.acc(pr["attributes"]["TEXCOORD_0"]).astype(np.float64) if "TEXCOORD_0" in pr["attributes"] else np.zeros((len(P), 2))
                F = self.acc(pr["indices"]).reshape(-1, 3).astype(np.int64)
                if np.linalg.det(M[:3, :3]) < 0:
                    F = F[:, ::-1]
                out.append((nm, P, Nn, uv, F, pr.get("material", 0)))
        return out


def build(pack, bid, prefixes, yaw, report):
    parts = pack.collect(prefixes)
    if not parts:
        print("!! %s: no nodes match %s" % (bid, prefixes))
        return
    allp = np.concatenate([p[1] for p in parts])
    # world units -> metres: the packs are exported in centimetres (value range check)
    ext = allp.max(0) - allp.min(0)
    k = 0.01 if ext.max() > 200 else 1.0
    lo, hi = allp.min(0) * k, allp.max(0) * k
    ctr = np.array([(lo[0] + hi[0]) / 2, lo[1], (lo[2] + hi[2]) / 2])
    a = np.radians(yaw)
    R = np.array([[np.cos(a), 0, np.sin(a)], [0, 1, 0], [-np.sin(a), 0, np.cos(a)]])
    scene = trimesh.Scene()
    cache = {}
    for gi, (nm, P, Nn, uv, F, mi) in enumerate(parts):
        P2 = (R @ ((P * k - ctr).T)).T
        N2 = (R @ Nn.T).T if Nn is not None else None
        uvf = uv.copy(); uvf[:, 1] = 1.0 - uvf[:, 1]
        m = trimesh.Trimesh(vertices=P2, faces=F, vertex_normals=N2, process=False)
        m.visual = TextureVisuals(uv=uvf, material=pack.material(mi, cache))
        scene.add_geometry(m, node_name="P%02d" % gi, geom_name="P%02d" % gi)
    os.makedirs(OUT, exist_ok=True)
    scene.export(os.path.join(OUT, bid + ".glb"))
    b = scene.bounds
    sz = b[1] - b[0]
    report[bid] = {"w": round(float(sz[0]), 2), "h": round(float(sz[1]), 2), "d": round(float(sz[2]), 2),
                   "tris": int(sum(len(g.faces) for g in scene.geometry.values())), "kb": round(os.path.getsize(os.path.join(OUT, bid + ".glb")) / 1024)}
    print(bid, report[bid])


if __name__ == "__main__":
    only = sys.argv[1:]
    packs = {"city": Pack(CITY), "soviet": Pack(SOVIET)}
    report = {}
    for bid, (p, pref, yaw) in CITY_B.items():
        if only and bid not in only:
            continue
        build(packs[p], bid, pref, yaw, report)
    if not only:
        json.dump(report, open(os.path.join(ROOT, "tools/buildings_report.json"), "w"), indent=1)

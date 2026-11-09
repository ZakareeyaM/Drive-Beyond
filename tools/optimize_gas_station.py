#!/usr/bin/env python3
"""Offline optimiser for assets/locations/gas_station_5.glb (340k triangles -> ~20k, no ground plate).

 * drops the 174 m ground plate (Rectangle001) and the far-away parking-bay helper group (Rectangle129)
 * bakes node transforms, re-centres the model on the canopy centre (ground level, canopy centre = origin)
 * decimates the dense meshes with quadric edge collapse (fast_simplification) to a per-mesh budget
 * merges everything into one mesh per unique material colour (about 14 draw calls)
 * writes assets/locations/gas_station_opt.glb; the original GLB is untouched.
Usage: python3 tools/optimize_gas_station.py
"""
import io, json, math, os, struct, sys
import numpy as np
import trimesh
import fast_simplification as fs
from trimesh.visual import ColorVisuals
from trimesh.visual.material import PBRMaterial

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/locations/gas_station_5.glb")
OUT = os.path.join(ROOT, "assets/locations/gas_station_opt.glb")
CENTRE = np.array([68.2, 0.0, -27.2])      # canopy centre (model space, metres)
DROP_NAMES = ("Rectangle001", "Rectangle129")
BUDGET = {"default": 900, "small": 10 ** 9}   # triangles per source mesh (meshes below 1200 tris are kept as is)

d = open(SRC, "rb").read()
jl = struct.unpack("<I", d[12:16])[0]
J = json.loads(d[20:20 + jl])
BIN = d[20 + jl + 8:]
CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
N = J["nodes"]
PARENT = {c: i for i, n in enumerate(N) for c in n.get("children", [])}


def acc(i):
    a = J["accessors"][i]
    bv = J["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    n = NC[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    return np.frombuffer(BIN, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n).copy()


def mat(n):
    if "matrix" in n:
        return np.array(n["matrix"], float).reshape(4, 4).T
    t = n.get("translation", [0, 0, 0]); x, y, z, w = n.get("rotation", [0, 0, 0, 1]); s = n.get("scale", [1, 1, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)], [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)], [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4); M[:3, :3] = R * np.array(s); M[:3, 3] = t
    return M


def world(i):
    M = mat(N[i])
    while i in PARENT:
        i = PARENT[i]
        M = mat(N[i]) @ M
    return M


def chain_names(i):
    out = []
    while True:
        out.append(N[i].get("name", ""))
        if i not in PARENT:
            break
        i = PARENT[i]
    return out


def mat_key(mi):
    m = J["materials"][mi]
    pbr = m.get("pbrMetallicRoughness", {})
    col = [round(float(c), 3) for c in pbr.get("baseColorFactor", [0, 0, 0, 1])[:3]]
    em = [round(float(c), 3) for c in m.get("emissiveFactor", [0, 0, 0])]
    es = m.get("extensions", {}).get("KHR_materials_emissive_strength", {}).get("emissiveStrength", 1.0)
    return (tuple(col), tuple(em), round(float(es), 2), round(float(pbr.get("metallicFactor", 0)), 2), round(float(pbr.get("roughnessFactor", 0.9)), 1))


TARGET_TOTAL = 22000          # triangles for the whole station after decimation
KEEP_HALF = 12.5              # keep only what lies under the canopy (+-12.5 m around its centre)
MIN_DIAG = 0.5                # metres; smaller loose parts are dropped
MIN_KEEP = 12                 # a component this small is never touched


def components(P, F):
    tm = trimesh.Trimesh(vertices=P, faces=F, process=False)
    um = trimesh.Trimesh(vertices=P, faces=F, process=True)           # merged copy -> adjacency across duplicated verts
    um.merge_vertices(digits_vertex=4)
    cc = trimesh.graph.connected_components(um.face_adjacency, nodes=np.arange(len(um.faces)), min_len=1)
    return [np.array(c) for c in cc], um


def simplify_component(P, F, keep_ratio):
    n = len(F)
    diag = float(np.linalg.norm(P.max(axis=0) - P.min(axis=0)))
    big = diag >= 1.5                       # columns, beams, roof panels: keep their silhouette
    tgt = max(80 if big else MIN_KEEP, int(keep_ratio * n ** 0.6))
    if n <= tgt or n < 48:
        return P, F
    try:
        P2, F2 = fs.simplify(P.astype(np.float32), F.astype(np.int32), target_reduction=1.0 - tgt / n, agg=3 if big else 6)
        if len(F2) < 4:
            return P, F
        return P2.astype(np.float64), F2.astype(np.int64)
    except Exception:
        return P, F


# gather components of all kept meshes
items = []   # (key, P, F)
for i, n in enumerate(N):
    if "mesh" not in n:
        continue
    if any(any(dn in nm for dn in DROP_NAMES) for nm in chain_names(i)):
        continue
    M = world(i)
    pr = J["meshes"][n["mesh"]]["primitives"][0]
    P = acc(pr["attributes"]["POSITION"]).astype(np.float64)
    P = (M[:3, :3] @ P.T).T + M[:3, 3] - CENTRE
    F = acc(pr["indices"]).reshape(-1, 3).astype(np.int64)
    if np.linalg.det(M[:3, :3]) < 0:
        F = F[:, ::-1]
    cc, um = components(P, F)
    if os.environ.get('DBG'):
        sz = sorted([len(c) for c in cc], reverse=True)
        print(i, n['name'][:26].ljust(26), 'tris', len(F), 'comps', len(cc), 'top', sz[:4], 'tiny<40:', sum(1 for x in sz if x < 40), sum(x for x in sz if x < 40))
    for c in cc:
        key = mat_key(pr["material"])
        fc = um.faces[c]
        pts = um.vertices[np.unique(fc.reshape(-1))]
        diag = float(np.linalg.norm(pts.max(axis=0) - pts.min(axis=0)))
        cen = pts.mean(axis=0)
        if abs(cen[0]) > KEEP_HALF or abs(cen[2]) > KEEP_HALF:   # shop, kerbs, bays: rebuilt in game
            continue
        if diag < MIN_DIAG and not any(key[1]):      # invisible-at-game-distance details (screws, buttons, nozzles' fine parts)
            continue
        items.append((key, um.vertices, fc))
tot_in = sum(len(f) for _, _, f in items)


def run(ratio):
    out = []
    for key, P, F in items:
        used, inv = np.unique(F.reshape(-1), return_inverse=True)
        P2, F2 = simplify_component(P[used], inv.reshape(-1, 3), ratio)
        out.append((key, P2, F2))
    return out


lo, hi = 0.05, 40.0
best = None
for _ in range(9):
    mid = math.sqrt(lo * hi)
    res = run(mid)
    tot = sum(len(f) for _, _, f in res)
    best = res
    if tot > TARGET_TOTAL:
        hi = mid
    else:
        lo = mid
tot_out = sum(len(f) for _, _, f in best)
groups = {}
for key, P, F in best:
    groups.setdefault(key, []).append((P, F))

scene = trimesh.Scene()
for gi, (key, parts) in enumerate(groups.items()):
    meshes = [trimesh.Trimesh(vertices=p, faces=f, process=False) for p, f in parts]
    m = trimesh.util.concatenate(meshes)
    m.merge_vertices()
    m.update_faces(m.nondegenerate_faces())
    col, em, es, met, rough = key
    emissive = [min(1.0, c * es) for c in em] if any(em) else None
    pm = PBRMaterial(name="m%d" % gi, baseColorFactor=[col[0], col[1], col[2], 1.0] if any(col) or not emissive else [0.9, 0.9, 0.8, 1.0],
                     metallicFactor=met, roughnessFactor=rough, emissiveFactor=emissive, doubleSided=True)
    m.visual = trimesh.visual.TextureVisuals(material=pm)
    scene.add_geometry(m, node_name="Mat%02d%s" % (gi, "_emissive" if emissive else ""), geom_name="Mat%02d" % gi)
scene.export(OUT)
print("in %d tris -> out %d tris, %d materials, %.1f KB" % (tot_in, sum(len(g.faces) for g in scene.geometry.values()), len(groups), os.path.getsize(OUT) / 1024))
b = scene.bounds
print("bounds min", np.round(b[0], 1), "max", np.round(b[1], 1))

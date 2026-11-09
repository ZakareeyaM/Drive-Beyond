#!/usr/bin/env python3
"""Offline asset preparation for Drive Beyond (run once; output is committed to the project).

Splits assets/vehicles/traffic_pack/traffic_rider_npc_vehicles.glb (22 vehicles, one big scene,
1024px textures, wheel pairs fused into one mesh per axle) into one small, game-ready GLB per vehicle:

  assets/vehicles/pack/<id>.glb
    Body      one mesh, one material (512px diffuse)
    Wheel_0   front  -X   (node origin = wheel centre, mesh centred on it)
    Wheel_1   front  +X
    Wheel_2   rear   -X
    Wheel_3   rear   +X

Every output model is in metres, faces -Z (Godot forward), has its origin on the ground at the
centre between the axles and is scaled so its length matches the real vehicle (the pack is
~1.45x too large for its real dimensions).  The original pack GLB is left untouched.

Usage:  python3 tools/split_traffic_pack.py            (needs numpy, pillow, trimesh)
Writes: assets/vehicles/pack/*.glb and tools/pack_report.json (measured dimensions).
"""
import io
import json
import math
import os
import struct
import sys

import numpy as np
import trimesh
from PIL import Image
from trimesh.visual import TextureVisuals
from trimesh.visual.material import PBRMaterial

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets/vehicles/traffic_pack/traffic_rider_npc_vehicles.glb")
OUT = os.path.join(ROOT, "assets/vehicles/pack")

# game id -> (node name in pack, real length in metres)
VEHICLES = {
    "mazda_2": ("AI_Mazda2_High", 3.95),
    "renault_clio": ("AI_Clio_High", 4.06),
    "vw_golf7": ("AI_Golf7_High", 4.26),
    "kia_ceed": ("AI_Kia_Ceed_High", 4.29),
    "mazda_3": ("AI_Mazda3_High", 4.58),
    "chevy_cruze": ("AI_Cruze_High", 4.60),
    "skoda_octavia": ("AI_Skoda_Octavia_High", 4.66),
    "bmw_4": ("AI_Bmw4_High", 4.64),
    "freelander": ("AI_Freelander_High", 4.50),
    "vw_amarok": ("AI_Vw_Amorak_High", 5.25),
    "ford_f150": ("AI_Ford_F150_High", 5.90),
    "chevy_silverado": ("AI_Chevy_High", 5.85),
    "ford_excursion": ("AI_Ford_Excursion_High", 5.76),
}


def load_glb(path):
    d = open(path, "rb").read()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    binb = d[20 + jl + 8:]
    return j, binb


J, BIN = load_glb(SRC)
CT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor(i):
    a = J["accessors"][i]
    bv = J["bufferViews"][a["bufferView"]]
    dt = np.dtype(CT[a["componentType"]])
    n = NC[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", dt.itemsize * n)
    if stride == dt.itemsize * n:
        arr = np.frombuffer(BIN, dtype=dt, count=a["count"] * n, offset=off).reshape(a["count"], n)
    else:
        arr = np.zeros((a["count"], n), dtype=dt)
        for k in range(a["count"]):
            arr[k] = np.frombuffer(BIN, dtype=dt, count=n, offset=off + k * stride)
    return arr.copy()


def node_matrix(n):
    if "matrix" in n:
        return np.array(n["matrix"], dtype=np.float64).reshape(4, 4).T
    t = n.get("translation", [0, 0, 0])
    x, y, z, w = n.get("rotation", [0, 0, 0, 1])
    s = n.get("scale", [1, 1, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    M = np.eye(4)
    M[:3, :3] = R * np.array(s)
    M[:3, 3] = t
    return M


NODES = J["nodes"]
PARENT = {}
for i, n in enumerate(NODES):
    for c in n.get("children", []):
        PARENT[c] = i


def world(i):
    M = node_matrix(NODES[i])
    while i in PARENT:
        i = PARENT[i]
        M = node_matrix(NODES[i]) @ M
    return M


def image_of_texture(ti):
    src = J["textures"][ti]["source"]
    im = J["images"][src]
    bv = J["bufferViews"][im["bufferView"]]
    return Image.open(io.BytesIO(BIN[bv.get("byteOffset", 0):bv.get("byteOffset", 0) + bv["byteLength"]]))


def prim_geometry(mesh_index, M):
    """world-space positions, normals, uvs, faces, material index of the (single) primitive"""
    pr = J["meshes"][mesh_index]["primitives"][0]
    pos = accessor(pr["attributes"]["POSITION"]).astype(np.float64)
    nrm = accessor(pr["attributes"]["NORMAL"]).astype(np.float64)
    uv = accessor(pr["attributes"]["TEXCOORD_0"]).astype(np.float64)
    idx = accessor(pr["indices"]).reshape(-1, 3).astype(np.int64)
    P = (M[:3, :3] @ pos.T).T + M[:3, 3]
    N = (np.linalg.inv(M[:3, :3]).T @ nrm.T).T
    N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    if np.linalg.det(M[:3, :3]) < 0:        # mirrored transform -> keep triangle winding outward
        idx = idx[:, ::-1]
    return P, N, uv, idx, pr["material"]


def sub(P, N, uv, idx, mask_faces):
    f = idx[mask_faces]
    used, inv = np.unique(f.reshape(-1), return_inverse=True)
    return P[used], N[used], uv[used], inv.reshape(-1, 3)


def dominant_body_colour(img):
    """most common non-dark, reasonably lit colour of the diffuse map (the paint) -> (r,g,b) 0..1"""
    a = np.asarray(img.convert("RGB").resize((128, 128)), dtype=np.float32) / 255.0
    v = a.max(axis=2)
    keep = v > 0.28
    px = a[keep]
    if len(px) < 50:
        return [0.5, 0.5, 0.5]
    q = (px * 7).astype(np.int32)                    # 8^3 colour buckets
    key = q[:, 0] * 64 + q[:, 1] * 8 + q[:, 2]
    best = np.bincount(key).argmax()
    sel = px[key == best]
    return [round(float(x), 3) for x in sel.mean(axis=0)]


def process(game_id, node_name, real_len):
    top = next(i for i, n in enumerate(NODES) if n.get("name") == node_name)
    kids = NODES[top]["children"]
    body_node = next(k for k in kids if "mesh" in NODES[k] and "teker" not in NODES[k]["name"])
    rear_node = next(k for k in kids if NODES[k]["name"].startswith("arka_teker"))
    front_node = next(k for k in kids if NODES[k]["name"].startswith("on_teker"))
    B = prim_geometry(NODES[body_node]["mesh"], world(body_node))
    # wheel meshes live on a child of the *_teker transform node
    def mesh_node_under(k):
        stack = [k]
        while stack:
            c = stack.pop()
            if "mesh" in NODES[c]:
                return c
            stack += NODES[c].get("children", [])
    fw_node = mesh_node_under(front_node)
    rw_node = mesh_node_under(rear_node)
    FW = prim_geometry(NODES[fw_node]["mesh"], world(fw_node))
    RW = prim_geometry(NODES[rw_node]["mesh"], world(rw_node))
    # ---- orientation: front wheels -> rear wheels gives the forward axis (on the ground plane)
    fc = FW[0].mean(axis=0)
    rc = RW[0].mean(axis=0)
    fwd = fc - rc
    fwd[1] = 0
    fwd /= np.linalg.norm(fwd)
    ang = math.atan2(fwd[0], -fwd[2])               # rotation about +Y that maps fwd -> -Z
    c, s = math.cos(ang), math.sin(ang)
    R = np.array([[c, 0, -s], [0, 1, 0], [s, 0, c]])    # R @ fwd = (0,0,-1)
    assert np.allclose(R @ fwd, [0, 0, -1], atol=1e-6), (R @ fwd)

    def rot(G):
        return (R @ G[0].T).T, (R @ G[1].T).T, G[2], G[3]
    B = rot(B)
    FW = rot(FW)
    RW = rot(RW)
    length = B[0][:, 2].max() - B[0][:, 2].min()
    k = real_len / length
    # ground = lowest wheel vertex; origin x = body centre, z = middle between axle centres
    ymin = min(FW[0][:, 1].min(), RW[0][:, 1].min())
    fz = FW[0][:, 2].mean()
    rz = RW[0][:, 2].mean()
    ox = 0.5 * (B[0][:, 0].min() + B[0][:, 0].max())
    off = np.array([ox, ymin, 0.5 * (fz + rz)])

    def xf(G):
        P = (G[0] - off) * k
        return P, G[1], G[2], G[3]
    B = xf(B)
    FW = xf(FW)
    RW = xf(RW)
    # ---- split wheel pairs left/right by triangle centroid
    wheels = []
    names = []
    for G, axle in ((FW, "F"), (RW, "R")):
        P, N, uv, idx = G
        cx = P[idx][:, :, 0].mean(axis=1)
        for side, m in (("-X", cx < 0), ("+X", cx >= 0)):
            p, n_, u, f = sub(P, N, uv, idx, m)
            ctr = 0.5 * (p.min(axis=0) + p.max(axis=0))
            wheels.append((p - ctr, n_, u, f, ctr))
            names.append(axle + side)
    # ---- report
    bb_lo, bb_hi = B[0].min(axis=0), B[0].max(axis=0)
    wr = float(np.mean([(w[0][:, 1].max() - w[0][:, 1].min()) * 0.5 for w in wheels]))
    ww = float(np.mean([(w[0][:, 0].max() - w[0][:, 0].min()) for w in wheels]))
    report = {
        "length": round(float(bb_hi[2] - bb_lo[2]), 3), "width": round(float(bb_hi[0] - bb_lo[0]), 3), "height": round(float(bb_hi[1]), 3),
        "wheel_radius": round(wr, 3), "wheel_width": round(ww, 3),
        "wheelbase": round(float(wheels[2][4][2] - wheels[0][4][2]), 3),
        "track_f": round(float(wheels[1][4][0] - wheels[0][4][0]), 3),
        "track_r": round(float(wheels[3][4][0] - wheels[2][4][0]), 3),
        "wheel_y": [round(float(w[4][1]), 3) for w in wheels],
        "bb_min": [round(float(x), 3) for x in bb_lo], "bb_max": [round(float(x), 3) for x in bb_hi],
        "scale_applied": round(float(k), 4), "tris_body": int(len(B[3])), "tris_wheels": int(sum(len(w[3]) for w in wheels)),
    }
    # ---- textures (diffuse only; the spec-gloss map is dropped): body 512px JPEG, tyre 256px PNG
    mats = J["materials"]
    bm = mats[B_mat(NODES[body_node]["mesh"])]["extensions"]["KHR_materials_pbrSpecularGlossiness"]
    body_img = image_of_texture(bm["diffuseTexture"]["index"]).convert("RGB")
    report["paint_rgb"] = dominant_body_colour(body_img)
    body_img = body_img.resize((512, 512), Image.LANCZOS)
    wm = mats[B_mat(NODES[fw_node]["mesh"])]["extensions"]["KHR_materials_pbrSpecularGlossiness"]
    wheel_img = image_of_texture(wm["diffuseTexture"]["index"]).convert("RGB").resize((256, 256), Image.LANCZOS)

    def tm(P, N, uv, f, img, name, rough):
        uvf = uv.copy()                            # glTF uv origin is top-left; trimesh stores bottom-left
        uvf[:, 1] = 1.0 - uvf[:, 1]
        mat = PBRMaterial(name=name, baseColorTexture=img, metallicFactor=0.0, roughnessFactor=rough)
        m = trimesh.Trimesh(vertices=P, faces=f, vertex_normals=N, process=False)
        m.visual = TextureVisuals(uv=uvf, material=mat)
        return m
    scene = trimesh.Scene()
    scene.add_geometry(tm(B[0], B[1], B[2], B[3], body_img, "body", 0.45), node_name="Body", geom_name="Body")
    for i, w in enumerate(wheels):
        T = np.eye(4)
        T[:3, 3] = w[4]
        scene.add_geometry(tm(w[0], w[1], w[2], w[3], wheel_img, "tyre", 0.85), node_name="Wheel_%d" % i, geom_name="Wheel_%d" % i, transform=T)
    os.makedirs(OUT, exist_ok=True)
    scene.export(os.path.join(OUT, game_id + ".glb"))
    report["wheel_order"] = names
    return report


def B_mat(mesh_index):
    return J["meshes"][mesh_index]["primitives"][0]["material"]


if __name__ == "__main__":
    only = sys.argv[1:]
    rep = {}
    for gid, (node, ln) in VEHICLES.items():
        if only and gid not in only:
            continue
        rep[gid] = process(gid, node, ln)
        r = rep[gid]
        print("%-16s L %.2f W %.2f H %.2f  wr %.3f ww %.3f wb %.3f track %.2f/%.2f  tris %d+%d  k %.3f paint %s" % (
            gid, r["length"], r["width"], r["height"], r["wheel_radius"], r["wheel_width"], r["wheelbase"], r["track_f"], r["track_r"],
            r["tris_body"], r["tris_wheels"], r["scale_applied"], r["paint_rgb"]))
    if not only:
        json.dump(rep, open(os.path.join(ROOT, "tools/pack_report.json"), "w"), indent=1)

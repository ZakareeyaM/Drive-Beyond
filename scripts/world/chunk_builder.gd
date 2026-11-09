class_name ChunkBuilder
extends RefCounted
## Builds one 128 m world chunk: terrain, roads, sidewalks, bridges, rails,
## buildings, trees, rocks, street lamps. build() is thread-safe (data only);
## instantiate() turns the result into nodes on the main thread.

const C := WorldGen.CHUNK
const NV := WorldGen.VERTS

static func _push(buf: PackedFloat32Array, t: Transform3D, col: Color, use_col: bool, cust: Color, use_cust: bool) -> void:
	var b: Basis = t.basis
	var o: Vector3 = t.origin
	buf.append(b.x.x); buf.append(b.y.x); buf.append(b.z.x); buf.append(o.x)
	buf.append(b.x.y); buf.append(b.y.y); buf.append(b.z.y); buf.append(o.y)
	buf.append(b.x.z); buf.append(b.y.z); buf.append(b.z.z); buf.append(o.z)
	if use_col:
		buf.append(col.r); buf.append(col.g); buf.append(col.b); buf.append(col.a)
	if use_cust:
		buf.append(cust.r); buf.append(cust.g); buf.append(cust.b); buf.append(cust.a)

static func _mm_add(d: Dictionary, name: String, t: Transform3D, col: Color, cust: Color, use_col: bool, use_cust: bool) -> void:
	if not d.has(name):
		d[name] = {"buf": PackedFloat32Array(), "n": 0, "col": use_col, "cust": use_cust}
	var e: Dictionary = d[name]
	_push(e["buf"], t, col, use_col, cust, use_cust)
	e["n"] = int(e["n"]) + 1

static func build(w: WorldGen, cx: int, cz: int) -> Dictionary:
	var out: Dictionary = {"cx": cx, "cz": cz}
	var x0: float = -WorldGen.HALF + float(cx) * C
	var z0: float = -WorldGen.HALF + float(cz) * C
	var ix0: int = cx * (NV - 1)
	var iz0: int = cz * (NV - 1)
	# ---- heights with 1-vertex border for seamless normals ----------------------
	var B: int = NV + 2
	var H := PackedFloat32Array()
	H.resize(B * B)
	for j in range(B):
		for i in range(B):
			H[j * B + i] = w.ground_h_ix(ix0 + i - 1, iz0 + j - 1)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var hm := PackedFloat32Array()
	verts.resize(NV * NV)
	norms.resize(NV * NV)
	cols.resize(NV * NV)
	hm.resize(NV * NV)
	for j in range(NV):
		for i in range(NV):
			var h: float = H[(j + 1) * B + (i + 1)]
			var hl: float = H[(j + 1) * B + i]
			var hr: float = H[(j + 1) * B + (i + 2)]
			var hu: float = H[j * B + (i + 1)]
			var hd: float = H[(j + 2) * B + (i + 1)]
			var n := Vector3(hl - hr, 2.0 * WorldGen.CELL, hu - hd).normalized()
			var wx: float = x0 + float(i) * WorldGen.CELL
			var wz: float = z0 + float(j) * WorldGen.CELL
			verts[j * NV + i] = Vector3(float(i) * WorldGen.CELL, h, float(j) * WorldGen.CELL)
			norms[j * NV + i] = n
			hm[j * NV + i] = h
			var c: Color = w.terrain_color(wx, wz, h, n.y)
			var infl: float = w.infl[w.grid_index(ix0 + i, iz0 + j)] if (ix0 + i <= WorldGen.GRID_N and iz0 + j <= WorldGen.GRID_N) else 0.0
			if infl > 0.0:
				var reg: String = w.region_at(wx, wz)
				var shoulder: Color = Color(0.46, 0.46, 0.45) if reg == "city" else Color(0.34, 0.31, 0.27)
				if reg == "desert":
					shoulder = Color(0.62, 0.5, 0.33)
				c = c.lerp(shoulder, clampf(infl * 1.3, 0.0, 1.0))
			cols[j * NV + i] = c
	var idx := PackedInt32Array()
	for j in range(NV - 1):
		for i in range(NV - 1):
			var a: int = j * NV + i
			var b2: int = a + 1
			var c2: int = a + NV
			var d2: int = c2 + 1
			idx.append(a); idx.append(b2); idx.append(c2)
			idx.append(b2); idx.append(d2); idx.append(c2)
	out["t_verts"] = verts
	out["t_norms"] = norms
	out["t_cols"] = cols
	out["t_idx"] = idx
	out["heightmap"] = hm
	var mm: Dictionary = {}
	var coll: PackedFloat32Array = PackedFloat32Array()     # box colliders: 12 xform + 3 size
	var ncoll: int = 0
	var key: int = w.key(cx, cz)
	var rng := RandomNumberGenerator.new()
	rng.seed = key * 7919 + w.seed_value
	# ---- roads ---------------------------------------------------------------------
	var rv := PackedVector3Array()
	var rn := PackedVector3Array()
	var ru := PackedVector2Array()
	var rc := PackedColorArray()
	var ri := PackedInt32Array()
	var sv := PackedVector3Array()
	var sc := PackedColorArray()
	var si := PackedInt32Array()
	if w.seg_index.has(key):
		var sg: PackedInt32Array = w.seg_index[key]
		for q in range(0, sg.size(), 2):
			var ei: int = sg[q]
			var k: int = sg[q + 1]
			var e: Dictionary = w.edges[ei]
			var pts: PackedVector3Array = e["pts"]
			var cum: PackedFloat32Array = e["cum"]
			var br: PackedByteArray = e["bridge"]
			var hw: float = float(e["width"]) * 0.5
			var kind: String = e["kind"]
			var info: Dictionary = WorldGen.KINDS[kind]
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[k + 1]
			var ta: Vector3 = (pts[k + 1] - pts[maxi(k - 1, 0)])
			var tb: Vector3 = (pts[mini(k + 2, pts.size() - 1)] - pts[k])
			ta = Vector3(ta.x, 0, ta.z).normalized()
			tb = Vector3(tb.x, 0, tb.z).normalized()
			if ta.length() < 0.5 or tb.length() < 0.5:
				continue
			var na := Vector3(-ta.z, 0, ta.x)
			var nb := Vector3(-tb.z, 0, tb.x)
			var kv: float = 0.0
			if kind == "dirt":
				kv = 0.5
			elif kind == "track":
				kv = 1.0
			var fade0: float = 1.0
			var fade1: float = 1.0
			var da: int = w.node_adj[int(e["a"])].size()
			var db: int = w.node_adj[int(e["b"])].size()
			if k < 2 and da >= 3:
				fade0 = 0.0
				fade1 = 0.0 if k == 0 else 1.0
			if k >= pts.size() - 3 and db >= 3:
				fade1 = 0.0
				fade0 = 0.0 if k == pts.size() - 2 else fade0
			var col0 := Color(float(e["lanes"]) / 4.0, kv, float(e["width"]) / 32.0, fade0)
			var col1 := Color(float(e["lanes"]) / 4.0, kv, float(e["width"]) / 32.0, fade1)
			var y0: float = p0.y + 0.05
			var y1: float = p1.y + 0.05
			var L0 := Vector3(p0.x - x0 - na.x * hw, y0, p0.z - z0 - na.z * hw)
			var R0 := Vector3(p0.x - x0 + na.x * hw, y0, p0.z - z0 + na.z * hw)
			var L1 := Vector3(p1.x - x0 - nb.x * hw, y1, p1.z - z0 - nb.z * hw)
			var R1 := Vector3(p1.x - x0 + nb.x * hw, y1, p1.z - z0 + nb.z * hw)
			var vb: int = rv.size()
			rv.append(L0); rv.append(R0); rv.append(L1); rv.append(R1)
			for _n in range(4):
				rn.append(Vector3.UP)
			ru.append(Vector2(0, cum[k])); ru.append(Vector2(1, cum[k])); ru.append(Vector2(0, cum[k + 1])); ru.append(Vector2(1, cum[k + 1]))
			rc.append(col0); rc.append(col0); rc.append(col1); rc.append(col1)
			ri.append(vb); ri.append(vb + 2); ri.append(vb + 1)
			ri.append(vb + 1); ri.append(vb + 2); ri.append(vb + 3)
			# sidewalks
			var near_junction: bool = (da >= 3 and cum[k] < float(e["width"]) * 0.5 + 5.0) or (db >= 3 and cum[k + 1] > float(e["len"]) - float(e["width"]) * 0.5 - 5.0)
			if info["side"] and not near_junction:
				var sw: float = 3.2
				var wc := Color(0.56, 0.56, 0.54)
				for side in [-1.0, 1.0]:
					var in0: Vector3 = Vector3(p0.x - x0 + na.x * hw * side, p0.y + 0.07, p0.z - z0 + na.z * hw * side)
					var ou0: Vector3 = Vector3(p0.x - x0 + na.x * (hw + sw) * side, p0.y + 0.07, p0.z - z0 + na.z * (hw + sw) * side)
					var in1: Vector3 = Vector3(p1.x - x0 + nb.x * hw * side, p1.y + 0.07, p1.z - z0 + nb.z * hw * side)
					var ou1: Vector3 = Vector3(p1.x - x0 + nb.x * (hw + sw) * side, p1.y + 0.07, p1.z - z0 + nb.z * (hw + sw) * side)
					var sb: int = sv.size()
					sv.append(in0); sv.append(ou0); sv.append(in1); sv.append(ou1)
					sc.append(wc); sc.append(wc); sc.append(wc); sc.append(wc)
					if side > 0.0:
						si.append(sb); si.append(sb + 2); si.append(sb + 1)
						si.append(sb + 1); si.append(sb + 2); si.append(sb + 3)
					else:
						si.append(sb); si.append(sb + 1); si.append(sb + 2)
						si.append(sb + 1); si.append(sb + 3); si.append(sb + 2)
			# bridge deck + parapets
			if br[k] == 1 or br[k + 1] == 1:
				var mid: Vector3 = (p0 + p1) * 0.5
				var dir: Vector3 = (p1 - p0)
				var slen: float = dir.length()
				var fwd: Vector3 = dir.normalized()
				var up := Vector3.UP
				var bz: Vector3 = fwd
				var bx: Vector3 = up.cross(bz).normalized()
				var by: Vector3 = bz.cross(bx).normalized()
				var bas := Basis(bx, by, bz)
				var deck_t := Transform3D(bas.scaled(Vector3(hw * 2.0 + 1.6, 1.2, slen + 0.2)), mid + Vector3(0, 0.05 - 1.2, 0) + by * 0.0)
				deck_t.origin = mid + Vector3(0, 0.05, 0) - by * 1.2
				_mm_add(mm, "struct", deck_t, Color(0.5, 0.5, 0.52), Color(0, 0, 0, 0), true, false)
				_append_box(coll, Transform3D(bas, mid + Vector3(0, 0.05, 0) - by * 0.6), Vector3(hw * 2.0 + 1.6, 1.2, slen + 0.2))
				ncoll += 1
				for side in [-1.0, 1.0]:
					var po: Vector3 = mid + bx * (hw + 0.55) * side + Vector3(0, 0.55, 0)
					var pt := Transform3D(bas.scaled(Vector3(0.4, 1.1, slen + 0.2)), po - by * 0.0)
					pt.origin = po - by * 0.0 - Vector3(0, 0.55, 0) + Vector3(0, 0.05, 0) * 0.0
					pt.origin = mid + bx * (hw + 0.55) * side + Vector3(0, 0.05, 0)
					_mm_add(mm, "struct", pt, Color(0.62, 0.62, 0.64), Color(0, 0, 0, 0), true, false)
					_append_box(coll, Transform3D(bas, mid + bx * (hw + 0.55) * side + Vector3(0, 0.6, 0)), Vector3(0.4, 1.1, slen + 0.2))
					ncoll += 1
			# street furniture every few samples
			var wp: Vector3 = Vector3(p0.x, p0.y, p0.z)
			var rr: float = sqrt(wp.x * wp.x + wp.z * wp.z)
			var lamp_every: int = 0
			if kind == "street" or kind == "avenue":
				lamp_every = 8
			elif kind == "suburb":
				lamp_every = 10
			elif kind == "highway" and rr < 900.0:
				lamp_every = 10
			elif kind == "industrial":
				lamp_every = 12
			if lamp_every > 0 and k % lamp_every == 0 and br[k] == 0:
				var side2: float = 1.0 if (k / lamp_every + ei) % 2 == 0 else -1.0
				var off: float = hw + (1.6 if info["side"] else 3.0)
				var lp: Vector3 = Vector3(p0.x + na.x * off * side2, p0.y + 0.07, p0.z + na.z * off * side2)
				var ang: float = atan2(na.z * side2, -na.x * side2)
				var lb := Basis(Vector3.UP, ang)
				_mm_add(mm, "lamp", Transform3D(lb, Vector3(lp.x, lp.y, lp.z)), Color.WHITE, Color(0, 0, 0, 0), false, false)
				_append_box(coll, Transform3D(Basis(Vector3.UP, ang), lp + Vector3(0, 3.5, 0)), Vector3(0.3, 7.0, 0.3))
				ncoll += 1
				var head: Vector3 = lp + lb * Vector3(1.75, 0.0, 0.0)
				_mm_add(mm, "pool", Transform3D(Basis.IDENTITY, Vector3(head.x, p0.y + 0.13, head.z)), Color(1, 1, 1, 1), Color(0, 0, 0, 0), true, false)
			if kind == "avenue" and rr < 560.0 and k % 5 == 2 and br[k] == 0:
				var sd: float = 1.0 if (k / 5) % 2 == 0 else -1.0
				var pp: Vector3 = Vector3(p0.x + na.x * (hw + 2.6) * sd, p0.y + 0.06, p0.z + na.z * (hw + 2.6) * sd)
				_mm_add(mm, "palm", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.1)), pp), Color(1, 1, 1, 1), Color(0, 0, 0, 0), true, false)
				_append_box(coll, Transform3D(Basis.IDENTITY, pp + Vector3(0, 2.5, 0)), Vector3(0.55, 5.0, 0.55))
				ncoll += 1
			if kind == "coastal" and w.region_at(p0.x, p0.z) == "coast" and k % 6 == 3 and br[k] == 0:
				var sd2: float = 1.0 if (k / 6) % 2 == 0 else -1.0
				var pp2: Vector3 = Vector3(p0.x + na.x * (hw + 3.0) * sd2, p0.y, p0.z + na.z * (hw + 3.0) * sd2)
				_mm_add(mm, "palm", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.1)), pp2), Color(1, 1, 1, 1), Color(0, 0, 0, 0), true, false)
				_append_box(coll, Transform3D(Basis.IDENTITY, pp2 + Vector3(0, 2.5, 0)), Vector3(0.55, 5.0, 0.55))
				ncoll += 1
			# guard rails where there is a drop-off
			if (kind == "mountain" or kind == "coastal" or kind == "highway") and k % 2 == 0 and br[k] == 0:
				for side3 in [-1.0, 1.0]:
					var lo: float = hw + 2.6
					var gx: float = p0.x + na.x * lo * side3
					var gz: float = p0.z + na.z * lo * side3
					var gh: float = w.ground_h(gx, gz)
					if gh < p0.y - 3.2 and gh > -40.0 or (gh < p0.y - 3.2 and w.nat_h(gx, gz) < 0.0):
						var rb: Vector3 = ta
						var rbx: Vector3 = Vector3.UP.cross(rb).normalized()
						var rby: Vector3 = rb.cross(rbx).normalized()
						var rbas := Basis(rbx, rby, rb)
						var rpos: Vector3 = Vector3(p0.x + na.x * (hw + 1.2) * side3, p0.y + 0.5, p0.z + na.z * (hw + 1.2) * side3) + rb * 5.0
						_mm_add(mm, "struct", Transform3D(rbas.scaled(Vector3(0.25, 0.7, 10.3)), rpos - rby * 0.35), Color(0.62, 0.64, 0.66), Color(0, 0, 0, 0), true, false)
						_append_box(coll, Transform3D(rbas, rpos), Vector3(0.3, 1.0, 10.3))
						ncoll += 1
	out["r_verts"] = rv
	out["r_norms"] = rn
	out["r_uvs"] = ru
	out["r_cols"] = rc
	out["r_idx"] = ri
	out["s_verts"] = sv
	out["s_cols"] = sc
	out["s_idx"] = si
	# ---- buildings ---------------------------------------------------------------------
	if w.buildings.has(key):
		for b in w.buildings[key]:
			var p: Vector3 = b["p"]
			var s: Vector3 = b["s"]
			var col: Color = b["c"]
			var kind2: String = b["kind"]
			var yaw: float = float(b.get("yaw", 0.0))
			var cust := Color(float(b.get("lit", 0.5)), float(b.get("win", 1.0)), float(b.get("seed", 1.0)), 0.0)
			var by0: float = p.y - 0.3
			var basis := Basis(Vector3.UP, yaw)
			if kind2 == "pack":
				_append_box(coll, Transform3D(basis, Vector3(p.x, by0 + s.y * 0.5, p.z)), Vector3(s.x * 0.96, s.y, s.z * 0.96))
				ncoll += 1
				continue
			if kind2 == "house" or kind2 == "barn":
				var wall: float = 3.1 if kind2 == "house" else s.y * 0.6
				_mm_add(mm, "bld", Transform3D(basis.scaled(Vector3(s.x, wall + 0.3, s.z)), Vector3(p.x, by0, p.z)), col, cust, true, true)
				var rcol: Color = Color(0.45, 0.2, 0.15) if kind2 == "house" else Color(0.3, 0.3, 0.32)
				if rng.randf() < 0.4 and kind2 == "house":
					rcol = Color(0.25, 0.27, 0.3)
				var rb2 := basis * Basis(Vector3.UP, PI * 0.5 * (1.0 if rng.randf() < 0.5 else 0.0))
				_mm_add(mm, "roof", Transform3D(rb2.scaled(Vector3(s.x + 0.8, s.y - wall, s.z + 0.8) if kind2 == "house" else Vector3(s.z * 0.0 + s.x + 0.6, s.y - wall, s.z + 0.6)), Vector3(p.x, by0 + wall, p.z)), rcol, Color(0, 0, 0, 0), true, false)
				_append_box(coll, Transform3D(basis, Vector3(p.x, by0 + wall * 0.5 + 0.2, p.z)), Vector3(s.x, wall + 0.2, s.z))
				ncoll += 1
			elif kind2 == "ruin":
				_mm_add(mm, "bld", Transform3D(basis.scaled(Vector3(s.x, s.y * 0.7, s.z)), Vector3(p.x, by0, p.z)), col, cust, true, true)
				_mm_add(mm, "bld", Transform3D(Basis(Vector3.UP, yaw + 0.5).scaled(Vector3(s.x * 0.4, s.y * 1.1, s.z * 0.5)), Vector3(p.x + s.x * 0.5, by0, p.z)), col * 0.8, cust, true, true)
				_append_box(coll, Transform3D(basis, Vector3(p.x, by0 + s.y * 0.35, p.z)), Vector3(s.x, s.y * 0.7, s.z))
				ncoll += 1
			else:
				_mm_add(mm, "bld", Transform3D(basis.scaled(s), Vector3(p.x, by0, p.z)), col, cust, true, true)
				_append_box(coll, Transform3D(basis, Vector3(p.x, by0 + s.y * 0.5, p.z)), s)
				ncoll += 1
				if kind2 == "tower":
					var cs: Vector3 = Vector3(s.x * 0.62, s.y * 0.14, s.z * 0.62)
					_mm_add(mm, "bld", Transform3D(basis.scaled(cs), Vector3(p.x, by0 + s.y, p.z)), col * 0.85, cust, true, true)
					if rng.randf() < 0.5:
						_mm_add(mm, "bld", Transform3D(basis.scaled(Vector3(0.6, s.y * 0.1, 0.6)), Vector3(p.x, by0 + s.y + cs.y, p.z)), Color(0.5, 0.5, 0.55), Color(0, 0, 0, 0), true, true)
				elif kind2 == "apartment" and rng.randf() < 0.4:
					_mm_add(mm, "bld", Transform3D(basis.scaled(Vector3(s.x * 0.5, 3.0, s.z * 0.5)), Vector3(p.x, by0 + s.y, p.z)), col * 0.7, Color(0, 0, 0, 0), true, true)
	# ---- vegetation + rocks -----------------------------------------------------------
	var step: float = 9.0
	var cells: int = int(C / step)
	for gj in range(cells):
		for gi in range(cells):
			var tx: float = x0 + (float(gi) + rng.randf()) * step
			var tz: float = z0 + (float(gj) + rng.randf()) * step
			var roll: float = rng.randf()
			var roll2: float = rng.randf()
			var rw: float = w.road_weight(tx, tz)
			if rw > 0.01:
				continue
			var th: float = _local_h(hm, tx - x0, tz - z0)
			if th < 0.6:
				continue
			var reg: String = w.region_at(tx, tz)
			var dens: float = w.tree_density(tx, tz, th)
			if roll < dens and w._free_of_roads(tx, tz, 6.0):
				var sc2: float = rng.randf_range(0.8, 1.6)
				var tint: Color = Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.1), 1.0)
				var tb2 := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * sc2)
				var name2: String = "pine" if (reg == "forest" or reg == "mountain") and roll2 < 0.8 else "oak"
				if reg == "coast":
					name2 = "palm"
				_mm_add(mm, name2, Transform3D(tb2, Vector3(tx, th - 0.1, tz)), tint, Color(0, 0, 0, 0), true, false)
				var tw: float = (0.5 if name2 != "pine" else 0.45) * sc2
				_append_box(coll, Transform3D(Basis.IDENTITY, Vector3(tx, th + 2.0 * sc2, tz)), Vector3(tw, 4.0 * sc2, tw))
				ncoll += 1
			elif reg == "desert" and roll2 < 0.035 and w._free_of_roads(tx, tz, 8.0):
				_mm_add(mm, "cactus", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), Vector3(tx, th - 0.1, tz)), Color(1, 1, 1, 1), Color(0, 0, 0, 0), true, false)
				_append_box(coll, Transform3D(Basis.IDENTITY, Vector3(tx, th + 1.0, tz)), Vector3(0.7, 2.0, 0.7))
				ncoll += 1
			elif (reg == "mountain" or reg == "desert" or (reg == "coast" and th < 4.0)) and roll2 < (0.1 if reg == "mountain" else 0.05) and w._free_of_roads(tx, tz, 8.0):
				var rs: float = rng.randf_range(0.8, 3.2)
				var rcol2: Color = Color(1.0, 0.85, 0.65) if reg == "desert" else Color(1, 1, 1)
				_mm_add(mm, "rock", Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rs, rs * rng.randf_range(0.6, 1.1), rs)), Vector3(tx, th - 0.2, tz)), rcol2, Color(0, 0, 0, 0), true, false)
				_append_box(coll, Transform3D(Basis.IDENTITY, Vector3(tx, th + rs * 0.45, tz)), Vector3(rs * 1.5, rs * 0.9, rs * 1.5))
				ncoll += 1
	out["mm"] = mm
	out["coll"] = coll
	out["ncoll"] = ncoll
	return out

static func _local_h(hm: PackedFloat32Array, lx: float, lz: float) -> float:
	var fx: float = clampf(lx / WorldGen.CELL, 0.0, float(NV - 1) - 0.001)
	var fz: float = clampf(lz / WorldGen.CELL, 0.0, float(NV - 1) - 0.001)
	var ix: int = int(fx)
	var iz: int = int(fz)
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	var h00: float = hm[iz * NV + ix]
	var h10: float = hm[iz * NV + ix + 1]
	var h01: float = hm[(iz + 1) * NV + ix]
	var h11: float = hm[(iz + 1) * NV + ix + 1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

static func _append_box(coll: PackedFloat32Array, t: Transform3D, size: Vector3) -> void:
	var b: Basis = t.basis.orthonormalized()
	var o: Vector3 = t.origin
	coll.append(b.x.x); coll.append(b.y.x); coll.append(b.z.x); coll.append(o.x)
	coll.append(b.x.y); coll.append(b.y.y); coll.append(b.z.y); coll.append(o.y)
	coll.append(b.x.z); coll.append(b.y.z); coll.append(b.z.z); coll.append(o.z)
	coll.append(size.x); coll.append(size.y); coll.append(size.z)

static func _append_box_small(coll: PackedFloat32Array, pos: Vector3) -> void:
	_append_box(coll, Transform3D(Basis.IDENTITY, pos), Vector3(0.7, 3.0, 0.7))

# ------------------------------------------------------------------ main thread
static func instantiate(data: Dictionary, assets: Dictionary, quality: Dictionary) -> Node3D:
	var root := Node3D.new()
	var cx: int = data["cx"]
	var cz: int = data["cz"]
	var x0: float = -WorldGen.HALF + float(cx) * C
	var z0: float = -WorldGen.HALF + float(cz) * C
	root.name = "Chunk_%d_%d" % [cx, cz]
	var origin := Vector3(x0, 0, z0)
	# terrain mesh
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = data["t_verts"]
	arr[Mesh.ARRAY_NORMAL] = data["t_norms"]
	arr[Mesh.ARRAY_COLOR] = data["t_cols"]
	arr[Mesh.ARRAY_INDEX] = data["t_idx"]
	var tm := ArrayMesh.new()
	tm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var ti := MeshInstance3D.new()
	ti.mesh = tm
	ti.material_override = assets["mat_terrain"]
	ti.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ti.position = origin
	root.add_child(ti)
	# terrain collision
	var body := StaticBody3D.new()
	var hs := HeightMapShape3D.new()
	hs.map_width = NV
	hs.map_depth = NV
	hs.map_data = data["heightmap"]
	var cs := CollisionShape3D.new()
	cs.shape = hs
	body.add_child(cs)
	body.position = origin + Vector3(C * 0.5, 0, C * 0.5)
	body.scale = Vector3(WorldGen.CELL, 1, WorldGen.CELL)
	body.add_to_group("terrain")
	root.add_child(body)
	# roads
	var rv: PackedVector3Array = data["r_verts"]
	if rv.size() > 0:
		var ra: Array = []
		ra.resize(Mesh.ARRAY_MAX)
		ra[Mesh.ARRAY_VERTEX] = rv
		ra[Mesh.ARRAY_NORMAL] = data["r_norms"]
		ra[Mesh.ARRAY_TEX_UV] = data["r_uvs"]
		ra[Mesh.ARRAY_COLOR] = data["r_cols"]
		ra[Mesh.ARRAY_INDEX] = data["r_idx"]
		var rm := ArrayMesh.new()
		rm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, ra)
		var rmi := MeshInstance3D.new()
		rmi.mesh = rm
		rmi.material_override = assets["mat_road"]
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rmi.visibility_range_end = float(quality.get("detail_range", 600.0)) + 200.0
		rmi.position = origin
		root.add_child(rmi)
	var sv: PackedVector3Array = data["s_verts"]
	if sv.size() > 0:
		var sa: Array = []
		sa.resize(Mesh.ARRAY_MAX)
		sa[Mesh.ARRAY_VERTEX] = sv
		var sn := PackedVector3Array()
		sn.resize(sv.size())
		sn.fill(Vector3.UP)
		sa[Mesh.ARRAY_NORMAL] = sn
		sa[Mesh.ARRAY_COLOR] = data["s_cols"]
		sa[Mesh.ARRAY_INDEX] = data["s_idx"]
		var sm := ArrayMesh.new()
		sm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sa)
		var smi := MeshInstance3D.new()
		smi.mesh = sm
		smi.material_override = assets["mat_plain"]
		smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		smi.visibility_range_end = float(quality.get("detail_range", 600.0)) + 200.0
		smi.position = origin
		root.add_child(smi)
	# multimeshes
	var mm: Dictionary = data["mm"]
	for name in mm:
		var e: Dictionary = mm[name]
		if int(e["n"]) == 0:
			continue
		var m := MultiMesh.new()
		m.transform_format = MultiMesh.TRANSFORM_3D
		m.use_colors = e["col"]
		m.use_custom_data = e["cust"]
		m.mesh = assets["mesh_" + name]
		m.instance_count = int(e["n"])
		m.buffer = e["buf"]
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = m
		mi.material_override = assets["mat_" + name]
		match name:
			"lamp", "pool":
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = 300.0 if name == "lamp" else 220.0
			"pine", "oak", "palm", "cactus":
				mi.visibility_range_end = float(quality.get("tree_range", 320.0))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if bool(quality.get("tree_shadows", false)) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"rock":
				mi.visibility_range_end = 280.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"struct":
				mi.visibility_range_end = 320.0
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_:
				pass
		root.add_child(mi)
	# box colliders (buildings, rails, bridge decks)
	var coll: PackedFloat32Array = data["coll"]
	var nc: int = int(data["ncoll"])
	if nc > 0:
		var sb := StaticBody3D.new()
		sb.add_to_group("structure")
		for q in range(nc):
			var o: int = q * 15
			var basis := Basis(Vector3(coll[o], coll[o + 4], coll[o + 8]), Vector3(coll[o + 1], coll[o + 5], coll[o + 9]), Vector3(coll[o + 2], coll[o + 6], coll[o + 10]))
			var shp := BoxShape3D.new()
			shp.size = Vector3(coll[o + 12], coll[o + 13], coll[o + 14])
			var cshape := CollisionShape3D.new()
			cshape.shape = shp
			cshape.transform = Transform3D(basis, Vector3(coll[o + 3], coll[o + 7], coll[o + 11]))
			sb.add_child(cshape)
		root.add_child(sb)
	return root

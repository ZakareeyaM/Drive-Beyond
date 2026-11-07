extends SceneTree
func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var w := WorldGen.new()
	w.build_all()
	print("build ms: ", Time.get_ticks_msec() - t0)
	print("nodes ", w.nodes.size(), " edges ", w.edges.size(), " bridges ", w.bridges.size(), " tunnels ", w.tunnels.size())
	var tot := 0.0
	var pts := 0
	for e in w.edges:
		tot += e["len"]; pts += e["pts"].size()
	print("road km ", tot / 1000.0, " pts ", pts)
	var nb := 0
	for k in w.buildings: nb += w.buildings[k].size()
	print("buildings ", nb, " structures ", w.structures.size(), " landmarks ", w.landmarks.size())
	print("home ", w.landmarks["home_garage"], " h ", w.ground_h(0, 0))
	# max grade over edges
	var worst := 0.0
	var worst_e := ""
	for e in w.edges:
		var p: PackedVector3Array = e["pts"]
		for i in range(1, p.size()):
			var d := Vector2(p[i].x - p[i-1].x, p[i].z - p[i-1].z).length()
			var g: float = absf(p[i].y - p[i-1].y) / maxf(d, 0.01)
			if g > worst:
				worst = g; worst_e = e["name"]
	print("max grade ", worst, " on ", worst_e)
	for b in w.bridges:
		print("bridge edge ", w.edges[b["edge"]]["name"], " ", b["i0"], "-", b["i1"])
	quit()

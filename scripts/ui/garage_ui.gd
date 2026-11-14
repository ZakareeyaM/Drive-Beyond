class_name GarageUI
extends Control
## 3D garage: owned cars, performance upgrades (which change real stats),
## visual customisation, repair, garage expansion and selling.

signal closed

var world: World
var showroom: Showroom
var tab: String = "cars"
var content: VBoxContainer
var stats_box: VBoxContainer
var money_lbl: Label
var tab_btns: Dictionary = {}
var vid: String = ""

const VISUAL_ROWS := [
	["paint", "Primary Paint", "paint"], ["paint2", "Two-Tone Roof", "paint2"], ["wheel_color", "Wheel Colour", "paint"],
	["rims", "Rims", "rims"], ["spoiler", "Spoiler", "spoiler"], ["bumper", "Bumper", "bumper"], ["bodykit", "Body Kit", "bodykit"],
	["tint", "Window Tint", "tint"], ["headlights", "Headlights", "headlights"], ["underglow", "Underglow", "underglow"],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	vid = Game.selected
	showroom = Showroom.new()
	add_child(showroom)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	row.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.title_bar("GARAGE", "Rico's workshop"))
	var tabs := HBoxContainer.new()
	lv.add_child(tabs)
	for t in [["cars", "Cars"], ["perf", "Performance"], ["visual", "Visual"], ["repair", "Repair"]]:
		var b: Button = UIKit.button(t[1], _set_tab.bind(t[0]), 48)
		b.add_theme_font_size_override("font_size", 18)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		tab_btns[t[0]] = b
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc: ScrollContainer = UIKit.scroll(content, Vector2(470, 300))
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sc)
	lv.add_child(UIKit.accent_button("Leave Garage", _close, 56))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(right)
	money_lbl = UIKit.label("", 34, UIKit.GREEN, 2)
	right.add_child(money_lbl)
	var sp := PanelContainer.new()
	sp.custom_minimum_size = Vector2(340, 0)
	right.add_child(sp)
	stats_box = VBoxContainer.new()
	sp.add_child(stats_box)
	Game.money_changed.connect(_on_money)
	Game.garage_changed.connect(_refresh)
	_refresh()

func _on_money(_m: int) -> void:
	money_lbl.text = Game.fmt_money(Game.money)

func _close() -> void:
	closed.emit()

func _set_tab(t: String) -> void:
	tab = t
	_refresh()

func _refresh() -> void:
	money_lbl.text = Game.fmt_money(Game.money)
	if not Game.owned.has(vid):
		vid = Game.selected
	for k in tab_btns:
		(tab_btns[k] as Button).disabled = k == tab
	var rec: Dictionary = Game.owned[vid]
	showroom.show_car(vid, rec["custom"], rec["upg"])
	UIKit.clear(content)
	match tab:
		"cars": _tab_cars()
		"perf": _tab_perf()
		"visual": _tab_visual()
		"repair": _tab_repair()
	_stats()

func _stats() -> void:
	UIKit.clear(stats_box)
	var spec: Dictionary = Data.vehicle(vid)
	var rec: Dictionary = Game.owned[vid]
	stats_box.add_child(UIKit.label(String(spec["name"]), 30))
	stats_box.add_child(UIKit.label("%s  |  %s  |  %s" % [spec["cat"], spec["drive"], String(spec["engine"]).to_upper()], 17, UIKit.MUTED))
	var r: Dictionary = Data.rating(vid, rec["upg"])
	var base: Dictionary = Data.rating(vid, Data.default_upgrades())
	for k in [["speed", "Top Speed"], ["accel", "Acceleration"], ["handling", "Handling"], ["braking", "Braking"]]:
		var h := HBoxContainer.new()
		var l: Label = UIKit.label(k[1], 18, UIKit.MUTED)
		l.custom_minimum_size = Vector2(120, 0)
		h.add_child(l)
		h.add_child(UIKit.bar(float(r[k[0]]), UIKit.RED, 130.0))
		var gain: int = int(round(float(r[k[0]]) - float(base[k[0]])))
		h.add_child(UIKit.label(("+%d" % gain) if gain > 0 else "", 16, UIKit.GREEN))
		stats_box.add_child(h)
	var s: Dictionary = Data.final_stats(vid, rec["upg"])
	stats_box.add_child(UIKit.label("%d %s top  |  %d kg" % [int(Game.speed_to_display(float(s["top"]))), Game.unit_label(), int(s["mass"])], 17, UIKit.MUTED))
	stats_box.add_child(UIKit.label("Condition: %d%%   Fuel: %d%%" % [int((1.0 - float(rec["damage"])) * 100.0), int(float(rec["fuel"]) * 100.0)], 17, UIKit.MUTED))
	stats_box.add_child(UIKit.label("Value: " + Game.fmt_money(Data.sell_value(vid, rec["upg"])), 17, UIKit.GOLD))

func _row_label(text: String, sub: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.add_child(UIKit.label(text, 21))
	if sub != "":
		v.add_child(UIKit.label(sub, 15, UIKit.MUTED))
	return v

# ------------------------------------------------------------ cars
func _tab_cars() -> void:
	content.add_child(UIKit.label("Paid slots %d / %d  -  starter and free cars are always yours" % [Game.slots_used(), Game.garage_slots], 16, UIKit.MUTED))
	for id in Game.owned:
		var spec: Dictionary = Data.vehicle(id)
		var h := HBoxContainer.new()
		var tag: String = "ACTIVE" if id == Game.selected else ("FREE" if Data.is_free_vehicle(id) else "OWNED")
		var b: Button = UIKit.button("%s   [%s]\n%s  |  %s  |  %s" % [spec["name"], tag, spec["cat"], spec["drive"], String(spec["engine"]).to_upper()], _pick_car.bind(id), 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 18)
		if id == vid:
			b.add_theme_stylebox_override("normal", UIKit.box(UIKit.RED_DARK, 8, UIKit.RED, 2, 14))
		h.add_child(b)
		content.add_child(h)
	content.add_child(UIKit.spacer(6))
	var sel: Button = UIKit.accent_button("Drive this car" if vid != Game.selected else "Currently selected", _select_car, 54)
	sel.disabled = vid == Game.selected
	content.add_child(sel)
	var sell: Button = UIKit.button("Permanent vehicle - cannot be sold" if Data.is_permanent(vid) else ("Sell for " + Game.fmt_money(Data.sell_value(vid, Game.owned[vid]["upg"]))), _sell, 50)
	sell.disabled = Game.owned.size() <= 1 or Data.is_permanent(vid)
	content.add_child(sell)
	if Game.garage_slots < 12:
		content.add_child(UIKit.button("Expand garage (+1 slot)  " + Game.fmt_money(Game.expand_cost()), func() -> void: Game.expand_garage(), 50))

func _pick_car(id: String) -> void:
	vid = id
	_refresh()

func _select_car() -> void:
	Game.selected = vid
	Game.garage_changed.emit()
	Game.notify.emit("Selected " + String(Data.vehicle(vid)["name"]), "info")

func _sell() -> void:
	if Game.sell_vehicle(vid):
		vid = Game.selected
		_refresh()

# ------------------------------------------------------------ performance
func _tab_perf() -> void:
	var rec: Dictionary = Game.owned[vid]
	for part in Data.PERF_PARTS:
		var lvl: int = int(rec["upg"].get(part, 0))
		var panel := PanelContainer.new()
		var hv := HBoxContainer.new()
		panel.add_child(hv)
		var lv := _row_label(Data.PART_LABEL[part], Data.PART_DESC[part])
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hv.add_child(lv)
		var pips: String = ""
		for i in Data.MAX_UPGRADE_LEVEL:
			pips += "■ " if i < lvl else "□ "
		hv.add_child(UIKit.label(pips, 20, UIKit.RED))
		if lvl >= Data.MAX_UPGRADE_LEVEL:
			var mx: Button = UIKit.button("MAX", Callable(), 46, 120)
			mx.disabled = true
			hv.add_child(mx)
		else:
			var cost: int = Data.upgrade_cost(vid, part, lvl + 1)
			var b: Button = UIKit.button(Game.fmt_money(cost), _buy_perf.bind(part), 46, 120)
			b.disabled = Game.money < cost
			hv.add_child(b)
		content.add_child(panel)

func _buy_perf(part: String) -> void:
	if Game.buy_upgrade(vid, part):
		world.audio.play_ui("pickup")

# ------------------------------------------------------------ visual
func _names_for(src: String) -> Array:
	var out: Array = []
	match src:
		"paint":
			for p in Data.PAINTS:
				out.append(p["n"])
		"paint2":
			for p in Data.PAINTS:
				out.append(p["n"])
			out[1] = "None"
		"rims": out = Data.RIM_NAMES
		"spoiler": out = Data.SPOILER_NAMES
		"bumper": out = Data.BUMPER_NAMES
		"bodykit": out = Data.BODYKIT_NAMES
		"tint": out = Data.TINT_NAMES
		"headlights":
			for p in Data.HEADLIGHTS:
				out.append(p["n"])
		"underglow":
			for p in Data.UNDERGLOWS:
				out.append(p["n"])
	return out

func _tab_visual() -> void:
	var rec: Dictionary = Game.owned[vid]
	for vr in VISUAL_ROWS:
		var key: String = vr[0]
		var names: Array = _names_for(vr[2])
		var cur: int = int(rec["custom"].get(key, 0)) % names.size()
		var panel := PanelContainer.new()
		var hv := HBoxContainer.new()
		panel.add_child(hv)
		var lv := _row_label(vr[1], "%s  -  %s" % [names[cur], Game.fmt_money(int(Data.CUSTOM_COST[key]))])
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hv.add_child(lv)
		hv.add_child(UIKit.button("◀", _cycle.bind(key, -1, names.size()), 46, 56))
		hv.add_child(UIKit.button("▶", _cycle.bind(key, 1, names.size()), 46, 56))
		content.add_child(panel)
	var pp := PanelContainer.new()
	var ph := HBoxContainer.new()
	pp.add_child(ph)
	var pl := _row_label("Number Plate", "7 characters, $100")
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph.add_child(pl)
	var le := LineEdit.new()
	le.text = String(rec["custom"].get("plate", "DB-001"))
	le.max_length = 7
	le.custom_minimum_size = Vector2(140, 44)
	ph.add_child(le)
	ph.add_child(UIKit.button("Set", func() -> void:
		var t: String = le.text.strip_edges().to_upper()
		if t.length() > 0:
			Game.buy_custom(vid, "plate", t), 46, 70))
	content.add_child(pp)

func _cycle(key: String, d: int, n: int) -> void:
	var rec: Dictionary = Game.owned[vid]
	var cur: int = int(rec["custom"].get(key, 0))
	var nxt: int = posmod(cur + d, n)
	var cost: int = int(Data.CUSTOM_COST[key])
	if Game.money < cost:
		Game.notify.emit("Not enough money", "warn")
		return
	Game.buy_custom(vid, key, nxt)

# ------------------------------------------------------------ repair
func _tab_repair() -> void:
	var rec: Dictionary = Game.owned[vid]
	var dmg: float = float(rec["damage"])
	var cost: int = Game.repair_cost(vid)
	content.add_child(UIKit.label("Condition %d%%" % int((1.0 - dmg) * 100.0), 26))
	content.add_child(UIKit.bar((1.0 - dmg) * 100.0, UIKit.GREEN, 400.0, 16.0))
	var b: Button = UIKit.accent_button("Repair  " + Game.fmt_money(cost) if cost > 0 else "No repairs needed", _do_repair, 56)
	b.disabled = cost <= 0 or Game.money < cost
	content.add_child(b)
	var fuel: float = float(rec["fuel"])
	content.add_child(UIKit.spacer(10))
	content.add_child(UIKit.label("Fuel %d%%" % int(fuel * 100.0), 26))
	var fc: int = int(ceil((1.0 - fuel) * 90.0))
	var fb: Button = UIKit.button("Fill tank  " + Game.fmt_money(fc) if fc > 0 else "Tank is full", _do_fill, 52)
	fb.disabled = fc <= 0 or Game.money < fc
	content.add_child(fb)

func _do_repair() -> void:
	if Game.repair(vid):
		world.audio.play_ui("pickup")
		Game.notify.emit("Repaired", "info")

func _do_fill() -> void:
	var fc: int = int(ceil((1.0 - float(Game.owned[vid]["fuel"])) * 90.0))
	if Game.spend(fc):
		Game.owned[vid]["fuel"] = 1.0
		Game.garage_changed.emit()

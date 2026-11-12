class_name DealershipUI
extends Control
## Marcus Motors: browse every vehicle in a 3D showroom, check real stats, buy.

signal closed

var world: World
var showroom: Showroom
var sel: String = "bmw_m6"
var list_box: VBoxContainer
var info_box: VBoxContainer
var money_lbl: Label
var colour: int = -1
var confirming: bool = false
var msg: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	showroom = Showroom.new()
	add_child(showroom)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 18)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)
	var left := PanelContainer.new()
	left.custom_minimum_size = Vector2(430, 0)
	row.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)
	lv.add_child(UIKit.title_bar("MARCUS MOTORS", "Dealership"))
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sc: ScrollContainer = UIKit.scroll(list_box, Vector2(400, 300))
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(sc)
	lv.add_child(UIKit.accent_button("Leave", func() -> void: closed.emit(), 56))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)
	var rv := VBoxContainer.new()
	rv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(rv)
	money_lbl = UIKit.label("", 34, UIKit.GREEN, 2)
	rv.add_child(money_lbl)
	var ip := PanelContainer.new()
	ip.custom_minimum_size = Vector2(380, 0)
	rv.add_child(ip)
	info_box = VBoxContainer.new()
	ip.add_child(info_box)
	Game.money_changed.connect(func(_m: int) -> void: _refresh())
	Game.garage_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	money_lbl.text = "%s    REP %d" % [Game.fmt_money(Game.money), Game.rep]
	UIKit.clear(list_box)
	for id in Data.shop_ids():
		var spec: Dictionary = Data.vehicle(id)
		var owned: bool = Game.owned.has(id)
		var req: int = Game.rep_required(id)
		var txt: String = "%s   %s" % [spec["name"], "OWNED" if owned else Game.fmt_money(int(spec["price"]))]
		if not owned and Game.rep < req:
			txt += "   (REP %d)" % req
		var b: Button = UIKit.button(txt, _select.bind(id), 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == sel:
			b.add_theme_stylebox_override("normal", UIKit.box(UIKit.RED_DARK, 8, UIKit.RED, 2, 14))
		list_box.add_child(b)
	var spec2: Dictionary = Data.vehicle(sel)
	var custom: Dictionary = Game.owned[sel]["custom"] if Game.owned.has(sel) else Data.default_custom(sel)
	if colour >= 0:
		custom = custom.duplicate(true)
		custom["paint"] = colour
	if showroom.cur_vid != sel or colour >= 0 or true:
		showroom.show_car(sel, custom, Game.owned[sel]["upg"] if Game.owned.has(sel) else {})
	UIKit.clear(info_box)
	info_box.add_child(UIKit.label(String(spec2["name"]), 32))
	info_box.add_child(UIKit.label("%s  |  %s  |  %s" % [spec2["cat"], spec2["drive"], String(spec2["engine"]).to_upper()], 18, UIKit.MUTED))
	var r: Dictionary = Data.rating(sel, Game.owned[sel]["upg"] if Game.owned.has(sel) else Data.default_upgrades())
	for k in [["speed", "Top Speed"], ["accel", "Acceleration"], ["handling", "Handling"], ["braking", "Braking"]]:
		var h := HBoxContainer.new()
		var l: Label = UIKit.label(k[1], 18, UIKit.MUTED)
		l.custom_minimum_size = Vector2(130, 0)
		h.add_child(l)
		h.add_child(UIKit.bar(float(r[k[0]]), UIKit.RED, 190.0))
		info_box.add_child(h)
	info_box.add_child(UIKit.label("%d %s   |   %d kg   |   %s" % [int(Game.speed_to_display(float(spec2["top"]))), Game.unit_label(), int(spec2["mass"]), "Off-road capable" if bool(spec2.get("offroad", false)) else "Road tyres"], 16, UIKit.MUTED))
	info_box.add_child(UIKit.label("Fuel tank  %d L   |   %s" % [int(Data.tank_litres(sel)), "OWNED" if Game.owned.has(sel) else "AVAILABLE"], 16, UIKit.GREEN if Game.owned.has(sel) else UIKit.MUTED))
	info_box.add_child(UIKit.spacer(4))
	info_box.add_child(UIKit.label("Preview colour", 16, UIKit.MUTED))
	var cr := HBoxContainer.new()
	for i in range(0, Data.PAINTS.size(), 2):
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(34, 34)
		cb.add_theme_stylebox_override("normal", UIKit.box(Data.PAINTS[i]["c"], 17, Color(1, 1, 1, 0.3), 1, 0))
		cb.add_theme_stylebox_override("hover", UIKit.box(Data.PAINTS[i]["c"], 17, Color.WHITE, 2, 0))
		cb.add_theme_stylebox_override("pressed", UIKit.box(Data.PAINTS[i]["c"], 17, Color.WHITE, 2, 0))
		cb.pressed.connect(func() -> void:
			colour = i
			_refresh())
		cr.add_child(cb)
	info_box.add_child(cr)
	info_box.add_child(UIKit.spacer(6))
	if Game.owned.has(sel):
		var b2: Button = UIKit.button("Already owned", Callable(), 54)
		b2.disabled = true
		info_box.add_child(b2)
	else:
		var price: int = int(spec2["price"])
		var req2: int = Game.rep_required(sel)
		if confirming:
			info_box.add_child(UIKit.label("Buy %s for %s?" % [spec2["name"], Game.fmt_money(price)], 20, UIKit.GREEN))
			info_box.add_child(UIKit.accent_button("Confirm purchase", _buy, 58))
			info_box.add_child(UIKit.button("Cancel", func() -> void:
				confirming = false
				_refresh(), 50))
		else:
			var b3: Button = UIKit.accent_button("Buy  " + Game.fmt_money(price), _ask_buy, 58)
			if Game.rep < req2:
				b3.text = "Locked - needs %d REP" % req2
				b3.disabled = true
			elif Game.slots_used() >= Game.garage_slots:
				b3.text = "Garage full (%d/%d)" % [Game.slots_used(), Game.garage_slots]
				b3.disabled = true
			info_box.add_child(b3)
	if msg != "":
		info_box.add_child(UIKit.label(msg, 16, Color(1.0, 0.6, 0.25)))
	info_box.add_child(UIKit.label("Stock paint is applied; customise in the garage.", 14, UIKit.MUTED))

func _select(id: String) -> void:
	sel = id
	confirming = false
	msg = ""
	colour = -1
	world.audio.play_ui("click")
	_refresh()

func _ask_buy() -> void:
	var price: int = int(Data.vehicle(sel)["price"])
	if Game.owned.has(sel):
		return
	if Game.money < price:
		msg = "Not enough money - you need %s more." % Game.fmt_money(price - Game.money)
		world.audio.play_ui("click")
	else:
		msg = ""
		confirming = true
	_refresh()

func _buy() -> void:
	confirming = false
	if Game.owned.has(sel):
		return
	if Game.buy_vehicle(sel):
		msg = "Purchased! Find it in your garage."
		if colour >= 0:
			Game.owned[sel]["custom"]["paint"] = colour
		world.audio.play_ui("win")
	else:
		msg = "Purchase failed."
	_refresh()

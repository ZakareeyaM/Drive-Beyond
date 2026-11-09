class_name RepairUI
extends Control
## Repair bay: shows the vehicle's condition and the fee; paying restores it to 100% (damage, dents, lamps, wreck state).

signal closed

var world: World
var car: Vehicle
var lbl_cond: Label
var bar_cond: ProgressBar
var lbl_fee: Label
var lbl_money: Label
var lbl_msg: Label
var btn: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	car = world.player_car
	var cp: Array = Menus._center_panel(560.0)
	add_child(cp[0])
	var v: VBoxContainer = cp[1]
	v.add_theme_constant_override("separation", 8)
	v.add_child(UIKit.title_bar("REPAIR BAY", String(Data.vehicle(car.vid)["name"])))
	lbl_cond = UIKit.label("", 26)
	v.add_child(lbl_cond)
	bar_cond = UIKit.bar(0.0, UIKit.GREEN, 520.0, 22.0)
	v.add_child(bar_cond)
	lbl_fee = UIKit.label("", 30, UIKit.GREEN)
	v.add_child(lbl_fee)
	lbl_money = UIKit.label("", 20, UIKit.MUTED)
	v.add_child(lbl_money)
	lbl_msg = UIKit.label("", 20, Color(1.0, 0.6, 0.3))
	v.add_child(lbl_msg)
	btn = UIKit.accent_button("", _repair, 70)
	v.add_child(btn)
	v.add_child(UIKit.button("Close", func() -> void: closed.emit(), 62))
	_refresh()

func _condition() -> float:
	return clampf(1.0 - car.damage, 0.0, 1.0)

func _refresh() -> void:
	var fee: int = world.repair_fee()
	lbl_cond.text = "Condition  %d%%" % int(round(_condition() * 100.0))
	bar_cond.value = _condition() * 100.0
	var col: Color = Color(1, 0.15, 0.1).lerp(UIKit.GREEN, _condition())
	bar_cond.add_theme_stylebox_override("fill", UIKit.box(col, 4, Color(0, 0, 0, 0), 0, 0))
	lbl_fee.text = "Repair fee:  %s" % Game.fmt_money(fee) if fee > 0 else "No repairs needed"
	lbl_money.text = "Your money:  %s" % Game.fmt_money(Game.money)
	btn.text = "REPAIR  %s" % Game.fmt_money(fee) if fee > 0 else "Vehicle in perfect condition"
	btn.disabled = fee <= 0

func _repair() -> void:
	var fee: int = world.repair_fee()
	if fee <= 0:
		return
	if Game.money < fee:
		lbl_msg.text = "Not enough money - need %s more" % Game.fmt_money(fee - Game.money)
		world.audio.play_ui("click")
		return
	Game.add_money(-fee, "Repair")
	car.repair_full()
	if Game.owned.has(car.vid):
		Game.owned[car.vid]["damage"] = 0.0
	world._sync_state()
	Game.save_game()
	world.audio.play_ui("win")
	lbl_msg.text = "Repaired - good as new"
	lbl_msg.add_theme_color_override("font_color", UIKit.GREEN)
	_refresh()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		closed.emit()

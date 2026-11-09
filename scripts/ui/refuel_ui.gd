class_name RefuelUI
extends Control
## Pump screen: shows tank level, litres added and cost; START / STOP fills the tank of the car you drove in,
## charging per litre. Uses the normal vehicle fuel value (0..1 of Data.tank_litres), so HUD, saves and fuel
## burn all see the result immediately.

signal closed

const RATE_LPS := 7.0     # litres per second while the nozzle is on

var world: World
var car: Vehicle
var tank: float = 50.0
var start_fuel: float = 0.0     # fuel fraction when the current session began
var added: float = 0.0          # litres added this session (not yet paid)
var filling: bool = false
var bar_fuel: ProgressBar
var lbl_level: Label
var lbl_added: Label
var lbl_cost: Label
var lbl_money: Label
var lbl_msg: Label
var btn_go: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	car = world.player_car
	tank = Data.tank_litres(car.vid)
	start_fuel = car.fuel
	var cp: Array = Menus._center_panel(560.0)
	add_child(cp[0])
	var v: VBoxContainer = cp[1]
	v.add_theme_constant_override("separation", 8)
	v.add_child(UIKit.title_bar("FUEL PUMP", "%s   |   %.0f L tank   |   $%.2f per litre" % [Data.vehicle(car.vid)["name"], tank, World.FUEL_PRICE]))
	lbl_level = UIKit.label("", 26)
	v.add_child(lbl_level)
	bar_fuel = UIKit.bar(0.0, UIKit.GOLD, 520.0, 22.0)
	v.add_child(bar_fuel)
	lbl_added = UIKit.label("", 24, UIKit.MUTED)
	v.add_child(lbl_added)
	lbl_cost = UIKit.label("", 30, UIKit.GREEN)
	v.add_child(lbl_cost)
	lbl_money = UIKit.label("", 20, UIKit.MUTED)
	v.add_child(lbl_money)
	lbl_msg = UIKit.label("", 20, Color(1.0, 0.6, 0.3))
	v.add_child(lbl_msg)
	btn_go = UIKit.accent_button("START FUELLING", _toggle, 70)
	v.add_child(btn_go)
	v.add_child(UIKit.button("Done", _finish, 62))
	_refresh()

func _cost() -> int:
	return int(ceil(added * World.FUEL_PRICE - 0.0001))

func _toggle() -> void:
	if filling:
		_stop()
		return
	if car.fuel >= 0.999:
		lbl_msg.text = "Tank is already full"
		return
	if Game.money - _cost() < int(ceil(World.FUEL_PRICE)):
		lbl_msg.text = "Not enough money for fuel"
		return
	filling = true
	lbl_msg.text = ""
	world.audio.play_ui("click")
	_refresh()

func _stop() -> void:
	filling = false
	_settle()
	_refresh()

## pay for what was pumped so far and start a fresh session
func _settle() -> void:
	var c: int = mini(_cost(), Game.money)
	if c > 0:
		Game.add_money(-c, "Fuel")
	added = 0.0
	start_fuel = car.fuel
	world._sync_state()
	Game.save_game()

func _process(dt: float) -> void:
	if not filling:
		return
	var room: float = tank * (1.0 - car.fuel)
	var afford: float = (float(Game.money) - float(_cost() - 0)) / World.FUEL_PRICE
	var step: float = minf(RATE_LPS * dt, room)
	if afford < step:
		step = maxf(afford, 0.0)
		lbl_msg.text = "Not enough money for more fuel"
		filling = false
	added += step
	car.fuel = clampf(car.fuel + step / tank, 0.0, 1.0)
	if car.fuel >= 0.999:
		car.fuel = 1.0
		filling = false
		lbl_msg.text = "Tank full"
	if not filling:
		_settle()
	_refresh()

func _refresh() -> void:
	lbl_level.text = "Fuel  %.1f / %.0f L   (%d%%)" % [car.fuel * tank, tank, int(round(car.fuel * 100.0))]
	bar_fuel.value = car.fuel * 100.0
	lbl_added.text = "Added this fill:  %.1f L" % added
	lbl_cost.text = "Cost:  %s" % Game.fmt_money(_cost())
	lbl_money.text = "Your money:  %s" % Game.fmt_money(Game.money)
	btn_go.text = "STOP" if filling else "START FUELLING"

func _finish() -> void:
	if filling:
		filling = false
	_settle()
	closed.emit()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel") or e.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		_finish()

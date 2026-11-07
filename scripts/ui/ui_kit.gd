class_name UIKit
extends RefCounted
## Shared look for every screen: dark panels, red accents, big touch targets.

const RED := Color(0.92, 0.1, 0.14)
const RED_DARK := Color(0.55, 0.04, 0.08)
const BG := Color(0.04, 0.04, 0.06, 0.94)
const PANEL := Color(0.08, 0.08, 0.11, 0.92)
const PANEL_LIGHT := Color(0.13, 0.13, 0.17, 0.95)
const TEXT := Color(0.94, 0.94, 0.96)
const MUTED := Color(0.62, 0.64, 0.7)
const GOLD := Color(1.0, 0.8, 0.2)
const GREEN := Color(0.25, 0.9, 0.45)

static func box(col: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), bw: int = 0, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	t.set_stylebox("normal", "Button", box(PANEL_LIGHT, 8, Color(1, 1, 1, 0.08), 1, 14))
	t.set_stylebox("hover", "Button", box(Color(0.2, 0.2, 0.26, 0.98), 8, RED, 2, 14))
	t.set_stylebox("pressed", "Button", box(RED_DARK, 8, RED, 2, 14))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 8, RED, 2, 14))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.12, 0.7), 8, Color(1, 1, 1, 0.04), 1, 14))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.4, 0.45))
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 12, Color(1, 1, 1, 0.07), 1, 14))
	t.set_stylebox("panel", "Panel", box(PANEL, 12, Color(1, 1, 1, 0.07), 1, 14))
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.03, 0.05), 6, Color(1, 1, 1, 0.15), 1, 10))
	t.set_stylebox("slider", "HSlider", box(Color(0.2, 0.2, 0.26), 4, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area", "HSlider", box(RED, 4, Color(0, 0, 0, 0), 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(RED, 4, Color(0, 0, 0, 0), 0, 2))
	t.set_constant("h_separation", "HBoxContainer", 10)
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_stylebox("panel", "TooltipPanel", box(PANEL, 6))
	return t

static func label(text: String, size: int = 22, col: Color = TEXT, align: int = 0) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align as HorizontalAlignment
	return l

static func button(text: String, cb: Callable, min_h: float = 54.0, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.pressed.connect(cb)
	b.focus_mode = Control.FOCUS_NONE
	return b

static func accent_button(text: String, cb: Callable, min_h: float = 58.0, min_w: float = 0.0) -> Button:
	var b: Button = button(text, cb, min_h, min_w)
	b.add_theme_stylebox_override("normal", box(RED_DARK, 8, RED, 2, 16))
	b.add_theme_stylebox_override("hover", box(RED, 8, Color.WHITE, 2, 16))
	b.add_theme_stylebox_override("pressed", box(Color(0.7, 0.05, 0.1), 8, Color.WHITE, 2, 16))
	return b

static func bar(value: float, col: Color = RED, w: float = 220.0, h: float = 12.0) -> ProgressBar:
	var p := ProgressBar.new()
	p.min_value = 0.0
	p.max_value = 100.0
	p.value = value
	p.show_percentage = false
	p.custom_minimum_size = Vector2(w, h)
	p.add_theme_stylebox_override("background", box(Color(0.15, 0.15, 0.2), 4, Color(0, 0, 0, 0), 0, 0))
	p.add_theme_stylebox_override("fill", box(col, 4, Color(0, 0, 0, 0), 0, 0))
	return p

static func title_bar(text: String, sub: String = "") -> VBoxContainer:
	var v := VBoxContainer.new()
	var l: Label = label(text, 40, TEXT)
	l.add_theme_color_override("font_outline_color", RED)
	l.add_theme_constant_override("outline_size", 0)
	v.add_child(l)
	if sub != "":
		v.add_child(label(sub, 18, MUTED))
	var line := ColorRect.new()
	line.color = RED
	line.custom_minimum_size = Vector2(120, 3)
	v.add_child(line)
	return v

static func spacer(h: float = 8.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func scroll(content: Control, min_size: Vector2) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.custom_minimum_size = min_size
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(content)
	return s

static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()

static func fmt_time(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]

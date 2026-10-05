extends Control
## Gamepad-style fire cluster: large FIRE + turret L/R hold buttons.
## Reload progress shown as a ring on the fire button.

signal fire_changed(down: bool)
signal turret_left_changed(down: bool)
signal turret_right_changed(down: bool)

const FIRE_R := 42.0
const SIDE_R := 28.0

var fire_down := false
var tleft_down := false
var tright_down := false
var fire_hover := false
var tleft_hover := false
var tright_hover := false
var reload_ratio := 1.0  ## 1 = ready, 0 = just fired
var turret_bearing := 0.0  ## radians, absolute
var show_aim_arc := true

var _navy := Color(0.10, 0.16, 0.22, 0.78)
var _steel := Color(0.28, 0.34, 0.40, 0.9)
var _brass := Color(0.82, 0.66, 0.30, 0.95)
var _cyan := Color(0.30, 0.90, 0.98, 1.0)
var _hot := Color(0.85, 0.38, 0.22, 0.95)
var _hot_glow := Color(1.0, 0.55, 0.25, 0.55)
var _col_ready := Color(0.95, 0.78, 0.35, 0.98)


func _ready() -> void:
	custom_minimum_size = Vector2(200, 130)
	mouse_filter = Control.MOUSE_FILTER_STOP


func _zone(which: String) -> Rect2:
	var c := Vector2(size.x * 0.5, size.y * 0.58)
	match which:
		"fire":
			return Rect2(c - Vector2(FIRE_R, FIRE_R), Vector2(FIRE_R * 2, FIRE_R * 2))
		"tleft":
			var p := c + Vector2(-FIRE_R - SIDE_R - 8.0, -6.0)
			return Rect2(p - Vector2(SIDE_R, SIDE_R), Vector2(SIDE_R * 2, SIDE_R * 2))
		"tright":
			var p2 := c + Vector2(FIRE_R + SIDE_R + 8.0, -6.0)
			return Rect2(p2 - Vector2(SIDE_R, SIDE_R), Vector2(SIDE_R * 2, SIDE_R * 2))
	return Rect2()


func _hit(local: Vector2) -> String:
	for z in ["fire", "tleft", "tright"]:
		var r := _zone(z)
		var center := r.get_center()
		var rad := r.size.x * 0.5
		if local.distance_to(center) <= rad + 2.0:
			return z
	return ""


func _set_zone(which: String, down: bool) -> void:
	match which:
		"fire":
			if fire_down != down:
				fire_down = down
				fire_changed.emit(down)
		"tleft":
			if tleft_down != down:
				tleft_down = down
				turret_left_changed.emit(down)
		"tright":
			if tright_down != down:
				tright_down = down
				turret_right_changed.emit(down)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var z := _hit(mb.position)
			if mb.pressed:
				if z != "":
					_set_zone(z, true)
					accept_event()
			else:
				_set_zone("fire", false)
				_set_zone("tleft", false)
				_set_zone("tright", false)
				accept_event()
	elif event is InputEventMouseMotion:
		var mz := _hit((event as InputEventMouseMotion).position)
		var nh := mz == "fire"
		var nl := mz == "tleft"
		var nr := mz == "tright"
		if nh != fire_hover or nl != tleft_hover or nr != tright_hover:
			fire_hover = nh
			tleft_hover = nl
			tright_hover = nr
			queue_redraw()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		var z2 := _hit(st.position)
		if st.pressed and z2 != "":
			_set_zone(z2, true)
			accept_event()
		elif not st.pressed:
			_set_zone("fire", false)
			_set_zone("tleft", false)
			_set_zone("tright", false)
			accept_event()


func set_reload(ratio: float) -> void:
	reload_ratio = clampf(ratio, 0.0, 1.0)
	queue_redraw()


func set_turret_bearing(rad: float) -> void:
	turret_bearing = rad
	queue_redraw()


func set_keyboard_visual(fire: bool, tleft: bool, tright: bool) -> void:
	# Visual-only highlight when keyboard is used (holds already set by battle)
	if fire != fire_down or tleft != tleft_down or tright != tright_down:
		# Don't overwrite actual holds from pad; just force redraw for kbd overlay
		pass
	queue_redraw()


var kbd_fire := false
var kbd_tleft := false
var kbd_tright := false


func sync_keyboard(fire: bool, tleft: bool, tright: bool) -> void:
	kbd_fire = fire
	kbd_tleft = tleft
	kbd_tright = tright
	queue_redraw()


func _draw() -> void:
	var c := Vector2(size.x * 0.5, size.y * 0.58)
	# Optional aim dial above fire button
	if show_aim_arc:
		_draw_aim_dial(Vector2(c.x, 28.0))
	_draw_side_btn(c + Vector2(-FIRE_R - SIDE_R - 8.0, -6.0), true, tleft_down or kbd_tleft, tleft_hover)
	_draw_side_btn(c + Vector2(FIRE_R + SIDE_R + 8.0, -6.0), false, tright_down or kbd_tright, tright_hover)
	_draw_fire_btn(c, fire_down or kbd_fire, fire_hover)


func _draw_aim_dial(at: Vector2) -> void:
	var r := 22.0
	draw_circle(at, r + 2.0, Color(0.06, 0.1, 0.14, 0.55))
	draw_arc(at, r, 0.0, TAU, 40, _brass, 1.6, true)
	# Ship outline (bow up on dial = absolute? Use relative bearing needle)
	var ship := PackedVector2Array([
		at + Vector2(0, -10),
		at + Vector2(5, 8),
		at + Vector2(0, 5),
		at + Vector2(-5, 8),
	])
	draw_colored_polygon(ship, Color(0.7, 0.78, 0.82, 0.7))
	# Turret needle (absolute bearing: 0 = +X world = east; map to screen: 0 rad = right)
	var ang := -PI * 0.5 + turret_bearing
	var tip := at + Vector2(cos(ang), sin(ang)) * (r - 4.0)
	draw_line(at, tip, _cyan, 2.2)
	draw_circle(tip, 2.5, _cyan)


func _draw_side_btn(at: Vector2, is_left: bool, pressed: bool, hover: bool) -> void:
	var col := _navy
	if hover:
		col = col.lightened(0.1)
	if pressed:
		col = Color(0.18, 0.42, 0.48, 0.95)
	draw_circle(at, SIDE_R + 2.0, Color(0, 0, 0, 0.3))
	draw_circle(at, SIDE_R, col)
	draw_arc(at, SIDE_R - 1.0, 0.0, TAU, 28, _brass if pressed else _steel, 2.0, true)
	# Curved arrow
	var start := PI * 0.75 if is_left else PI * 0.25
	var end := PI * 1.75 if is_left else PI * -0.25
	var arc_col := _cyan if pressed else Color(0.75, 0.82, 0.86, 0.9)
	draw_arc(at, 12.0, start, end, 16, arc_col, 2.4, true)
	# Arrow head
	var head_ang := end
	var hp := at + Vector2(cos(head_ang), sin(head_ang)) * 12.0
	var tang := head_ang + (PI * 0.5 if is_left else -PI * 0.5)
	var nrm := Vector2(cos(head_ang), sin(head_ang))
	var pts := PackedVector2Array([
		hp + nrm * 3.0,
		hp - nrm * 2.0 + Vector2(cos(tang), sin(tang)) * 5.0,
		hp - nrm * 2.0 - Vector2(cos(tang), sin(tang)) * 5.0,
	])
	draw_colored_polygon(pts, arc_col)


func _draw_fire_btn(at: Vector2, pressed: bool, hover: bool) -> void:
	var is_ready := reload_ratio >= 0.999
	if pressed or hover:
		draw_circle(at, FIRE_R + 8.0, _hot_glow)
	draw_circle(at, FIRE_R + 3.0, Color(0, 0, 0, 0.35))
	var fill := _hot if pressed else (_navy.lightened(0.05) if hover else _navy)
	if is_ready and not pressed:
		fill = Color(0.16, 0.22, 0.28, 0.88)
	draw_circle(at, FIRE_R, fill)
	# Reload ring
	var ring_col := _col_ready if is_ready else Color(0.45, 0.55, 0.6, 0.7)
	if is_ready:
		draw_arc(at, FIRE_R - 3.0, 0.0, TAU, 48, ring_col, 3.5, true)
	else:
		# Sweep from top
		var a0 := -PI * 0.5
		var a1 := a0 + TAU * reload_ratio
		draw_arc(at, FIRE_R - 3.0, a0, a1, 48, _cyan, 3.5, true)
		draw_arc(at, FIRE_R - 3.0, a1, a0 + TAU, 48, Color(0.25, 0.3, 0.35, 0.5), 2.0, true)
	draw_arc(at, FIRE_R - 1.0, 0.0, TAU, 40, _brass, 2.0, true)
	# Crosshair / shell icon
	var ic := _cyan if is_ready else Color(0.6, 0.65, 0.68, 0.8)
	if pressed:
		ic = Color(1.0, 0.92, 0.7)
	draw_arc(at, 14.0, 0.0, TAU, 24, ic, 2.0, true)
	draw_line(at + Vector2(0, -20), at + Vector2(0, -10), ic, 2.2)
	draw_line(at + Vector2(0, 10), at + Vector2(0, 20), ic, 2.2)
	draw_line(at + Vector2(-20, 0), at + Vector2(-10, 0), ic, 2.2)
	draw_line(at + Vector2(10, 0), at + Vector2(20, 0), ic, 2.2)
	# Shell tip in centre
	var shell := PackedVector2Array([
		at + Vector2(0, -8),
		at + Vector2(4, 2),
		at + Vector2(4, 8),
		at + Vector2(-4, 8),
		at + Vector2(-4, 2),
	])
	draw_colored_polygon(shell, ic)

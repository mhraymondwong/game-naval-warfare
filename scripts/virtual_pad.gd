extends Control
## Virtual helm pad — ship-style engine telegraph + rudder.
## Throttle (Y) is persistent when the knob is released (telegraph order).
## Rudder (X) snaps back to centre on release.
## Icons/chevrons only — no Chinese text on the control.

signal throttle_changed(value: float)
signal rudder_changed(value: float)

const BASE_R := 78.0
const KNOB_R := 26.0
const DEAD := 0.10

var throttle := 0.0  ## -1..1 persistent order
var rudder := 0.0    ## -1..1 momentary
var dragging := false
var hovered := false
var press_id := -1
## Visual overlay from keyboard (does not write throttle unless caller does)
var kbd_thrust := 0.0
var kbd_rudder := 0.0

var _col_base := Color(0.08, 0.14, 0.20, 0.72)
var _col_ring := Color(0.55, 0.62, 0.58, 0.85)
var _col_brass := Color(0.78, 0.64, 0.32, 0.95)
var _col_cyan := Color(0.35, 0.88, 0.95, 0.95)
var _col_knob := Color(0.22, 0.32, 0.40, 0.92)
var _col_knob_hot := Color(0.28, 0.48, 0.58, 0.98)


func _ready() -> void:
	custom_minimum_size = Vector2(BASE_R * 2.0 + 16.0, BASE_R * 2.0 + 16.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): hovered = true; queue_redraw())
	mouse_exited.connect(func(): hovered = false; queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				dragging = true
				press_id = 0
				_apply_from_local(mb.position)
				accept_event()
			elif dragging:
				dragging = false
				press_id = -1
				rudder = 0.0
				rudder_changed.emit(0.0)
				queue_redraw()
				accept_event()
	elif event is InputEventMouseMotion and dragging:
		_apply_from_local((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			dragging = true
			press_id = st.index
			_apply_from_local(st.position)
			accept_event()
		elif st.index == press_id:
			dragging = false
			press_id = -1
			rudder = 0.0
			rudder_changed.emit(0.0)
			queue_redraw()
			accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == press_id and dragging:
			_apply_from_local(sd.position)
			accept_event()


func _apply_from_local(local: Vector2) -> void:
	var c := size * 0.5
	var d := local - c
	var max_r := BASE_R - KNOB_R * 0.35
	if d.length() > max_r:
		d = d.normalized() * max_r
	var nx := clampf(d.x / max_r, -1.0, 1.0)
	var ny := clampf(-d.y / max_r, -1.0, 1.0)  # up = ahead
	if absf(nx) < DEAD:
		nx = 0.0
	if absf(ny) < DEAD:
		ny = 0.0
	var th_changed := not is_equal_approx(throttle, ny)
	var rd_changed := not is_equal_approx(rudder, nx)
	throttle = ny
	rudder = nx
	if th_changed:
		throttle_changed.emit(throttle)
	if rd_changed:
		rudder_changed.emit(rudder)
	queue_redraw()


func set_keyboard_visual(thrust: float, rudder_v: float) -> void:
	kbd_thrust = thrust
	kbd_rudder = rudder_v
	queue_redraw()


func set_throttle_order(v: float) -> void:
	throttle = clampf(v, -1.0, 1.0)
	queue_redraw()


func _knob_offset() -> Vector2:
	var max_r := BASE_R - KNOB_R * 0.35
	var th := throttle
	var rd := rudder
	if not dragging:
		# Keyboard rudder is momentary; keyboard thrust shows on knob if stronger
		if absf(kbd_rudder) > 0.01:
			rd = kbd_rudder
		if absf(kbd_thrust) > 0.01:
			th = kbd_thrust
		elif absf(throttle) > 0.01:
			th = throttle
	return Vector2(rd * max_r, -th * max_r)


func _draw() -> void:
	var c := size * 0.5
	# Soft outer glow
	draw_circle(c, BASE_R + 6.0, Color(0.05, 0.1, 0.14, 0.35))
	# Base disc
	var base := _col_base
	if hovered or dragging:
		base = base.lightened(0.08)
	draw_circle(c, BASE_R, base)
	# Brass outer ring
	draw_arc(c, BASE_R - 1.5, 0.0, TAU, 64, _col_brass, 2.5, true)
	# Inner steel ring
	draw_arc(c, BASE_R - 10.0, 0.0, TAU, 48, _col_ring, 1.5, true)
	# Crosshair guide
	var guide := Color(0.45, 0.55, 0.58, 0.35)
	draw_line(c + Vector2(0, -BASE_R + 14), c + Vector2(0, BASE_R - 14), guide, 1.2)
	draw_line(c + Vector2(-BASE_R + 14, 0), c + Vector2(BASE_R - 14, 0), guide, 1.2)
	# Throttle track (vertical brass)
	draw_line(c + Vector2(0, -BASE_R + 18), c + Vector2(0, BASE_R - 18), Color(0.7, 0.58, 0.28, 0.4), 3.0)
	# Chevrons: ahead / astern / port / starboard
	_draw_chevron(c + Vector2(0, -BASE_R + 22), 0.0, _col_cyan if throttle > 0.2 or kbd_thrust > 0.2 else _col_ring)
	_draw_chevron(c + Vector2(0, BASE_R - 22), PI, _col_cyan if throttle < -0.2 or kbd_thrust < -0.2 else _col_ring)
	_draw_chevron(c + Vector2(-BASE_R + 22, 0), -PI * 0.5, _col_cyan if rudder < -0.2 or kbd_rudder < -0.2 else _col_ring)
	_draw_chevron(c + Vector2(BASE_R - 22, 0), PI * 0.5, _col_cyan if rudder > 0.2 or kbd_rudder > 0.2 else _col_ring)
	# Deadzone circle
	draw_arc(c, BASE_R * DEAD * 2.2, 0.0, TAU, 24, Color(0.5, 0.55, 0.5, 0.25), 1.0, true)
	# Knob
	var kp := c + _knob_offset()
	var kcol := _col_knob_hot if dragging or absf(throttle) > 0.05 or absf(kbd_thrust) > 0.05 else _col_knob
	draw_circle(kp, KNOB_R + 3.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(kp, KNOB_R, kcol)
	draw_arc(kp, KNOB_R - 1.0, 0.0, TAU, 32, _col_brass, 2.0, true)
	draw_circle(kp, 6.0, _col_cyan if dragging else Color(0.7, 0.78, 0.82, 0.8))


func _draw_chevron(at: Vector2, rot: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var a := Vector2(0, -9).rotated(rot)
	var b := Vector2(-7, 5).rotated(rot)
	var d := Vector2(7, 5).rotated(rot)
	pts.append(at + a)
	pts.append(at + b)
	pts.append(at + d)
	draw_colored_polygon(pts, col)

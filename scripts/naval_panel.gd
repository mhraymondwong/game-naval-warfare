extends Control
## Bridge HUD panel: smoked-glass plate with brass trim, drawn procedurally.
## Name plate + silhouette, enemy roster icons, segmented hull bar,
## speed gauge (with telegraph order pip) and turret bearing compass.

var font: Font
var ship_name := "戰艦·海風"
var hp := 3000
var max_hp := 3000
var knots := 0.0          ## signed: negative = astern
var max_knots := 30.0
var order := 0.0          ## telegraph order -1..1
var turret_rel := 0.0     ## turret bearing relative to bow, radians
var cruisers_left := 4
var destroyers_left := 6
var cruisers_total := 4
var destroyers_total := 6

const GLASS := Color(0.035, 0.075, 0.115, 0.80)
const GLASS_TOP := Color(0.10, 0.17, 0.23, 0.55)
const BRASS := Color(0.80, 0.65, 0.32, 0.95)
const BRASS_DIM := Color(0.56, 0.46, 0.24, 0.65)
const STEEL := Color(0.50, 0.58, 0.62, 0.85)
const CYAN := Color(0.40, 0.90, 0.98, 1.0)
const AMBER := Color(0.96, 0.70, 0.28, 1.0)
const CREAM := Color(0.96, 0.93, 0.84, 1.0)
const MUTED := Color(0.66, 0.75, 0.78, 0.92)
const ENEMY := Color(0.93, 0.42, 0.33, 1.0)
const DEAD := Color(0.30, 0.33, 0.35, 0.55)


func setup(p_font: Font) -> void:
	font = p_font
	queue_redraw()


func update_stats(p_hp: int, p_max: int, p_knots: float, p_turret_rel: float, p_ca: int, p_dd: int, p_order: float) -> void:
	hp = p_hp
	max_hp = p_max
	knots = p_knots
	turret_rel = p_turret_rel
	cruisers_left = p_ca
	destroyers_left = p_dd
	order = p_order
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	_draw_frame(w, h)
	var x0 := 16.0
	var inner := w - 32.0
	var y := 16.0

	# Name plate
	_draw_nameplate(Rect2(x0 - 2, y, inner + 4, 40))
	y += 52.0

	# Enemy roster
	_section(Vector2(x0, y), "敵情", inner)
	_text_right("%d" % (cruisers_left + destroyers_left), Vector2(x0 + inner, y - 3), 17, ENEMY)
	y += 22.0
	for i in cruisers_total:
		_ship_icon(Vector2(x0 + 12 + i * 26, y + 7), 1.0, i < cruisers_left)
	_text_right("巡洋 %d" % cruisers_left, Vector2(x0 + inner, y - 1), 12, MUTED)
	y += 20.0
	for i in destroyers_total:
		_ship_icon(Vector2(x0 + 9 + i * 18, y + 7), 0.68, i < destroyers_left)
	_text_right("驅逐 %d" % destroyers_left, Vector2(x0 + inner, y - 1), 12, MUTED)
	y += 28.0

	# Hull integrity
	var ratio := clampf(float(hp) / float(maxi(max_hp, 1)), 0.0, 1.0)
	_section(Vector2(x0, y), "艦體", inner)
	_text_right("%d%%" % int(round(ratio * 100.0)), Vector2(x0 + inner, y - 3), 15, _hull_col(ratio))
	y += 22.0
	_segmented_bar(Rect2(x0, y, inner, 14), ratio)
	y += 20.0
	_text("%d / %d" % [hp, max_hp], Vector2(x0, y), 15, CREAM)
	y += 30.0

	# Gauges
	_section(Vector2(x0, y), "航速 · 砲向", inner)
	y += 22.0
	var r := inner * 0.25
	_speed_gauge(Vector2(x0 + inner * 0.25, y + r + 2), r)
	_turret_compass(Vector2(x0 + inner * 0.75, y + r + 2), r)
	y += r * 2.0 + 30.0

	# Compact key legend
	_section(Vector2(x0, y), "鍵盤", inner)
	y += 22.0
	var kx := x0
	kx = _keycap(Vector2(kx, y), "W") + 3
	kx = _keycap(Vector2(kx, y), "S") + 5
	_text("車鐘", Vector2(kx, y + 1), 12, MUTED)
	kx = x0 + inner * 0.52
	kx = _keycap(Vector2(kx, y), "A") + 3
	kx = _keycap(Vector2(kx, y), "D") + 5
	_text("舵", Vector2(kx, y + 1), 12, MUTED)
	y += 24.0
	kx = x0
	kx = _keycap(Vector2(kx, y), "Q") + 3
	kx = _keycap(Vector2(kx, y), "E") + 5
	_text("砲塔", Vector2(kx, y + 1), 12, MUTED)
	kx = x0 + inner * 0.52
	kx = _keycap(Vector2(kx, y), "SPACE") + 5
	_text("開火", Vector2(kx, y + 1), 12, MUTED)


func needed_height() -> float:
	return 16.0 + 52.0 + 22.0 + 20.0 + 28.0 + 22.0 + 20.0 + 30.0 + 22.0 + (size.x - 32.0) * 0.5 + 30.0 + 22.0 + 24.0 + 26.0


# ---------------------------------------------------------------- frame


func _draw_frame(w: float, h: float) -> void:
	var cut := 14.0
	var outer := PackedVector2Array([
		Vector2(cut, 0), Vector2(w, 0), Vector2(w, h - cut),
		Vector2(w - cut, h), Vector2(0, h), Vector2(0, cut),
	])
	draw_colored_polygon(outer, GLASS)
	# Top sheen
	var sheen := PackedVector2Array([
		Vector2(cut, 0), Vector2(w, 0), Vector2(w, 46), Vector2(0, 46), Vector2(0, cut),
	])
	draw_colored_polygon(sheen, GLASS_TOP)
	var loop := outer.duplicate()
	loop.append(outer[0])
	draw_polyline(loop, BRASS, 2.0, true)
	# Inner hairline
	var c2 := cut - 3.0
	var inner_pts := PackedVector2Array([
		Vector2(c2 + 4, 4), Vector2(w - 4, 4), Vector2(w - 4, h - c2 - 4),
		Vector2(w - c2 - 4, h - 4), Vector2(4, h - 4), Vector2(4, c2 + 4), Vector2(c2 + 4, 4),
	])
	draw_polyline(inner_pts, Color(BRASS_DIM, 0.35), 1.0, true)
	# Brass corner accents
	draw_line(Vector2(w - 26, 2), Vector2(w - 2, 2), BRASS, 3.0)
	draw_line(Vector2(w - 2, 2), Vector2(w - 2, 26), BRASS, 3.0)
	draw_line(Vector2(2, h - 26), Vector2(2, h - 2), BRASS, 3.0)
	draw_line(Vector2(2, h - 2), Vector2(26, h - 2), BRASS, 3.0)


func _section(at: Vector2, title: String, width: float) -> void:
	draw_rect(Rect2(at.x, at.y + 3, 3, 12), BRASS, true)
	_text(title, Vector2(at.x + 8, at.y), 13, MUTED)
	var tw := _measure(title, 13)
	draw_line(Vector2(at.x + 14 + tw, at.y + 10), Vector2(at.x + width - 30, at.y + 10), Color(BRASS_DIM, 0.45), 1.0)


func _draw_nameplate(r: Rect2) -> void:
	draw_rect(r, Color(0.02, 0.05, 0.08, 0.75), true)
	draw_rect(r, BRASS_DIM, false, 1.0)
	draw_rect(Rect2(r.position, Vector2(4, r.size.y)), BRASS, true)
	# Battleship silhouette (side view, bow right)
	var o := r.position + Vector2(12, r.size.y * 0.5 + 7)
	var hull := PackedVector2Array([
		o + Vector2(0, -4), o + Vector2(42, -4), o + Vector2(48, -8),
		o + Vector2(44, 2), o + Vector2(3, 2),
	])
	var col := Color(0.62, 0.80, 0.86, 0.95)
	draw_colored_polygon(hull, col)
	draw_rect(Rect2(o + Vector2(17, -11), Vector2(10, 7)), col, true)    # bridge
	draw_rect(Rect2(o + Vector2(20, -17), Vector2(3, 6)), col, true)     # mast
	draw_rect(Rect2(o + Vector2(11, -9), Vector2(4, 5)), col, true)      # funnel
	draw_rect(Rect2(o + Vector2(31, -7), Vector2(6, 3)), col, true)      # fwd turret
	draw_line(o + Vector2(36, -6), o + Vector2(44, -7), col, 1.2)
	draw_rect(Rect2(o + Vector2(4, -7), Vector2(6, 3)), col, true)       # aft turret
	draw_line(o + Vector2(4, -6), o + Vector2(-3, -7), col, 1.2)
	_text(ship_name, Vector2(r.position.x + 64, r.position.y + 7), 19, CREAM)


func _ship_icon(at: Vector2, sc: float, alive: bool) -> void:
	var col := ENEMY if alive else DEAD
	var L := 20.0 * sc
	var B := 7.0 * sc
	var pts := PackedVector2Array([
		at + Vector2(L * 0.5, 0), at + Vector2(L * 0.2, -B * 0.5),
		at + Vector2(-L * 0.42, -B * 0.42), at + Vector2(-L * 0.5, 0),
		at + Vector2(-L * 0.42, B * 0.42), at + Vector2(L * 0.2, B * 0.5),
	])
	draw_colored_polygon(pts, col)
	draw_rect(Rect2(at + Vector2(-L * 0.12, -B * 0.25), Vector2(L * 0.2, B * 0.5)), col.darkened(0.35), true)
	if not alive:
		draw_line(at + Vector2(-L * 0.4, -B * 0.6), at + Vector2(L * 0.4, B * 0.6), Color(0.6, 0.6, 0.6, 0.5), 1.0)


func _hull_col(ratio: float) -> Color:
	if ratio > 0.55:
		return Color(0.40, 0.86, 0.52)
	if ratio > 0.28:
		return Color(0.95, 0.74, 0.28)
	return Color(0.92, 0.32, 0.26)


func _segmented_bar(r: Rect2, ratio: float) -> void:
	var segs := 15
	var gap := 2.0
	var seg_w := (r.size.x - gap * float(segs - 1)) / float(segs)
	var filled := ratio * float(segs)
	draw_rect(r.grow(2.0), Color(0.01, 0.03, 0.05, 0.9), true)
	for i in segs:
		var rect := Rect2(r.position.x + float(i) * (seg_w + gap), r.position.y, seg_w, r.size.y)
		var t := float(i) / float(segs - 1)
		var col: Color
		if t < 0.28:
			col = Color(0.92, 0.32, 0.26)
		elif t < 0.55:
			col = Color(0.95, 0.74, 0.28)
		else:
			col = Color(0.40, 0.86, 0.52)
		# whole bar tints toward current state colour
		col = col.lerp(_hull_col(ratio), 0.5)
		if float(i) + 1.0 <= filled:
			draw_rect(rect, col, true)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), col.lightened(0.3), true)
		elif float(i) < filled:
			var part := filled - float(i)
			draw_rect(Rect2(rect.position, Vector2(rect.size.x * part, rect.size.y)), col, true)
			draw_rect(Rect2(rect.position + Vector2(rect.size.x * part, 0), Vector2(rect.size.x * (1.0 - part), rect.size.y)), Color(0.13, 0.17, 0.2, 0.8), true)
		else:
			draw_rect(rect, Color(0.13, 0.17, 0.2, 0.8), true)


func _gauge_face(at: Vector2, r: float) -> void:
	draw_circle(at, r + 4.0, Color(0.0, 0.0, 0.0, 0.35))
	draw_circle(at, r + 2.0, Color(0.02, 0.05, 0.08, 0.92))
	draw_arc(at, r + 2.0, 0.0, TAU, 56, BRASS, 2.2, true)
	draw_arc(at, r - 2.0, 0.0, TAU, 56, Color(BRASS_DIM, 0.4), 1.0, true)


func _speed_gauge(at: Vector2, r: float) -> void:
	_gauge_face(at, r)
	# Scale: -12 (astern) .. 0 .. 30 (ahead), sweep 240° from lower-left to lower-right
	var lo := -12.0
	var hi := max_knots
	var a0 := deg_to_rad(150.0)
	var sweep := deg_to_rad(240.0)
	# Astern zone arc
	var z := a0 + sweep * ((0.0 - lo) / (hi - lo))
	draw_arc(at, r - 5.0, a0, z, 16, Color(AMBER, 0.6), 3.0, true)
	draw_arc(at, r - 5.0, z, a0 + sweep, 32, Color(CYAN, 0.35), 3.0, true)
	for kv in [-10, 0, 10, 20, 30]:
		var t := (float(kv) - lo) / (hi - lo)
		var ang := a0 + sweep * t
		var d := Vector2(cos(ang), sin(ang))
		draw_line(at + d * (r - 9.0), at + d * (r - 1.0), CREAM if kv == 0 else STEEL, 1.6 if kv == 0 else 1.2)
	# Telegraph order pip (brass triangle on rim)
	var order_kn := order * hi if order >= 0.0 else order * hi * 0.42
	var ot := clampf((order_kn - lo) / (hi - lo), 0.0, 1.0)
	var oa := a0 + sweep * ot
	var od := Vector2(cos(oa), sin(oa))
	var on := Vector2(-od.y, od.x)
	draw_colored_polygon(PackedVector2Array([
		at + od * (r - 3.0), at + od * (r + 5.0) + on * 4.0, at + od * (r + 5.0) - on * 4.0,
	]), BRASS)
	# Needle
	var kt := clampf((knots - lo) / (hi - lo), 0.0, 1.0)
	var na := a0 + sweep * kt
	var nd := Vector2(cos(na), sin(na))
	draw_line(at - nd * 4.0, at + nd * (r - 8.0), CYAN if knots >= -0.05 else AMBER, 2.4, true)
	draw_circle(at, 3.5, BRASS)
	_text_center("%.1f" % knots, Vector2(at.x, at.y + r * 0.32), 13, CYAN if knots >= -0.05 else AMBER)
	_text_center("節", Vector2(at.x, at.y + r + 6), 11, MUTED)


func _turret_compass(at: Vector2, r: float) -> void:
	_gauge_face(at, r)
	for i in 12:
		var ang := float(i) * TAU / 12.0
		var d := Vector2(cos(ang), sin(ang))
		var major := i % 3 == 0
		draw_line(at + d * (r - (8.0 if major else 5.0)), at + d * (r - 1.0), STEEL if major else Color(STEEL, 0.5), 1.2)
	# Own ship, bow up
	var s := r * 0.62
	var hull := PackedVector2Array([
		at + Vector2(0, -s), at + Vector2(s * 0.24, -s * 0.45), at + Vector2(s * 0.24, s * 0.7),
		at + Vector2(0, s * 0.85), at + Vector2(-s * 0.24, s * 0.7), at + Vector2(-s * 0.24, -s * 0.45),
	])
	draw_colored_polygon(hull, Color(0.50, 0.60, 0.66, 0.75))
	# Bearing: relative to bow. Bow = up (-Y). Positive rel = starboard (clockwise).
	var ang2 := -PI * 0.5 + turret_rel
	var d2 := Vector2(cos(ang2), sin(ang2))
	var wedge := PackedVector2Array([at])
	for i in 7:
		var a := ang2 - 0.22 + 0.44 * float(i) / 6.0
		wedge.append(at + Vector2(cos(a), sin(a)) * (r - 3.0))
	draw_colored_polygon(wedge, Color(0.40, 0.95, 0.55, 0.22))
	draw_line(at, at + d2 * (r - 6.0), Color(0.48, 1.0, 0.58), 2.4, true)
	draw_circle(at + d2 * (r - 6.0), 2.8, Color(0.48, 1.0, 0.58))
	draw_circle(at, 3.0, BRASS)
	var deg := int(round(rad_to_deg(wrapf(turret_rel, -PI, PI))))
	var side := ""
	if deg > 2:
		side = "右"
	elif deg < -2:
		side = "左"
	_text_center("%s%d°" % [side, absi(deg)], Vector2(at.x, at.y + r + 6), 12, Color(0.72, 0.96, 0.66))


func _keycap(at: Vector2, key: String) -> float:
	var tw := _measure(key, 10)
	var w := maxf(16.0, tw + 8.0)
	var r := Rect2(at, Vector2(w, 16))
	draw_rect(r, Color(0.10, 0.15, 0.20, 0.9), true)
	draw_rect(r, Color(STEEL, 0.7), false, 1.0)
	draw_line(r.position + Vector2(1, r.size.y - 1), r.end - Vector2(1, 1), Color(0, 0, 0, 0.6), 1.0)
	_text_center(key, Vector2(r.get_center().x, at.y + 1), 10, CREAM)
	return at.x + w


# ---------------------------------------------------------------- text


func _measure(text: String, px: int) -> float:
	if font == null:
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


func _text(text: String, pos: Vector2, px: int, col: Color) -> void:
	if font == null:
		return
	draw_string(font, pos + Vector2(0, px), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


func _text_right(text: String, right_top: Vector2, px: int, col: Color) -> void:
	_text(text, right_top - Vector2(_measure(text, px), 0), px, col)


func _text_center(text: String, center_top: Vector2, px: int, col: Color) -> void:
	_text(text, center_top - Vector2(_measure(text, px) * 0.5, 0), px, col)

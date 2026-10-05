extends Node3D

## 海戰風雲錄 — original 3D naval skirmish. Same helm as the top-down prototype.
## Ships are code-built warship hulls (bow, stern, deck, guns), not boxes. The sea is a wave shader.

const WORLD_W := 3400.0
const WORLD_H := 2100.0
const MAX_SPEED := 175.0
const MAX_KNOTS := 30.0
const ACCEL := 95.0
const TURN_RATE := 1.15
const TURRET_RATE := 1.35
const PLAYER_CD := 0.62
const ENEMY_CD := 2.45
const ENEMY_SPEED := 56.0
const ENEMY_TURN := 0.42
const ENEMY_RANGE := 1080.0
const ENEMY_ARC := 0.52
const SHELL_SPEED := 780.0
const SHELL_LIFE := 1.7
const PLAYER_DMG := 420
const ENEMY_DMG := 210
const FONT_PATH := "res://assets/fonts/NotoSansCJK-Regular.ttc"
const MINIMAP_SCRIPT := preload("res://scripts/minimap.gd")
const SEA_SHADER := preload("res://shaders/sea.gdshader")
const VIRTUAL_PAD_SCRIPT := preload("res://scripts/virtual_pad.gd")
const FIRE_PAD_SCRIPT := preload("res://scripts/fire_pad.gd")
const NAVAL_PANEL_SCRIPT := preload("res://scripts/naval_panel.gd")

## Uniform world scale for all ships (visual + collision + related FX).
const SHIP_SCALE := 0.65
## Extra rise so the painted freeboard clears swell crests from the follow camera.
const WATERLINE_LIFT := 3.2

var font: Font
var player: Ship
var enemies: Array[Ship] = []
var shells: Array[Shell] = []
var islands: Array[PackedVector2Array] = []
var effects: Array[Dictionary] = []
var floaters: Array[Dictionary] = []
var holds := {
	"fwd": false,
	"back": false,
	"left": false,
	"right": false,
	"tleft": false,
	"tright": false,
	"fire": false,
}
var outcome := ""
var cam: Camera3D
var cam_ready := false
var sea_time := 0.0
var sea_mat: ShaderMaterial
var banner: Label
var retry: Button
var dim: ColorRect
var map_ctrl: Control
var naval_panel: Control
var virtual_pad: Control
var fire_pad: Control
var throttle_order := 0.0
var pad_rudder := 0.0
var aim_marks: Array[MeshInstance3D] = []
var shell_mesh: BoxMesh
var splash_mesh: TorusMesh
var flash_mesh: SphereMesh
var shell_mat_player: StandardMaterial3D
var shell_mat_enemy: StandardMaterial3D
var hull_mat: StandardMaterial3D
var wake_mat: StandardMaterial3D

class Ship:
	var pos := Vector2.ZERO
	var heading := 0.0
	var turret := 0.0
	var hp := 1000
	var max_hp := 1000
	var radius := 36.0
	var along := 0.0
	var afloat := true
	var sink := 0.0
	var player := false
	var kind := 0
	var hull := Color(0.4, 0.4, 0.4)
	var deck := Color(0.78, 0.8, 0.74)
	var cd := 0.0
	var goal := Vector2.ZERO
	var think := 1.0
	var mount := 0.0
	var gun_y := 8.0
	var body: Node3D
	var wake: MeshInstance3D
	var wake_trail: Array[Vector2] = []
	var wake_beam := 12.0
	var turret_pivots: Array[Node3D] = []

class Shell:
	var pos := Vector2.ZERO
	var dir := Vector2.RIGHT
	var owner: Ship
	var from_player := false
	var life := 1.7
	var gun_y := 6.0
	var node: MeshInstance3D


func _ready() -> void:
	font = _make_font()
	_build_fx_meshes()
	_build_islands()
	_build_ships()
	_build_world()
	_build_ui()
	_place_camera(1.0)
	DisplayServer.window_set_title("海戰風雲錄")


func _make_font() -> Font:
	var base := FontFile.new()
	base.allow_system_fallback = false
	var bytes := FileAccess.get_file_as_bytes(FONT_PATH)
	if bytes.is_empty():
		push_error("CJK font missing at %s" % FONT_PATH)
	base.data = bytes
	var variation := FontVariation.new()
	variation.base_font = base
	variation.variation_face_index = 3
	return variation


func _build_fx_meshes() -> void:
	shell_mesh = BoxMesh.new()
	shell_mesh.size = Vector3(2.4, 2.4, 14.0)
	splash_mesh = TorusMesh.new()
	splash_mesh.outer_radius = 1.0
	splash_mesh.inner_radius = 0.62
	splash_mesh.rings = 10
	splash_mesh.ring_segments = 18
	flash_mesh = SphereMesh.new()
	flash_mesh.radius = 2.4
	flash_mesh.height = 4.8
	shell_mat_player = _shot_mat(Color(1.0, 0.92, 0.62))
	shell_mat_enemy = _shot_mat(Color(1.0, 0.58, 0.32))
	hull_mat = StandardMaterial3D.new()
	hull_mat.vertex_color_use_as_albedo = true
	hull_mat.roughness = 0.55
	hull_mat.metallic = 0.2
	hull_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wake_mat = StandardMaterial3D.new()
	wake_mat.albedo_color = Color(0.88, 0.97, 1.0, 1.0)
	wake_mat.vertex_color_use_as_albedo = true
	wake_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wake_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wake_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	wake_mat.emission_enabled = true
	wake_mat.emission = Color(0.72, 0.9, 1.0)
	wake_mat.emission_energy_multiplier = 0.55
	wake_mat.no_depth_test = false


func _shot_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	mat.roughness = 0.28
	mat.metallic = 0.2
	return mat


func _solid(color: Color, rough: float, metal: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	return mat


func _build_islands() -> void:
	_add_island(Vector2(1180, 760), [210, 170, 240, 150, 200, 160, 230], 0.4, Color(0.34, 0.5, 0.3))
	_add_island(Vector2(1760, 1460), [180, 260, 150, 220, 140, 200], 1.1, Color(0.30, 0.46, 0.28))
	_add_island(Vector2(2620, 540), [150, 120, 190, 110, 160, 130, 170, 100], 0.2, Color(0.38, 0.52, 0.31))
	_add_island(Vector2(2140, 1720), [120, 90, 140, 80, 110], 2.0, Color(0.32, 0.48, 0.27))


func _add_island(center: Vector2, scales: Array, rot: float, foliage: Color) -> void:
	var pts := PackedVector2Array()
	var n := scales.size()
	for i in n:
		var ang := rot + TAU * float(i) / float(n)
		pts.append(center + Vector2.from_angle(ang) * float(scales[i]))
	islands.append(pts)
	var reach := 0.0
	for sc in scales:
		reach += float(sc)
	reach /= float(n)
	var height := clampf(reach * 0.26, 24.0, 58.0)
	_add_island_mesh(pts, height, foliage)


func _add_island_mesh(poly: PackedVector2Array, height: float, foliage: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var ctr := Vector2.ZERO
	for p in poly:
		ctr += p
	ctr /= float(n)
	var sand := Color(0.64, 0.56, 0.38)
	var rock := Color(0.40, 0.38, 0.34)
	var peak := Vector3(ctr.x, height, ctr.y)
	var top_y := height * 0.72
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		var a_top_2 := ctr + (a - ctr) * 0.8
		var b_top_2 := ctr + (b - ctr) * 0.8
		var ba := Vector3(a.x, -8.0, a.y)
		var bb := Vector3(b.x, -8.0, b.y)
		var ta := Vector3(a_top_2.x, top_y, a_top_2.y)
		var tb := Vector3(b_top_2.x, top_y, b_top_2.y)
		_tri_cols(st, ba, ta, tb, rock, sand, sand)
		_tri_cols(st, ba, tb, bb, rock, sand, rock)
		_tri_cols(st, ta, peak, tb, foliage, foliage.lightened(0.08), foliage)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.94
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_ships() -> void:
	player = Ship.new()
	player.player = true
	player.kind = 0
	player.pos = Vector2(560, 1040)
	player.heading = 0.2
	player.turret = 0.2
	player.hp = 3000
	player.max_hp = 3000
	player.radius = 52.0
	player.mount = 10.0
	player.hull = Color(0.24, 0.34, 0.40)
	player.deck = Color(0.78, 0.76, 0.66)
	player.turret_pivots = []
	if _blocked(player.pos, 30.0 * SHIP_SCALE):
		player.pos = Vector2(480, 1000)
	_compose_ship(player)

	# 4 cruisers + 6 destroyers. Victory is all ten sunk.
	var specs: Array[Dictionary] = [
		{"pos": Vector2(2860, 1480), "heading": PI, "kind": 1, "hp": 1500, "radius": 34.0, "hull": Color(0.46, 0.30, 0.26), "deck": Color(0.60, 0.50, 0.38), "cd": 0.5},
		{"pos": Vector2(2320, 420), "heading": 2.5, "kind": 1, "hp": 1600, "radius": 34.0, "hull": Color(0.30, 0.36, 0.44), "deck": Color(0.58, 0.50, 0.40), "cd": 1.3},
		{"pos": Vector2(1680, 1880), "heading": -0.5, "kind": 1, "hp": 1450, "radius": 34.0, "hull": Color(0.34, 0.40, 0.28), "deck": Color(0.56, 0.48, 0.36), "cd": 2.0},
		{"pos": Vector2(3080, 860), "heading": 2.8, "kind": 1, "hp": 1550, "radius": 36.0, "hull": Color(0.40, 0.32, 0.40), "deck": Color(0.62, 0.54, 0.42), "cd": 0.2},
		{"pos": Vector2(980, 1680), "heading": 0.7, "kind": 2, "hp": 780, "radius": 22.0, "hull": Color(0.62, 0.64, 0.60), "deck": Color(0.74, 0.75, 0.70), "cd": 0.8},
		{"pos": Vector2(1240, 280), "heading": 1.3, "kind": 2, "hp": 740, "radius": 22.0, "hull": Color(0.56, 0.58, 0.54), "deck": Color(0.72, 0.73, 0.68), "cd": 1.7},
		{"pos": Vector2(2480, 1120), "heading": PI, "kind": 2, "hp": 820, "radius": 22.0, "hull": Color(0.50, 0.52, 0.48), "deck": Color(0.70, 0.72, 0.66), "cd": 2.3},
		{"pos": Vector2(1880, 700), "heading": 2.1, "kind": 2, "hp": 760, "radius": 22.0, "hull": Color(0.58, 0.54, 0.46), "deck": Color(0.73, 0.70, 0.62), "cd": 0.4},
		{"pos": Vector2(640, 360), "heading": 0.9, "kind": 2, "hp": 800, "radius": 22.0, "hull": Color(0.48, 0.52, 0.54), "deck": Color(0.70, 0.74, 0.72), "cd": 1.1},
		{"pos": Vector2(2680, 1760), "heading": -1.6, "kind": 2, "hp": 790, "radius": 22.0, "hull": Color(0.54, 0.50, 0.42), "deck": Color(0.72, 0.68, 0.58), "cd": 2.6},
	]
	for spec in specs:
		var e := Ship.new()
		e.pos = spec["pos"]
		e.heading = float(spec["heading"])
		e.turret = e.heading
		e.kind = int(spec["kind"])
		e.hp = int(spec["hp"])
		e.max_hp = e.hp
		e.radius = float(spec["radius"])
		e.hull = spec["hull"]
		e.deck = spec["deck"]
		e.cd = float(spec["cd"])
		e.goal = _random_water()
		e.think = randf_range(2.0, 4.5)
		e.turret_pivots = []
		if _blocked(e.pos, 24.0 * SHIP_SCALE):
			e.pos = _random_water()
		_compose_ship(e)
		enemies.append(e)


func _kind_spec(kind: int) -> Dictionary:
	if kind == 0:
		return {
			"length": 188.0,
			"beam": 32.0,
			"height": 15.5,
			"role": "bb",
			"turrets": [
				{"x": 54.0, "y": 0.0, "scale": 1.12, "barrels": 3},
				{"x": 34.0, "y": 3.8, "scale": 1.08, "barrels": 3},
				{"x": -50.0, "y": 3.6, "scale": 1.02, "barrels": 3},
				{"x": -70.0, "y": 0.0, "scale": 1.0, "barrels": 3},
			],
		}
	if kind == 1:
		return {
			"length": 146.0,
			"beam": 20.0,
			"height": 11.0,
			"role": "ca",
			"turrets": [
				{"x": 42.0, "y": 0.0, "scale": 0.78, "barrels": 2},
				{"x": 22.0, "y": 2.5, "scale": 0.74, "barrels": 2},
				{"x": -50.0, "y": 0.0, "scale": 0.76, "barrels": 2},
			],
		}
	return {
		"length": 132.0,
		"beam": 13.0,
		"height": 9.6,
		"role": "dd",
		"turrets": [
			{"x": 40.0, "y": 0.0, "scale": 0.64, "barrels": 2},
			{"x": -44.0, "y": 0.0, "scale": 0.62, "barrels": 2},
		],
	}


func _compose_ship(s: Ship) -> void:
	var spec: Dictionary = _kind_spec(s.kind)
	var length: float = float(spec["length"])
	var beam: float = float(spec["beam"])
	var height: float = float(spec["height"])
	var role: String = str(spec["role"])
	var body := Node3D.new()
	body.name = "Ship"
	add_child(body)
	s.body = body
	var hull_mi := MeshInstance3D.new()
	hull_mi.mesh = _hull_mesh(length, beam, height, s.hull, s.deck)
	hull_mi.material_override = hull_mat
	hull_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(hull_mi)
	var house := _solid(s.deck.darkened(0.2), 0.58, 0.08)
	var funnel_mat := _solid(Color(0.11, 0.11, 0.12), 0.4, 0.25)
	var turret_mat := _solid(Color(0.17, 0.19, 0.21), 0.36, 0.38)
	var barrel_mat := _solid(Color(0.06, 0.065, 0.07), 0.28, 0.55)
	var metal := _solid(Color(0.14, 0.15, 0.16), 0.42, 0.45)
	var glass := _solid(Color(0.12, 0.2, 0.26), 0.18, 0.35)
	var boat := _solid(Color(0.82, 0.8, 0.72), 0.7, 0.02)
	_dress_ship(body, role, length, beam, height, house, funnel_mat, metal, glass, boat)
	var pivots: Array[Node3D] = []
	var layout: Array = spec["turrets"]
	var top_gun := 6.0
	for item in layout:
		var x: float = float(item["x"])
		var extra_y: float = float(item["y"])
		var sc: float = float(item["scale"])
		var barrels: int = int(item["barrels"])
		var dy: float = _deck_at(length, height, x)
		var piv := _add_turret(body, x, dy + extra_y, sc, barrels, turret_mat, barrel_mat)
		pivots.append(piv)
		top_gun = maxf(top_gun, dy + extra_y + 4.4 * sc)
	s.turret_pivots = pivots
	s.gun_y = top_gun
	if role == "bb":
		_add_broadsides(body, length, beam, height, turret_mat, barrel_mat)
	var wake := MeshInstance3D.new()
	wake.name = "WakeRibbon"
	wake.material_override = wake_mat
	wake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wake.visible = false
	add_child(wake)
	s.wake = wake
	s.wake_trail = []
	s.wake_beam = beam * 0.85
	# Uniform ship scale: visual root + gameplay sizes derived from design units.
	body.scale = Vector3.ONE * SHIP_SCALE
	s.radius *= SHIP_SCALE
	s.gun_y *= SHIP_SCALE
	s.mount *= SHIP_SCALE
	_sync_ship(s)


func _dress_ship(body: Node3D, role: String, length: float, beam: float, height: float, house: Material, funnel_mat: Material, metal: Material, glass: Material, boat: Material) -> void:
	if role == "bb":
		var deck_b: float = _deck_at(length, height, 8.0)
		var bsize := Vector3(22.0, 8.2, beam * 0.42)
		_add_bridge_block(body, bsize, Vector3(8.0, deck_b + bsize.y * 0.5, 0.0), house, glass)
		_box(body, Vector3(11.0, 4.2, beam * 0.26), Vector3(11.0, deck_b + bsize.y + 2.3, 0.0), house)
		_box(body, Vector3(9.0, 1.15, beam * 0.68), Vector3(12.0, deck_b + 7.4, 0.0), house)
		_add_funnel(body, 3.05, 11.0, Vector3(-16.0, _deck_at(length, height, -16.0), 0.0), funnel_mat)
		_add_funnel(body, 2.75, 9.4, Vector3(-34.0, _deck_at(length, height, -34.0), 0.0), funnel_mat)
		_add_mast(body, Vector3(2.0, deck_b + bsize.y + 4.4, 0.0), 20.0, metal, true)
		_add_mast(body, Vector3(-42.0, _deck_at(length, height, -42.0), 0.0), 15.0, metal, false)
		_add_breakwater(body, length, beam, height, 76.0, house)
		_add_boat(body, length, beam, height, -24.0, boat)
		_add_propellers(body, length, beam, height, metal, 2.55)
		_box(body, Vector3(length * 0.28, height * 0.22, 0.5), Vector3(-length * 0.22, -height * 0.18, 0.0), metal)
	elif role == "ca":
		var deck_c: float = _deck_at(length, height, -2.0)
		var csize := Vector3(16.0, 5.6, beam * 0.48)
		_add_bridge_block(body, csize, Vector3(-2.0, deck_c + csize.y * 0.5, 0.0), house, glass)
		_box(body, Vector3(7.5, 2.6, beam * 0.3), Vector3(0.0, deck_c + csize.y + 1.5, 0.0), house)
		_add_funnel(body, 1.9, 7.8, Vector3(-18.0, _deck_at(length, height, -18.0), 0.0), funnel_mat)
		_add_funnel(body, 1.7, 6.6, Vector3(-32.0, _deck_at(length, height, -32.0), 0.0), funnel_mat)
		_add_mast(body, Vector3(-4.0, deck_c + csize.y + 2.6, 0.0), 14.0, metal, false)
		_add_mast(body, Vector3(-40.0, _deck_at(length, height, -40.0), 0.0), 10.0, metal, false)
		_add_breakwater(body, length, beam, height, 58.0, house)
		_add_propellers(body, length, beam, height, metal, 1.65)
		_box(body, Vector3(length * 0.22, height * 0.2, 0.4), Vector3(-length * 0.2, -height * 0.16, 0.0), metal)
	else:
		var deck_d: float = _deck_at(length, height, 6.0)
		var dsize := Vector3(12.0, 3.3, beam * 0.6)
		_add_bridge_block(body, dsize, Vector3(6.0, deck_d + dsize.y * 0.5, 0.0), house, glass)
		_add_funnel(body, 1.15, 5.2, Vector3(-8.0, _deck_at(length, height, -8.0), 0.0), funnel_mat)
		_add_funnel(body, 1.05, 4.5, Vector3(-18.0, _deck_at(length, height, -18.0), 0.0), funnel_mat)
		_add_mast(body, Vector3(8.0, deck_d + dsize.y + 0.4, 0.0), 11.0, metal, false)
		_add_breakwater(body, length, beam, height, 50.0, house)
		_add_propellers(body, length, beam, height, metal, 1.05)
		_box(body, Vector3(length * 0.16, height * 0.18, 0.28), Vector3(-length * 0.18, -height * 0.14, 0.0), metal)


func _add_bridge_block(parent: Node3D, size: Vector3, pos: Vector3, house: Material, glass: Material) -> void:
	_box(parent, size, pos, house)
	_box(parent, Vector3(0.5, size.y * 0.24, size.z * 0.78), pos + Vector3(size.x * 0.48, size.y * 0.12, 0.0), glass)


func _add_funnel(parent: Node3D, radius: float, height: float, base: Vector3, mat: Material) -> void:
	var pivot := Node3D.new()
	pivot.position = base
	pivot.rotation_degrees = Vector3(0.0, 0.0, 7.0)
	parent.add_child(pivot)
	_cyl(pivot, radius, height, Vector3(0.0, height * 0.5, 0.0), mat)
	_cyl(pivot, radius * 1.28, maxf(0.55, radius * 0.32), Vector3(0.0, height + 0.2, 0.0), mat)
	var cap := _solid(Color(0.05, 0.05, 0.06), 0.55, 0.1)
	_cyl(pivot, radius * 0.72, 0.35, Vector3(0.0, height + 0.15, 0.0), cap)


func _add_mast(parent: Node3D, base: Vector3, mast_h: float, mat: Material, tripod: bool) -> void:
	var pole_w := 1.15 if mast_h >= 18.0 else 0.8
	_box(parent, Vector3(pole_w, mast_h, pole_w), base + Vector3(0.0, mast_h * 0.5, 0.0), mat)
	_box(parent, Vector3(mast_h * 0.34, 0.42, 0.42), base + Vector3(0.3, mast_h * 0.76, 0.0), mat)
	_box(parent, Vector3(0.38, 0.38, mast_h * 0.16), base + Vector3(0.3, mast_h * 0.76, 0.0), mat)
	_box(parent, Vector3(2.2, 0.55, 2.2), base + Vector3(0.0, mast_h * 0.58, 0.0), mat)
	if tripod:
		var leg_a := _box(parent, Vector3(0.65, mast_h * 0.7, 0.65), base + Vector3(-1.8, mast_h * 0.28, 2.1), mat)
		leg_a.rotation_degrees = Vector3(16.0, 0.0, 12.0)
		var leg_b := _box(parent, Vector3(0.65, mast_h * 0.7, 0.65), base + Vector3(-1.8, mast_h * 0.28, -2.1), mat)
		leg_b.rotation_degrees = Vector3(-16.0, 0.0, 12.0)


func _add_breakwater(body: Node3D, length: float, beam: float, height: float, x: float, mat: Material) -> void:
	var y: float = _deck_at(length, height, x) + 1.05
	var span: float = beam * 0.22
	var a := _box(body, Vector3(0.65, 2.0, span), Vector3(x, y, beam * 0.1), mat)
	a.rotation_degrees = Vector3(0.0, 26.0, 0.0)
	var b := _box(body, Vector3(0.65, 2.0, span), Vector3(x, y, -beam * 0.1), mat)
	b.rotation_degrees = Vector3(0.0, -26.0, 0.0)


func _add_boat(body: Node3D, length: float, beam: float, height: float, x: float, mat: Material) -> void:
	var y: float = _deck_at(length, height, x) + 0.9
	_box(body, Vector3(8.0, 1.5, 2.2), Vector3(x, y, beam * 0.36), mat)
	_box(body, Vector3(8.0, 1.5, 2.2), Vector3(x, y, -beam * 0.36), mat)


func _add_propellers(body: Node3D, length: float, beam: float, height: float, mat: Material, radius: float) -> void:
	for side in [-1.0, 1.0]:
		var z: float = side * beam * 0.16
		var shaft := _cyl(body, radius * 0.22, radius * 1.5, Vector3(-length * 0.45, -height * 0.2, z), mat)
		shaft.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		var disc := _cyl(body, radius, radius * 0.16, Vector3(-length * 0.478, -height * 0.2, z), mat)
		disc.rotation_degrees = Vector3(0.0, 0.0, 90.0)


func _add_broadsides(body: Node3D, length: float, beam: float, height: float, housing: Material, barrel_mat: Material) -> void:
	for x in [24.0, -44.0]:
		for side in [-1.0, 1.0]:
			var y: float = _deck_at(length, height, x) + 0.2
			var piv := _add_turret(body, x, y, 0.42, 1, housing, barrel_mat)
			piv.position = Vector3(x, y, side * beam * 0.34)
			piv.rotation.y = -PI * 0.5 * side


func _add_turret(parent: Node3D, x: float, y: float, scale: float, barrels: int, housing: Material, barrel_mat: Material) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = Vector3(x, y, 0.0)
	parent.add_child(pivot)
	var barb := CylinderMesh.new()
	barb.top_radius = 3.15 * scale
	barb.bottom_radius = 3.55 * scale
	barb.height = 2.25 * scale
	barb.radial_segments = 14
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = barb
	base_mi.position = Vector3(0.0, 1.12 * scale, 0.0)
	base_mi.material_override = housing
	base_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pivot.add_child(base_mi)
	var zs: Array = [0.0]
	var spread := 0.0
	if barrels <= 1:
		zs = [0.0]
		spread = 0.0
	elif barrels == 2:
		zs = [-1.2, 1.2]
		spread = 1.2
	else:
		zs = [-2.05, 0.0, 2.05]
		spread = 2.05
	var house_z: float = (spread * 2.0 + 3.5) * scale
	_box(pivot, Vector3(7.6 * scale, 3.15 * scale, house_z), Vector3(0.15 * scale, 3.15 * scale, 0.0), housing)
	_box(pivot, Vector3(1.35 * scale, 0.8 * scale, house_z * 0.9), Vector3(-0.7 * scale, 4.95 * scale, 0.0), housing)
	var barrel_len: float = maxf(8.5, 16.5 * scale)
	var barrel_w: float = maxf(1.15, 1.3 * scale)
	if barrels <= 1:
		barrel_len = maxf(7.5, 13.0 * scale)
		barrel_w = maxf(1.25, 1.55 * scale)
	for side in zs:
		var box := BoxMesh.new()
		box.size = Vector3(barrel_len, barrel_w, barrel_w)
		var bmi := MeshInstance3D.new()
		bmi.mesh = box
		bmi.position = Vector3(barrel_len * 0.48, 3.4 * scale, float(side) * scale)
		bmi.material_override = barrel_mat
		bmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pivot.add_child(bmi)
	return pivot



func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.08
	mesh.height = height
	mesh.radial_segments = 10
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _beam_factor(t: float) -> float:
	if t < 0.18:
		var u := t / 0.18
		return 0.05 + 0.57 * sin(u * PI * 0.5)
	if t < 0.42:
		var u2 := (t - 0.18) / 0.24
		var s := u2 * u2 * (3.0 - 2.0 * u2)
		return 0.62 + 0.38 * s
	if t < 0.70:
		return 1.0
	if t < 0.86:
		var u3 := (t - 0.70) / 0.16
		return lerpf(1.0, 0.55, u3)
	var u4 := (t - 0.86) / 0.14
	return lerpf(0.55, 0.26, clampf(u4, 0.0, 1.0))


func _sheer(t: float) -> float:
	var bow := exp(-t * 3.1)
	var stern := clampf((t - 0.75) / 0.25, 0.0, 1.0)
	stern = stern * stern * (3.0 - 2.0 * stern)
	return 0.34 + bow * 0.42 + stern * 0.16


func _keel_frac(t: float) -> float:
	var mid := sin(clampf(t, 0.0, 1.0) * PI)
	return 0.20 + mid * 0.62


func _deck_at(length: float, height: float, x: float) -> float:
	var t := clampf(0.50 - x / length, 0.0, 1.0)
	return height * _sheer(t) + 0.35


func _station(length: float, beam: float, height: float, t: float) -> PackedVector3Array:
	var x0 := length * (0.50 - t)
	var hb := beam * 0.5 * _beam_factor(t)
	var deck_y := height * _sheer(t)
	var keel_y := -height * _keel_frac(t)
	var flare := 1.0
	if t < 0.22:
		flare = lerpf(1.28, 1.0, t / 0.22)
	elif t > 0.8:
		flare = lerpf(1.0, 1.08, clampf((t - 0.8) / 0.2, 0.0, 1.0))
	var deck_z := hb * flare
	var wl_z := hb * 0.94
	var bilge_z := hb * 0.56
	var keel_z := hb * 0.08
	var deck_rake := 0.0
	var keel_rake := 0.0
	if t < 0.28:
		var k := (0.28 - t) / 0.28
		deck_rake = k * k * length * 0.06
		keel_rake = k * length * 0.01
	elif t > 0.80:
		var k2 := (t - 0.80) / 0.20
		deck_rake = -k2 * length * 0.028
		keel_rake = k2 * length * 0.012
	var xd := x0 + deck_rake
	var xm := x0 + deck_rake * 0.35
	var xw := x0
	var xk := x0 + keel_rake
	var pts := PackedVector3Array()
	pts.append(Vector3(xd, deck_y + height * 0.06, deck_z))
	pts.append(Vector3(xd, deck_y, deck_z * 0.92))
	pts.append(Vector3(xm, deck_y * 0.45, wl_z))
	pts.append(Vector3(xw, -height * 0.02, wl_z * 0.98))
	pts.append(Vector3(xk, keel_y * 0.45, bilge_z))
	pts.append(Vector3(xk, keel_y, keel_z))
	pts.append(Vector3(xk, keel_y, -keel_z))
	pts.append(Vector3(xk, keel_y * 0.45, -bilge_z))
	pts.append(Vector3(xw, -height * 0.02, -wl_z * 0.98))
	pts.append(Vector3(xm, deck_y * 0.45, -wl_z))
	pts.append(Vector3(xd, deck_y, -deck_z * 0.92))
	pts.append(Vector3(xd, deck_y + height * 0.06, -deck_z))
	return pts


func _is_upper_idx(k: int) -> bool:
	return k <= 2 or k >= 9


func _hull_mesh(length: float, beam: float, height: float, paint: Color, deck_col: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stations := 18
	var rings: Array = []
	for i in stations:
		var t := lerpf(0.0, 1.0, float(i) / float(stations - 1))
		rings.append(_station(length, beam, height, t))
	var sides := 12
	for i in stations - 1:
		var ring_a: PackedVector3Array = rings[i]
		var ring_b: PackedVector3Array = rings[i + 1]
		for k in sides:
			var k2 := (k + 1) % sides
			var a: Vector3 = ring_a[k]
			var b: Vector3 = ring_a[k2]
			var d: Vector3 = ring_b[k]
			var c: Vector3 = ring_b[k2]
			var centroid := (a + b + c + d) * 0.0
			var hint := Vector3(0.0, centroid.y, centroid.z)
			if hint.length_squared() < 0.04:
				hint = Vector3(0.0, 1.0, 0.0)
			_tri_hull_out(st, a, d, c, paint, hint)
			_tri_hull_out(st, a, c, b, paint, hint)
		var s1: Vector3 = ring_a[1]
		var p1: Vector3 = ring_a[10]
		var s2: Vector3 = ring_b[1]
		var p2: Vector3 = ring_b[10]
		var c1 := Vector3((s1.x + p1.x) * 0.5, (s1.y + p1.y) * 0.5, 0.0)
		var c2 := Vector3((s2.x + p2.x) * 0.5, (s2.y + p2.y) * 0.5, 0.0)
		_tri_flat_out(st, c1, s1, s2, deck_col, Vector3.UP)
		_tri_flat_out(st, c1, s2, c2, deck_col, Vector3.UP)
		_tri_flat_out(st, c1, p2, p1, deck_col, Vector3.UP)
		_tri_flat_out(st, c1, c2, p2, deck_col, Vector3.UP)
	var bow: PackedVector3Array = rings[0]
	var nose := Vector3(length * 0.575, bow[1].y * 0.96, 0.0)
	var stem := Vector3(length * 0.535, height * 0.02, 0.0)
	var bow_hint := Vector3(1.0, 0.15, 0.0)
	for k in sides:
		var k2 := (k + 1) % sides
		var tip_a := nose if _is_upper_idx(k) else stem
		var tip_b := nose if _is_upper_idx(k2) else stem
		if tip_a.is_equal_approx(tip_b):
			_tri_hull_out(st, tip_a, bow[k2], bow[k], paint, bow_hint)
		else:
			_tri_hull_out(st, tip_a, tip_b, bow[k], paint, bow_hint)
			_tri_hull_out(st, tip_b, bow[k2], bow[k], paint, bow_hint)
	_tri_flat_out(st, nose, bow[1], bow[10], deck_col, Vector3.UP)
	var last: PackedVector3Array = rings[stations - 1]
	var cx := 0.0
	for p in last:
		cx += p.x
	cx /= float(last.size())
	var stern_c := Vector3(cx - length * 0.012, (last[0].y + last[5].y) * 0.42, 0.0)
	var stern_hint := Vector3(-1.0, 0.0, 0.0)
	for k in sides:
		_tri_hull_out(st, stern_c, last[k], last[(k + 1) % sides], paint, stern_hint)
	var tail := Vector3((last[1].x + last[10].x) * 0.5 - length * 0.01, last[1].y, 0.0)
	_tri_flat_out(st, tail, last[10], last[1], deck_col, Vector3.UP)
	return st.commit()


func _hull_color(paint: Color, y: float) -> Color:
	if y < -1.05:
		return Color(0.36, 0.13, 0.11).lerp(paint.darkened(0.4), 0.18)
	if y < 0.2:
		return paint.darkened(0.14)
	return paint.lightened(0.05)


func _tri_hull_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, paint: Color, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0004:
		return
	if n.dot(hint) < 0.0:
		_tri_hull(st, a, c, b, paint)
	else:
		_tri_hull(st, a, b, c, paint)


func _tri_flat_out(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, col: Color, hint: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.0004:
		return
	var bb := b
	var cc := c
	if n.dot(hint) < 0.0:
		bb = c
		cc = b
		n = -n
	n = n.normalized()
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(bb)
	st.set_normal(n)
	st.set_color(col)
	st.add_vertex(cc)

func _tri_hull(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, paint: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() > 0.00001:
		n = n.normalized()
	else:
		n = Vector3.UP
	st.set_normal(n)
	st.set_color(_hull_color(paint, a.y))
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(_hull_color(paint, b.y))
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(_hull_color(paint, c.y))
	st.add_vertex(c)


func _tri_cols(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.32, 0.52, 0.82)
	sky_mat.sky_horizon_color = Color(0.72, 0.8, 0.84)
	sky_mat.sky_curve = 0.09
	sky_mat.ground_bottom_color = Color(0.05, 0.14, 0.22)
	sky_mat.ground_horizon_color = Color(0.55, 0.68, 0.74)
	sky_mat.ground_curve = 0.06
	sky_mat.sun_angle_max = 28.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.64, 0.77, 0.86)
	env.fog_density = 0.0002
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, 32.0, 0.0)
	sun.light_energy = 1.3
	sun.light_color = Color(1.0, 0.97, 0.9)
	sun.shadow_enabled = false
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, 210.0, 0.0)
	fill.light_energy = 0.38
	fill.light_color = Color(0.72, 0.84, 1.0)
	fill.shadow_enabled = false
	add_child(fill)

	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var plane := PlaneMesh.new()
	plane.orientation = PlaneMesh.FACE_Y
	plane.size = Vector2(12000.0, 9000.0)
	plane.subdivide_width = 160
	plane.subdivide_depth = 110
	sea.mesh = plane
	sea.position = Vector3(WORLD_W * 0.5, -0.35, WORLD_H * 0.5)
	sea_mat = ShaderMaterial.new()
	sea_mat.shader = SEA_SHADER
	sea.material_override = sea_mat
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sea.extra_cull_margin = 40.0
	add_child(sea)

	cam = Camera3D.new()
	cam.fov = 55.0
	cam.near = 0.4
	cam.far = 8000.0
	add_child(cam)
	cam.make_current()

	var mark_mesh := BoxMesh.new()
	mark_mesh.size = Vector3(7.0, 1.4, 1.3)
	var mark_mat := StandardMaterial3D.new()
	mark_mat.albedo_color = Color(0.45, 1.0, 0.5, 0.9)
	mark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark_mat.emission_enabled = true
	mark_mat.emission = Color(0.35, 0.9, 0.4)
	mark_mat.emission_energy_multiplier = 1.4
	for _i in 6:
		var mark := MeshInstance3D.new()
		mark.mesh = mark_mesh
		mark.material_override = mark_mat
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mark)
		aim_marks.append(mark)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)

	# Professional left HUD (narrow floating glass panel)
	naval_panel = Control.new()
	naval_panel.set_script(NAVAL_PANEL_SCRIPT)
	naval_panel.position = Vector2(10, 10)
	naval_panel.size = Vector2(228, 448)
	naval_panel.custom_minimum_size = Vector2(228, 448)
	naval_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	naval_panel.setup(font)
	root.add_child(naval_panel)

	# Minimap top-right
	var frame := PanelContainer.new()
	frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame.offset_left = -248
	frame.offset_top = 12
	frame.offset_right = -12
	frame.offset_bottom = 12 + 152
	var map_box := _flat(Color(0.04, 0.09, 0.14, 0.82), 8)
	map_box.border_color = Color(0.78, 0.64, 0.30, 0.85)
	map_box.border_width_left = 2
	map_box.border_width_top = 2
	map_box.border_width_right = 2
	map_box.border_width_bottom = 2
	frame.add_theme_stylebox_override("panel", map_box)
	root.add_child(frame)

	map_ctrl = Control.new()
	map_ctrl.set_script(MINIMAP_SCRIPT)
	map_ctrl.battle = self
	map_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_ctrl.offset_left = 6
	map_ctrl.offset_top = 6
	map_ctrl.offset_right = -6
	map_ctrl.offset_bottom = -6
	map_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(map_ctrl)

	# Virtual helm pad — bottom-left of sea view
	virtual_pad = Control.new()
	virtual_pad.set_script(VIRTUAL_PAD_SCRIPT)
	virtual_pad.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	virtual_pad.offset_left = 24
	virtual_pad.offset_top = -196
	virtual_pad.offset_right = 24 + 172
	virtual_pad.offset_bottom = -24
	virtual_pad.throttle_changed.connect(_on_throttle_changed)
	virtual_pad.rudder_changed.connect(_on_rudder_changed)
	root.add_child(virtual_pad)

	# Fire cluster — bottom-right
	fire_pad = Control.new()
	fire_pad.set_script(FIRE_PAD_SCRIPT)
	fire_pad.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_pad.offset_left = -220
	fire_pad.offset_top = -170
	fire_pad.offset_right = -16
	fire_pad.offset_bottom = -16
	fire_pad.fire_changed.connect(func(d): _set_hold("fire", d))
	fire_pad.turret_left_changed.connect(func(d): _set_hold("tleft", d))
	fire_pad.turret_right_changed.connect(func(d): _set_hold("tright", d))
	root.add_child(fire_pad)

	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.03, 0.05, 0.55)
	dim.visible = false
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	banner = _lab("", 56, Color(0.98, 0.93, 0.72))
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -360
	banner.offset_top = -90
	banner.offset_right = 360
	banner.offset_bottom = -16
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_constant_override("outline_size", 10)
	banner.add_theme_color_override("font_outline_color", Color(0.02, 0.05, 0.08, 0.92))
	banner.visible = false
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(banner)

	# Graphic retry button (icon + short label)
	retry = Button.new()
	retry.text = "  再來一次"
	retry.visible = false
	retry.focus_mode = Control.FOCUS_NONE
	retry.set_anchors_preset(Control.PRESET_CENTER)
	retry.offset_left = -100
	retry.offset_top = 20
	retry.offset_right = 100
	retry.offset_bottom = 76
	_style_retry(retry)
	retry.pressed.connect(_on_retry)
	root.add_child(retry)


func _lab(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	return l


func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	return sb


func _style_retry(btn: Button) -> void:
	var normal := _flat(Color(0.12, 0.22, 0.30, 0.92), 12)
	normal.border_color = Color(0.78, 0.64, 0.30, 0.95)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	var hover := _flat(Color(0.18, 0.34, 0.44, 0.95), 12)
	hover.border_color = Color(0.40, 0.90, 0.98, 0.95)
	hover.border_width_left = 2
	hover.border_width_top = 2
	hover.border_width_right = 2
	hover.border_width_bottom = 2
	var pressed := _flat(Color(0.08, 0.16, 0.22, 0.95), 12)
	pressed.border_color = Color(0.78, 0.64, 0.30, 0.8)
	pressed.border_width_left = 2
	pressed.border_width_top = 2
	pressed.border_width_right = 2
	pressed.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", normal)
	btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 22)
	btn.add_theme_color_override("font_color", Color(0.96, 0.93, 0.84))
	btn.add_theme_color_override("font_hover_color", Color(0.40, 0.95, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.85, 0.82, 0.72))
	# Procedural refresh icon via button icon
	var img := Image.create(28, 28, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for a in range(0, 270):
		var rad := deg_to_rad(float(a) - 90.0)
		for rr in range(8, 11):
			var x := int(14.0 + cos(rad) * float(rr))
			var y := int(14.0 + sin(rad) * float(rr))
			if x >= 0 and y >= 0 and x < 28 and y < 28:
				img.set_pixel(x, y, Color(0.4, 0.9, 0.98, 1))
	# Arrow head at end of arc
	for dx in range(-3, 4):
		for dy in range(-3, 4):
			var px := 14 + 10 + dx
			var py := 14 + dy
			if px >= 0 and py >= 0 and px < 28 and py < 28 and dx * dx + dy * dy < 10:
				img.set_pixel(px, py, Color(0.4, 0.9, 0.98, 1))
	var tex := ImageTexture.create_from_image(img)
	btn.icon = tex
	btn.expand_icon = false


func _on_throttle_changed(value: float) -> void:
	throttle_order = value


func _on_rudder_changed(value: float) -> void:
	pad_rudder = value


func _set_hold(action: String, down: bool) -> void:
	holds[action] = down


func _on_retry() -> void:
	get_tree().reload_current_scene()


func _held(action: String) -> bool:
	if bool(holds.get(action, false)):
		return true
	match action:
		"fwd":
			return Input.is_key_pressed(KEY_W)
		"back":
			return Input.is_key_pressed(KEY_S)
		"left":
			return Input.is_key_pressed(KEY_A)
		"right":
			return Input.is_key_pressed(KEY_D)
		"tleft":
			return Input.is_key_pressed(KEY_Q)
		"tright":
			return Input.is_key_pressed(KEY_E)
		"fire":
			return Input.is_key_pressed(KEY_SPACE)
	return false


func _process(delta: float) -> void:
	var dt := minf(delta, 0.033)
	sea_time += dt
	if sea_mat != null:
		sea_mat.set_shader_parameter("sea_time", sea_time)
	if outcome == "" and player.afloat:
		_steer_player(dt)
		_steer_enemies(dt)
		_separate()
		_update_shells(dt)
	for s in _all_ships():
		if not s.afloat:
			s.sink = minf(s.sink + dt, 1.2)
	_tick_floaters(dt)
	_tick_effects(dt)
	_sync_world(dt)
	_refresh_hud()
	if map_ctrl:
		map_ctrl.queue_redraw()


func _steer_player(dt: float) -> void:
	# Keyboard W/S set persistent throttle order (engine telegraph style).
	if Input.is_key_pressed(KEY_W):
		throttle_order = 1.0
		if virtual_pad:
			virtual_pad.set_throttle_order(1.0)
	elif Input.is_key_pressed(KEY_S):
		throttle_order = -1.0
		if virtual_pad:
			virtual_pad.set_throttle_order(-1.0)
	var turn := clampf(pad_rudder, -1.0, 1.0)
	if _held("left"):
		turn -= 1.0
	if _held("right"):
		turn += 1.0
	turn = clampf(turn, -1.0, 1.0)
	player.heading += turn * TURN_RATE * dt
	# throttle_order -1..1 → ahead MAX_SPEED or astern 0.42*MAX_SPEED
	var target := 0.0
	if throttle_order >= 0.0:
		target = throttle_order * MAX_SPEED
	else:
		target = throttle_order * MAX_SPEED * 0.42
	var rate := ACCEL if absf(throttle_order) > 0.01 else ACCEL * 0.0
	player.along = move_toward(player.along, target, rate * dt)
	_try_move(player, Vector2.from_angle(player.heading) * player.along * dt)
	if _held("tleft"):
		player.turret -= TURRET_RATE * dt
	if _held("tright"):
		player.turret += TURRET_RATE * dt
	player.cd = maxf(player.cd - dt, 0.0)
	if _held("fire") and player.cd <= 0.0:
		_spawn_shell(player, player.turret, true)
		player.cd = PLAYER_CD


func _steer_enemies(dt: float) -> void:
	for e in enemies:
		if not e.afloat:
			continue
		e.cd = maxf(e.cd - dt, 0.0)
		e.think -= dt
		if e.pos.distance_to(e.goal) < 100.0 or e.think <= 0.0:
			e.think = randf_range(3.5, 6.5)
			e.goal = _pick_goal()
		var desired := (e.goal - e.pos).angle()
		var diff := wrapf(desired - e.heading, -PI, PI)
		e.heading += clampf(diff, -ENEMY_TURN * dt, ENEMY_TURN * dt)
		var before := e.pos
		_try_move(e, Vector2.from_angle(e.heading) * ENEMY_SPEED * dt)
		if e.pos.distance_to(before) < 0.6:
			e.heading += 1.15 * dt * 8.0
			e.goal = _random_water()
		if player.afloat:
			var to_player := player.pos - e.pos
			var dist := to_player.length()
			if dist > 1.0 and dist < ENEMY_RANGE * 1.2:
				var td := wrapf(to_player.angle() - e.turret, -PI, PI)
				e.turret += clampf(td, -1.1 * dt, 1.1 * dt)
			else:
				var td_fwd := wrapf(e.heading - e.turret, -PI, PI)
				e.turret += clampf(td_fwd, -1.1 * dt, 1.1 * dt)
			var rel := wrapf(e.turret - e.heading, -PI, PI)
			if absf(rel) > 2.35:
				e.turret = e.heading + signf(rel) * 2.35
			if e.cd <= 0.0:
				var ang := absf(wrapf(to_player.angle() - e.heading, -PI, PI))
				if dist < ENEMY_RANGE and dist > 90.0 * SHIP_SCALE and ang < ENEMY_ARC:
					_spawn_shell(e, to_player.angle(), false)
					e.cd = ENEMY_CD
		else:
			var td_home := wrapf(e.heading - e.turret, -PI, PI)
			e.turret += clampf(td_home, -1.1 * dt, 1.1 * dt)


func _pick_goal() -> Vector2:
	if player.afloat and randf() < 0.7:
		var guess := player.pos + Vector2.from_angle(randf() * TAU) * randf_range(220, 520)
		if not _blocked(guess, 40.0 * SHIP_SCALE):
			return guess
	return _random_water()


func _try_move(s: Ship, delta: Vector2) -> void:
	if not _blocked(s.pos + delta, s.radius * 0.72):
		s.pos += delta
		return
	var x_only := Vector2(delta.x, 0.0)
	if not _blocked(s.pos + x_only, s.radius * 0.72):
		s.pos += x_only
		return
	var y_only := Vector2(0.0, delta.y)
	if not _blocked(s.pos + y_only, s.radius * 0.72):
		s.pos += y_only


func _separate() -> void:
	var all := _all_ships()
	for i in all.size():
		for j in range(i + 1, all.size()):
			var a: Ship = all[i]
			var b: Ship = all[j]
			if not a.afloat or not b.afloat:
				continue
			var d := a.pos - b.pos
			var dist := d.length()
			var need := a.radius + b.radius
			if dist < need and dist > 0.01:
				var push := d.normalized() * (need - dist) * 0.5
				if not _blocked(a.pos + push, 8.0 * SHIP_SCALE):
					a.pos += push
				if not _blocked(b.pos - push, 8.0 * SHIP_SCALE):
					b.pos -= push


func _spawn_shell(owner: Ship, angle: float, from_player: bool) -> void:
	var sh := Shell.new()
	sh.owner = owner
	sh.from_player = from_player
	sh.dir = Vector2.from_angle(angle)
	sh.pos = owner.pos + sh.dir * (owner.radius + 16.0 * SHIP_SCALE)
	sh.life = SHELL_LIFE
	sh.gun_y = _sea_height(owner.pos) + WATERLINE_LIFT + maxf(5.5 * SHIP_SCALE, owner.gun_y * 0.75)
	var mi := MeshInstance3D.new()
	mi.mesh = shell_mesh
	mi.material_override = shell_mat_player if from_player else shell_mat_enemy
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	sh.node = mi
	shells.append(sh)
	_sync_shell(sh)


func _update_shells(dt: float) -> void:
	for i in range(shells.size() - 1, -1, -1):
		var sh: Shell = shells[i]
		var dest := sh.pos + sh.dir * SHELL_SPEED * dt
		var best := 2.0
		var hit: Ship = null
		for other in _all_ships():
			if other == sh.owner or not other.afloat:
				continue
			var t := _seg_circle(sh.pos, dest, other.pos, other.radius)
			if t >= 0.0 and t < best:
				best = t
				hit = other
		for poly in islands:
			var ti := _seg_poly(sh.pos, dest, poly)
			if ti >= 0.0 and ti < best:
				best = ti
				hit = null
		if best <= 1.0:
			var at := sh.pos.lerp(dest, best)
			if hit != null:
				_damage(hit, PLAYER_DMG if sh.from_player else ENEMY_DMG)
				_spawn_flash(at, _sea_height(hit.pos) + WATERLINE_LIFT + hit.gun_y)
			else:
				_spawn_splash(at)
			_free_shell(i)
			if outcome != "":
				return
		else:
			sh.pos = dest
			sh.life -= dt
			var outside := sh.pos.x < -40.0 or sh.pos.y < -40.0 or sh.pos.x > WORLD_W + 40.0 or sh.pos.y > WORLD_H + 40.0
			if sh.life <= 0.0 or outside:
				if sh.life <= 0.0 and not outside:
					_spawn_splash(sh.pos)
				_free_shell(i)


func _free_shell(i: int) -> void:
	var sh: Shell = shells[i]
	if sh.node != null:
		sh.node.queue_free()
		sh.node = null
	shells.remove_at(i)


func _damage(s: Ship, amount: int) -> void:
	if not s.afloat or outcome != "":
		return
	s.hp = maxi(s.hp - amount, 0)
	if s.hp == 0:
		_sink(s)


func _sink(s: Ship) -> void:
	s.afloat = false
	s.along = 0.0
	s.sink = 0.001
	var lab := Label3D.new()
	lab.text = "擊沉"
	lab.font = font
	lab.font_size = 48
	lab.modulate = Color(1.0, 0.96, 0.82, 1.0)
	lab.outline_modulate = Color(0.02, 0.05, 0.08, 0.92)
	lab.outline_size = 16
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = true
	lab.pixel_size = 0.008
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.position = Vector3(s.pos.x, 26.0, s.pos.y)
	add_child(lab)
	floaters.append({"node": lab, "pos": s.pos, "t": 0.0})
	if s.player:
		outcome = "lose"
	elif _enemies_all_sunk():
		outcome = "win"


func _enemies_all_sunk() -> bool:
	for e in enemies:
		if e.afloat:
			return false
	return true


func _tick_floaters(dt: float) -> void:
	for i in range(floaters.size() - 1, -1, -1):
		floaters[i]["t"] = float(floaters[i]["t"]) + dt
		var t := float(floaters[i]["t"])
		var lab: Label3D = floaters[i]["node"]
		var pos: Vector2 = floaters[i]["pos"]
		lab.position = Vector3(pos.x, 26.0 + t * 20.0, pos.y)
		var col := lab.modulate
		col.a = clampf(1.0 - t / 1.15, 0.0, 1.0)
		lab.modulate = col
		if t > 1.15:
			lab.queue_free()
			floaters.remove_at(i)


func _spawn_splash(at: Vector2) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, _sea_height(at) + WATERLINE_LIFT * 0.35 + 0.4, at.y)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = splash_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.84, 0.94, 0.98, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var spray := MeshInstance3D.new()
	spray.name = "Spray"
	spray.mesh = flash_mesh
	spray.position = Vector3(0.0, 2.4, 0.0)
	spray.scale = Vector3(0.55, 1.3, 0.55) * SHIP_SCALE
	spray.material_override = mat
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spray)
	add_child(root)
	effects.append({"root": root, "ring": ring, "mat": mat, "light": null, "t": 0.0, "life": 0.42, "kind": "splash"})


func _spawn_flash(at: Vector2, height: float) -> void:
	var root := Node3D.new()
	root.position = Vector3(at.x, height, at.y)
	var mi := MeshInstance3D.new()
	mi.name = "Flash"
	mi.mesh = flash_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.38, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.2)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.72, 0.38)
	light.light_energy = 2.6
	light.omni_range = 55.0 * SHIP_SCALE
	light.shadow_enabled = false
	root.add_child(light)
	add_child(root)
	effects.append({"root": root, "ring": mi, "mat": mat, "light": light, "t": 0.0, "life": 0.28, "kind": "flash"})


func _tick_effects(dt: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["t"] = float(effects[i]["t"]) + dt
		var t := float(effects[i]["t"])
		var life := float(effects[i]["life"])
		var k := clampf(t / life, 0.0, 1.0)
		var root: Node3D = effects[i]["root"]
		var ring: MeshInstance3D = effects[i]["ring"]
		var mat: StandardMaterial3D = effects[i]["mat"]
		var kind := str(effects[i]["kind"])
		var col := mat.albedo_color
		col.a = (0.85 if kind == "splash" else 0.95) * (1.0 - k)
		mat.albedo_color = col
		if kind == "splash":
			var sc := (3.2 + k * 22.0) * SHIP_SCALE
			ring.scale = Vector3(sc, sc * 0.0, sc)
			var spray := root.get_node_or_null("Spray") as MeshInstance3D
			if spray != null:
				spray.position.y = (2.0 + k * 7.0) * SHIP_SCALE
				spray.scale = Vector3(0.4 + k * 1.4, 1.2 + k * 2.4, 0.4 + k * 1.4) * SHIP_SCALE
		else:
			var fs := (0.7 + k * 2.4) * SHIP_SCALE
			ring.scale = Vector3(fs, fs, fs)
			var light: OmniLight3D = effects[i]["light"]
			if light != null:
				light.light_energy = 2.6 * (1.0 - k)
		if t >= life:
			root.queue_free()
			effects.remove_at(i)


func _sync_world(dt: float) -> void:
	for s in _all_ships():
		_sync_ship(s)
	for sh in shells:
		_sync_shell(sh)
	_sync_aim()
	_place_camera(dt)


func _sea_height(xz: Vector2) -> float:
	# Must match shaders/sea.gdshader sea_h().
	var h := 0.0
	h += sin(xz.dot(Vector2(0.0085, 0.0035)) + sea_time * 0.75) * 0.70
	h += sin(xz.dot(Vector2(-0.0045, 0.0105)) + sea_time * 1.05) * 0.40
	h += sin(xz.dot(Vector2(0.016, -0.012)) + sea_time * 1.45) * 0.18
	return h


func _sea_slope(xz: Vector2) -> Vector2:
	# Returns (dH/dx, dH/dz) with the same sample span as the shader normal.
	var e := 20.0
	var h := _sea_height(xz)
	var hx := _sea_height(xz + Vector2(e, 0.0))
	var hz := _sea_height(xz + Vector2(0.0, e))
	return Vector2((hx - h) / e, (hz - h) / e)


func _sync_ship(s: Ship) -> void:
	if s.body == null:
		return
	# Ride the same swell the sea shader draws; local y≈0 is the design waterline.
	# Sample along the hull so long ships clear crests under bow/stern, not only midships.
	var fwd2 := Vector2.from_angle(s.heading)
	var half := (52.0 if s.kind == 0 else (38.0 if s.kind == 1 else 30.0)) * SHIP_SCALE
	var y := maxf(
		_sea_height(s.pos),
		maxf(_sea_height(s.pos + fwd2 * half), _sea_height(s.pos - fwd2 * half))
	) + WATERLINE_LIFT
	var slope := _sea_slope(s.pos)
	var right := Vector2(-fwd2.y, fwd2.x)
	var slope_fwd := slope.dot(fwd2)
	var slope_right := slope.dot(right)
	# Tiny attitude only — larger pitch digs the long BB bow under the swell.
	var pitch := clampf(atan(-slope_fwd) * 0.18, -0.012, 0.012)
	var roll := clampf(atan(slope_right) * 0.18, -0.016, 0.016)
	if not s.afloat:
		y -= s.sink * 20.0
		pitch += s.sink * 0.5
	s.body.position = Vector3(s.pos.x, y, s.pos.y)
	s.body.rotation = Vector3(pitch, -s.heading, roll)
	s.body.visible = s.sink < 1.15
	var local_yaw := wrapf(s.heading - s.turret, -PI, PI)
	for piv in s.turret_pivots:
		piv.rotation.y = local_yaw
	_update_wake_ribbon(s)


func _ship_speed(s: Ship) -> float:
	if not s.afloat:
		return 0.0
	if s.player:
		return absf(s.along)
	return ENEMY_SPEED


func _stern_world(s: Ship) -> Vector2:
	var aft := (82.0 if s.kind == 0 else (62.0 if s.kind == 1 else 50.0)) * SHIP_SCALE
	return s.pos + Vector2.from_angle(s.heading + PI) * aft


func _update_wake_ribbon(s: Ship) -> void:
	if s.wake == null:
		return
	var speed := _ship_speed(s)
	var moving := s.afloat and speed > 18.0
	if not moving:
		s.wake_trail.clear()
		s.wake.visible = false
		s.wake.mesh = null
		return
	var stern := _stern_world(s)
	var sample := 7.5 * SHIP_SCALE
	if s.wake_trail.is_empty() or s.wake_trail[s.wake_trail.size() - 1].distance_to(stern) >= sample:
		s.wake_trail.append(stern)
	var max_len := lerpf(55.0, 210.0, clampf(speed / MAX_SPEED, 0.0, 1.0)) * SHIP_SCALE
	if not s.player:
		max_len = lerpf(50.0, 140.0, clampf(speed / MAX_SPEED, 0.0, 1.0)) * SHIP_SCALE
	# Trim oldest points so path length <= max_len.
	while s.wake_trail.size() > 2:
		var total := 0.0
		for i in range(1, s.wake_trail.size()):
			total += s.wake_trail[i].distance_to(s.wake_trail[i - 1])
		if total <= max_len:
			break
		s.wake_trail.remove_at(0)
	# Cap point count for mesh cost.
	while s.wake_trail.size() > 36:
		s.wake_trail.remove_at(0)
	# Keep the newest point glued to the live stern.
	if not s.wake_trail.is_empty():
		s.wake_trail[s.wake_trail.size() - 1] = stern
	_rebuild_wake_mesh(s, speed)


func _rebuild_wake_mesh(s: Ship, speed: float) -> void:
	var trail: Array[Vector2] = s.wake_trail
	var n := trail.size()
	if n < 2:
		s.wake.visible = false
		s.wake.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var beam0: float = maxf(4.0, s.wake_beam * SHIP_SCALE)
	var strength := clampf(speed / MAX_SPEED, 0.2, 1.0)
	if not s.player:
		strength = clampf(speed / MAX_SPEED, 0.25, 0.85)
	for i in range(n - 1):
		var p0: Vector2 = trail[i]
		var p1: Vector2 = trail[i + 1]
		var u0 := float(i) / float(n - 1)
		var u1 := float(i + 1) / float(n - 1)
		# u=0 oldest (far) → wide + faded; u=1 newest (stern) → narrow + brighter
		var tang0: Vector2
		var tang1: Vector2
		if i == 0:
			tang0 = (trail[1] - trail[0])
		else:
			tang0 = (trail[i + 1] - trail[i - 1])
		if i + 2 < n:
			tang1 = (trail[i + 2] - trail[i])
		else:
			tang1 = (trail[n - 1] - trail[n - 2])
		if tang0.length_squared() < 0.0001:
			tang0 = Vector2.RIGHT
		if tang1.length_squared() < 0.0001:
			tang1 = tang0
		tang0 = tang0.normalized()
		tang1 = tang1.normalized()
		var perp0 := Vector2(-tang0.y, tang0.x)
		var perp1 := Vector2(-tang1.y, tang1.x)
		var w0 := lerpf(beam0 * 2.65, beam0 * 0.2, u0)
		var w1 := lerpf(beam0 * 2.65, beam0 * 0.2, u1)
		var a0 := pow(u0, 0.95) * (0.26 + 0.52 * strength)
		var a1 := pow(u1, 0.95) * (0.26 + 0.52 * strength)
		var y0 := _sea_height(p0) + 0.55
		var y1 := _sea_height(p1) + 0.55
		var l0 := Vector3(p0.x - perp0.x * w0, y0, p0.y - perp0.y * w0)
		var r0 := Vector3(p0.x + perp0.x * w0, y0, p0.y + perp0.y * w0)
		var l1 := Vector3(p1.x - perp1.x * w1, y1, p1.y - perp1.y * w1)
		var r1 := Vector3(p1.x + perp1.x * w1, y1, p1.y + perp1.y * w1)
		# Soft V: brighter foam banks, faded outer edge + quieter center.
		var m0 := (l0 + r0) * 0.5
		var m1 := (l1 + r1) * 0.5
		var q0 := l0.lerp(m0, 0.55)
		var q1 := l1.lerp(m1, 0.55)
		var p0b := r0.lerp(m0, 0.55)
		var p1b := r1.lerp(m1, 0.55)
		var c_edge := Color(0.86, 0.96, 1.0, 0.0)
		var c_bank0 := Color(0.94, 0.99, 1.0, a0)
		var c_bank1 := Color(0.94, 0.99, 1.0, a1)
		var c_mid0 := Color(0.9, 0.97, 1.0, a0 * 0.28)
		var c_mid1 := Color(0.9, 0.97, 1.0, a1 * 0.28)
		# left bank
		_wake_tri(st, l0, q0, q1, c_edge, c_bank0, c_bank1)
		_wake_tri(st, l0, q1, l1, c_edge, c_bank1, c_edge)
		_wake_tri(st, q0, m0, m1, c_bank0, c_mid0, c_mid1)
		_wake_tri(st, q0, m1, q1, c_bank0, c_mid1, c_bank1)
		# right bank
		_wake_tri(st, p0b, r0, r1, c_bank0, c_edge, c_edge)
		_wake_tri(st, p0b, r1, p1b, c_bank0, c_edge, c_bank1)
		_wake_tri(st, m0, p0b, p1b, c_mid0, c_bank0, c_bank1)
		_wake_tri(st, m0, p1b, m1, c_mid0, c_bank1, c_mid1)
	s.wake.mesh = st.commit()
	s.wake.visible = true


func _wake_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 0.00001:
		return
	n = n.normalized()
	# Prefer upward facing.
	if n.y < 0.0:
		n = -n
		st.set_normal(n)
		st.set_color(ca)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(cc)
		st.add_vertex(c)
		st.set_normal(n)
		st.set_color(cb)
		st.add_vertex(b)
	else:
		st.set_normal(n)
		st.set_color(ca)
		st.add_vertex(a)
		st.set_normal(n)
		st.set_color(cb)
		st.add_vertex(b)
		st.set_normal(n)
		st.set_color(cc)
		st.add_vertex(c)


func _sync_shell(sh: Shell) -> void:
	if sh.node == null:
		return
	sh.node.position = Vector3(sh.pos.x, sh.gun_y, sh.pos.y)
	var dir := Vector3(sh.dir.x, 0.0, sh.dir.y)
	if dir.length_squared() > 0.0001:
		sh.node.basis = Basis.looking_at(dir, Vector3.UP)


func _sync_aim() -> void:
	var show := player != null and player.afloat and outcome == ""
	var fwd := Vector3(cos(player.turret), 0.0, sin(player.turret))
	var origin := Vector3(player.pos.x, _sea_height(player.pos) + WATERLINE_LIFT + 2.2 * SHIP_SCALE, player.pos.y)
	var dists: Array[float] = [42.0, 90.0, 146.0, 210.0, 280.0, 360.0]
	for i in aim_marks.size():
		var mark: MeshInstance3D = aim_marks[i]
		mark.visible = show
		if show:
			mark.position = origin + fwd * dists[i]
			mark.basis = Basis.looking_at(fwd, Vector3.UP)



func _place_camera(dt: float) -> void:
	if cam == null or player == null:
		return
	var fwd := Vector3(cos(player.heading), 0.0, sin(player.heading))
	var focus := Vector3(player.pos.x, _sea_height(player.pos) + WATERLINE_LIFT + 5.0 * SHIP_SCALE, player.pos.y)
	# Lower follow angle + slight side offset so freeboard reads from stern-ish views.
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var desired := focus - fwd * 210.0 + right * 42.0 + Vector3(0.0, 58.0, 0.0)
	var look := focus + fwd * 100.0 + Vector3(0.0, 4.0, 0.0)
	if not cam_ready:
		cam.position = desired
		cam_ready = true
	else:
		var k := 1.0 - exp(-3.4 * dt)
		cam.position = cam.position.lerp(desired, k)
	if cam.position.distance_squared_to(look) > 4.0:
		cam.look_at(look, Vector3.UP)


func _refresh_hud() -> void:
	var ca_left := 0
	var dd_left := 0
	for e in enemies:
		if e.afloat:
			if e.kind == 1:
				ca_left += 1
			else:
				dd_left += 1
	var knots := player.along / MAX_SPEED * MAX_KNOTS
	var turret_rel := wrapf(player.turret - player.heading, -PI, PI)
	if naval_panel:
		naval_panel.update_stats(player.hp, player.max_hp, knots, turret_rel, ca_left, dd_left, throttle_order)
	if fire_pad:
		var ready := 1.0 if PLAYER_CD <= 0.001 else clampf(1.0 - player.cd / PLAYER_CD, 0.0, 1.0)
		fire_pad.set_reload(ready)
		fire_pad.set_turret_bearing(turret_rel)
		fire_pad.sync_keyboard(
			Input.is_key_pressed(KEY_SPACE),
			Input.is_key_pressed(KEY_Q),
			Input.is_key_pressed(KEY_E)
		)
	if virtual_pad:
		var kbd_t := 0.0
		if Input.is_key_pressed(KEY_W):
			kbd_t = 1.0
		elif Input.is_key_pressed(KEY_S):
			kbd_t = -1.0
		var kbd_r := 0.0
		if Input.is_key_pressed(KEY_A):
			kbd_r -= 1.0
		if Input.is_key_pressed(KEY_D):
			kbd_r += 1.0
		virtual_pad.set_keyboard_visual(kbd_t, kbd_r)
	var show := outcome != ""
	dim.visible = show
	dim.mouse_filter = Control.MOUSE_FILTER_STOP if show else Control.MOUSE_FILTER_IGNORE
	banner.visible = show
	if outcome == "win":
		banner.text = "勝利"
		retry.visible = false
	elif outcome == "lose":
		banner.text = "戰艦沉沒"
		retry.visible = true


func _all_ships() -> Array[Ship]:
	var all: Array[Ship] = [player]
	all.append_array(enemies)
	return all


func _random_water() -> Vector2:
	for _i in 24:
		var p := Vector2(randf_range(180, WORLD_W - 180), randf_range(180, WORLD_H - 180))
		if not _blocked(p, 50.0 * SHIP_SCALE):
			return p
	return Vector2(WORLD_W * 0.5, WORLD_H * 0.5)


func _blocked(p: Vector2, clearance: float) -> bool:
	if p.x < clearance or p.y < clearance or p.x > WORLD_W - clearance or p.y > WORLD_H - clearance:
		return true
	var samples: Array[Vector2] = [p]
	if clearance > 1.0:
		samples.append(p + Vector2(clearance, 0))
		samples.append(p + Vector2(-clearance, 0))
		samples.append(p + Vector2(0, clearance))
		samples.append(p + Vector2(0, -clearance))
	for poly in islands:
		for s in samples:
			if _point_in_poly(s, poly):
				return true
	return false


func _point_in_poly(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[j]
		if (a.y > p.y) != (b.y > p.y):
			var xint := (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x
			if p.x < xint:
				inside = not inside
		j = i
	return inside


func _seg_poly(a: Vector2, b: Vector2, poly: PackedVector2Array) -> float:
	var best := -1.0
	var n := poly.size()
	for i in n:
		var t := _seg_t(a, b, poly[i], poly[(i + 1) % n])
		if t >= 0.0 and (best < 0.0 or t < best):
			best = t
	return best


func _seg_t(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var r := b - a
	var s := d - c
	var den := r.cross(s)
	if absf(den) < 0.00001:
		return -1.0
	var t := (c - a).cross(s) / den
	var u := (c - a).cross(r) / den
	if t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0:
		return t
	return -1.0


func _seg_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> float:
	var d := b - a
	var f := a - center
	var qa := d.dot(d)
	if qa < 0.00001:
		return -1.0
	var qb := 2.0 * f.dot(d)
	var qc := f.dot(f) - radius * radius
	var disc := qb * qb - 4.0 * qa * qc
	if disc < 0.0:
		return -1.0
	var sd := sqrt(disc)
	var t1 := (-qb - sd) / (2.0 * qa)
	var t2 := (-qb + sd) / (2.0 * qa)
	var best := -1.0
	if t1 >= 0.0 and t1 <= 1.0:
		best = t1
	if t2 >= 0.0 and t2 <= 1.0 and (best < 0.0 or t2 < best):
		best = t2
	return best


func draw_minimap(c: Control) -> void:
	var sz := c.size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.06, 0.22, 0.38))
	var sx := sz.x / WORLD_W
	var sy := sz.y / WORLD_H
	for poly in islands:
		var mini := PackedVector2Array()
		for p in poly:
			mini.append(Vector2(p.x * sx, p.y * sy))
		c.draw_colored_polygon(mini, Color(0.55, 0.62, 0.40))
	for e in enemies:
		if e.sink >= 1.15:
			continue
		var dot := Color(0.92, 0.34, 0.28, 1.0 if e.afloat else 0.35)
		var dot_r := (4.2 if e.kind == 1 else 2.5) * SHIP_SCALE
		c.draw_circle(Vector2(e.pos.x * sx, e.pos.y * sy), maxf(1.6, dot_r), dot)
	if player.sink < 1.15:
		c.draw_circle(Vector2(player.pos.x * sx, player.pos.y * sy), maxf(2.2, 4.0 * SHIP_SCALE), Color(0.96, 0.86, 0.32))
	c.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.78, 0.86, 0.82, 0.85), false, 1.5)


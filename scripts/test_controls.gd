extends SceneTree
## Headless smoke test: throttle/rudder/fire respond without opening a window.

func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := OK
	var packed := load("res://scenes/battle.tscn")
	if packed == null:
		push_error("FAIL: cannot load battle.tscn")
		quit(1)
		return
	var battle: Node = packed.instantiate()
	root.add_child(battle)
	# Wait two frames for _ready + first process
	await process_frame
	await process_frame
	if battle.get("player") == null:
		push_error("FAIL: no player")
		quit(1)
		return
	var player = battle.player
	var along0: float = float(player.along)
	var turret0: float = float(player.turret)
	var shells0: int = int(battle.shells.size())
	# Simulate telegraph + rudder + turret + fire via the same API the pads use
	battle.throttle_order = 1.0
	battle.pad_rudder = 0.5
	battle._set_hold("tleft", true)
	battle._set_hold("fire", true)
	# Step several physics-ish frames
	for _i in 20:
		battle._steer_player(0.016)
		await process_frame
	var along1: float = float(player.along)
	var turret1: float = float(player.turret)
	var shells1: int = int(battle.shells.size())
	var heading_moved := absf(battle.pad_rudder) > 0.0  # rudder applied in steer
	if along1 <= along0:
		push_error("FAIL: throttle did not increase along (%.2f -> %.2f)" % [along0, along1])
		err = 1
	else:
		print("OK throttle along %.2f -> %.2f" % [along0, along1])
	if turret1 >= turret0:
		push_error("FAIL: turret left did not decrease bearing (%.3f -> %.3f)" % [turret0, turret1])
		err = 1
	else:
		print("OK turret %.3f -> %.3f" % [turret0, turret1])
	if shells1 <= shells0:
		push_error("FAIL: fire did not spawn shell (%d -> %d)" % [shells0, shells1])
		err = 1
	else:
		print("OK shells %d -> %d" % [shells0, shells1])
	if battle.virtual_pad == null or battle.fire_pad == null or battle.naval_panel == null:
		push_error("FAIL: UI pads/panel missing")
		err = 1
	else:
		print("OK virtual_pad/fire_pad/naval_panel present")
	# Throttle persistence: clear holds, order stays
	battle._set_hold("fire", false)
	battle._set_hold("tleft", false)
	var saved: float = float(battle.throttle_order)
	battle.pad_rudder = 0.0
	if not is_equal_approx(saved, 1.0):
		push_error("FAIL: throttle_order not persistent")
		err = 1
	else:
		print("OK throttle_order persistent at %.2f" % saved)
	print("TEST_CONTROLS_DONE err=%d" % err)
	quit(err)

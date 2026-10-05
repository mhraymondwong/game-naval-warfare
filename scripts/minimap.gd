extends Control

var battle = null

func _draw() -> void:
	if battle != null:
		battle.draw_minimap(self)

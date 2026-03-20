extends CanvasLayer

@onready var target_indicator: TextureRect = $target_indicator

var player: Node = null


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	target_indicator.hide()


func _process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		target_indicator.hide()
		return

	if not player.has_method("get_lock_target"):
		target_indicator.hide()
		return

	var locked_enemy: Node3D = player.get_lock_target()
	if locked_enemy == null or not is_instance_valid(locked_enemy):
		target_indicator.hide()
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null or camera.is_position_behind(locked_enemy.global_position):
		target_indicator.hide()
		return

	var screen_pos: Vector2 = camera.unproject_position(locked_enemy.global_position)
	target_indicator.global_position = screen_pos - (target_indicator.size * 0.5)
	target_indicator.show()

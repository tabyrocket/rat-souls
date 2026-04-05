extends ProgressBar

@export var world_offset: Vector3 = Vector3(0.0, 3.1, 0.0)
@export var smooth_speed: float = 8.0

var enemy: Node3D = null
var health_max: float = 1.0
var shown_health: float = 0.0


func _ready() -> void:
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	step = 0.01
	enemy = get_parent() as Node3D

	if enemy == null:
		hide()
		set_process(false)
		return

	_apply_health_immediately()
	_update_screen_position()


func _process(delta: float) -> void:
	if enemy == null or not is_instance_valid(enemy):
		queue_free()
		return

	_update_health(delta)
	_update_screen_position()


func _apply_health_immediately() -> void:
	var health: float = _get_enemy_health()
	health_max = max(health_max, max(health, 1.0))
	shown_health = health
	max_value = health_max
	value = clamp(shown_health, 0.0, health_max)


func _update_health(delta: float) -> void:
	var health: float = _get_enemy_health()
	health_max = max(health_max, max(health, 1.0))
	shown_health = move_toward(shown_health, health, smooth_speed * delta * health_max)
	max_value = health_max
	value = clamp(shown_health, 0.0, health_max)


func _update_screen_position() -> void:
	if enemy == null:
		hide()
		return

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		hide()
		return

	var world_position: Vector3 = enemy.global_position + world_offset
	if camera.is_position_behind(world_position):
		hide()
		return

	var screen_position: Vector2 = camera.unproject_position(world_position)
	global_position = screen_position - (size * 0.5)
	show()


func _get_enemy_health() -> float:
	if enemy == null:
		return 0.0

	var health_value: Variant = enemy.get("health")
	if typeof(health_value) == TYPE_NIL:
		return 0.0

	return float(health_value)
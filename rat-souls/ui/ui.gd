extends CanvasLayer

@onready var target_indicator: TextureRect = $target_indicator
@onready var health_bar: ProgressBar = $HBoxContainer/VBoxContainer/HealthBar
@onready var stamina_bar: ProgressBar = $HBoxContainer/VBoxContainer/StaminaBar

const BAR_SMOOTH_SPEED: float = 8.0

var player: Node = null
var health_max: float = 1.0
var shown_health: float = 0.0
var shown_stamina: float = 0.0


func _ready() -> void:
	_refresh_player_reference()
	health_bar.step = 0.01
	stamina_bar.step = 0.01
	target_indicator.hide()
	_apply_stats_immediately()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_refresh_player_reference()

	_update_bars(delta)
	_update_target_indicator()


func _refresh_player_reference() -> void:
	player = get_tree().get_first_node_in_group("player")


func _apply_stats_immediately() -> void:
	if player == null or not is_instance_valid(player):
		health_bar.max_value = health_max
		health_bar.value = 0.0
		stamina_bar.max_value = 100.0
		stamina_bar.value = 0.0
		return

	var health: float = float(player.get("health"))
	var stamina: float = float(player.get("stamina"))
	var stamina_max: float = max(float(player.get("stamina_max")), 1.0)

	health_max = max(health_max, max(health, 1.0))
	shown_health = health
	shown_stamina = stamina

	health_bar.max_value = health_max
	health_bar.value = clamp(shown_health, 0.0, health_max)
	stamina_bar.max_value = stamina_max
	stamina_bar.value = clamp(shown_stamina, 0.0, stamina_max)


func _update_bars(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		shown_health = move_toward(shown_health, 0.0, BAR_SMOOTH_SPEED * delta * max(health_max, 1.0))
		shown_stamina = move_toward(shown_stamina, 0.0, BAR_SMOOTH_SPEED * delta * max(stamina_bar.max_value, 1.0))
		health_bar.max_value = health_max
		health_bar.value = clamp(shown_health, 0.0, health_max)
		stamina_bar.value = clamp(shown_stamina, 0.0, stamina_bar.max_value)
		return

	var health: float = float(player.get("health"))
	var stamina: float = float(player.get("stamina"))
	var stamina_max: float = max(float(player.get("stamina_max")), 1.0)

	health_max = max(health_max, max(health, 1.0))
	shown_health = move_toward(shown_health, health, BAR_SMOOTH_SPEED * delta * health_max)
	shown_stamina = move_toward(shown_stamina, stamina, BAR_SMOOTH_SPEED * delta * stamina_max)

	health_bar.max_value = health_max
	health_bar.value = clamp(shown_health, 0.0, health_max)
	stamina_bar.max_value = stamina_max
	stamina_bar.value = clamp(shown_stamina, 0.0, stamina_max)


func _update_target_indicator() -> void:
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

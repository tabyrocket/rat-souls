extends CanvasLayer

@onready var target_indicator: TextureRect = $target_indicator
@onready var health_bar: ProgressBar = $HBoxContainer/VBoxContainer/HealthBar
@onready var stamina_bar: ProgressBar = $HBoxContainer/VBoxContainer/StaminaBar
@onready var pause_panel: Control = $PausePanel
@onready var settings_panel: Control = $SettingsPanel
@onready var resume_button: Button = $PausePanel/VBoxContainer/ResumeButton
@onready var settings_button: Button = $PausePanel/VBoxContainer/SettingsButton
@onready var exit_button: Button = $PausePanel/VBoxContainer/ExitButton
@onready var back_button: Button = $SettingsPanel/VBoxContainer/CenterContainer/BackButton
@onready var mouse_sensitivity_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/SensitivitySettings/VBoxContainer/MouseSens/HSlider
@onready var controller_sensitivity_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/SensitivitySettings/VBoxContainer/ContSens/HSlider
@onready var master_volume_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/VolumeSettings/VBoxContainer/MasterVol/HSlider
@onready var bgm_volume_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/VolumeSettings/VBoxContainer/BGMusic/HSlider
@onready var sfx_volume_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/VolumeSettings/VBoxContainer/SFX/HSlider

const BAR_SMOOTH_SPEED: float = 8.0
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const BUS_MASTER: StringName = &"Master"
const BUS_BGM: StringName = &"BGM"
const BUS_SFX: StringName = &"SFX"
const MIN_LINEAR_VOLUME: float = 0.0001

var player: Node = null
var health_max: float = 1.0
var shown_health: float = 0.0
var shown_stamina: float = 0.0
var base_mouse_sensitivity: float = 0.0
var base_controller_sensitivity: float = 0.0
var base_master_volume_linear: float = 1.0
var base_bgm_volume_linear: float = 1.0
var base_sfx_volume_linear: float = 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_player_reference()
	_cache_player_sensitivity_defaults()
	_cache_bus_volume_defaults()
	_connect_menu_signals()
	health_bar.step = 0.01
	stamina_bar.step = 0.01
	pause_panel.hide()
	settings_panel.hide()
	mouse_sensitivity_slider.value = 1.0
	controller_sensitivity_slider.value = 1.0
	master_volume_slider.value = 1.0
	bgm_volume_slider.value = 1.0
	sfx_volume_slider.value = 1.0
	_apply_sensitivity_settings()
	_apply_volume_settings()
	target_indicator.hide()
	_apply_stats_immediately()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_refresh_player_reference()

	_update_bars(delta)
	_update_target_indicator()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return

	get_viewport().set_input_as_handled()
	if get_tree().paused:
		_resume_game()
	else:
		_pause_game()


func _refresh_player_reference() -> void:
	var refreshed_player: Node = get_tree().get_first_node_in_group("player")
	if refreshed_player == player:
		return

	player = refreshed_player
	_cache_player_sensitivity_defaults()
	_apply_sensitivity_settings()


func _cache_player_sensitivity_defaults() -> void:
	if player == null or not is_instance_valid(player):
		return

	base_mouse_sensitivity = float(player.get("mouse_sensitivity"))
	base_controller_sensitivity = float(player.get("controller_look_sensitivity"))


func _cache_bus_volume_defaults() -> void:
	base_master_volume_linear = _get_bus_volume_linear(BUS_MASTER)
	base_bgm_volume_linear = _get_bus_volume_linear(BUS_BGM)
	base_sfx_volume_linear = _get_bus_volume_linear(BUS_SFX)


func _get_bus_volume_linear(bus_name: StringName) -> float:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(bus_index))


func _apply_bus_volume_multiplier(bus_name: StringName, base_linear: float, multiplier: float) -> void:
	var bus_index: int = AudioServer.get_bus_index(bus_name)
	if bus_index == -1:
		return

	if multiplier <= 0.0:
		AudioServer.set_bus_volume_db(bus_index, -80.0)
		return

	var linear_volume: float = max(base_linear * multiplier, MIN_LINEAR_VOLUME)
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(linear_volume))


func _apply_sensitivity_settings() -> void:
	if player == null or not is_instance_valid(player):
		return

	player.set("mouse_sensitivity", base_mouse_sensitivity * mouse_sensitivity_slider.value)
	player.set("controller_look_sensitivity", base_controller_sensitivity * controller_sensitivity_slider.value)


func _apply_volume_settings() -> void:
	_apply_bus_volume_multiplier(BUS_MASTER, base_master_volume_linear, master_volume_slider.value)
	_apply_bus_volume_multiplier(BUS_BGM, base_bgm_volume_linear, bgm_volume_slider.value)
	_apply_bus_volume_multiplier(BUS_SFX, base_sfx_volume_linear, sfx_volume_slider.value)


func _connect_menu_signals() -> void:
	resume_button.pressed.connect(_on_resume_button_pressed)
	settings_button.pressed.connect(_on_settings_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	mouse_sensitivity_slider.value_changed.connect(_on_mouse_sensitivity_slider_value_changed)
	controller_sensitivity_slider.value_changed.connect(_on_controller_sensitivity_slider_value_changed)
	master_volume_slider.value_changed.connect(_on_master_volume_slider_value_changed)
	bgm_volume_slider.value_changed.connect(_on_bgm_volume_slider_value_changed)
	sfx_volume_slider.value_changed.connect(_on_sfx_volume_slider_value_changed)


func _pause_game() -> void:
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	settings_panel.hide()
	pause_panel.show()
	call_deferred("_focus_resume_button")


func _focus_resume_button() -> void:
	if pause_panel.visible:
		resume_button.grab_focus()


func _resume_game() -> void:
	settings_panel.hide()
	pause_panel.hide()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _on_resume_button_pressed() -> void:
	_resume_game()


func _on_settings_button_pressed() -> void:
	settings_panel.show()
	mouse_sensitivity_slider.grab_focus()


func _on_back_button_pressed() -> void:
	settings_panel.hide()
	settings_button.grab_focus()


func _on_exit_button_pressed() -> void:
	push_warning("Main menu scene does not exist yet. Placeholder path: %s" % MAIN_MENU_SCENE_PATH)
	# get_tree().paused = false
	# get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_mouse_sensitivity_slider_value_changed(_value: float) -> void:
	_apply_sensitivity_settings()


func _on_controller_sensitivity_slider_value_changed(_value: float) -> void:
	_apply_sensitivity_settings()


func _on_master_volume_slider_value_changed(value: float) -> void:
	_apply_bus_volume_multiplier(BUS_MASTER, base_master_volume_linear, value)


func _on_bgm_volume_slider_value_changed(value: float) -> void:
	_apply_bus_volume_multiplier(BUS_BGM, base_bgm_volume_linear, value)


func _on_sfx_volume_slider_value_changed(value: float) -> void:
	_apply_bus_volume_multiplier(BUS_SFX, base_sfx_volume_linear, value)


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
	if pause_panel.visible or settings_panel.visible:
		target_indicator.hide()
		return

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

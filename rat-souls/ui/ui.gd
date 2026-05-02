extends CanvasLayer

@onready var target_indicator: TextureRect = $target_indicator
@onready var health_bar: ProgressBar = $HBoxContainer/VBoxContainer/HealthBar
@onready var stamina_bar: ProgressBar = $HBoxContainer/VBoxContainer/StaminaBar
@onready var pause_panel: Control = $PausePanel
@onready var settings_panel: Control = $SettingsPanel
@onready var game_over_panel: Control = $GameOverPanel
@onready var final_score_label: Label = $GameOverPanel/FinalScoreLabel
@onready var retry_button: Button = $GameOverPanel/VBoxContainer/RetryButton
@onready var resume_button: Button = $PausePanel/VBoxContainer/ResumeButton
@onready var settings_button: Button = $PausePanel/VBoxContainer/SettingsButton
@onready var exit_button: Button = $PausePanel/VBoxContainer/ExitButton
@onready var back_button: Button = $SettingsPanel/VBoxContainer/CenterContainer/BackButton
@onready var mouse_sensitivity_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/SensitivitySettings/VBoxContainer/MouseSens/HSlider
@onready var controller_sensitivity_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/SensitivitySettings/VBoxContainer/ContSens/HSlider
@onready var master_volume_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/VolumeSettings/VBoxContainer/MasterVol/HSlider
@onready var bgm_volume_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/VolumeSettings/VBoxContainer/BGMusic/HSlider
@onready var sfx_volume_slider: HSlider = $SettingsPanel/VBoxContainer/Settings/VolumeSettings/VBoxContainer/SFX/HSlider
@onready var score_label: Label = get_node_or_null("ColorRect/ScoreLabel") as Label

const BAR_SMOOTH_SPEED: float = 8.0
const MAIN_MENU_SCENE_PATH: String = "res://scenes/main_menu.tscn"
const BUS_MASTER: StringName = &"Master"
const BUS_BGM: StringName = &"BGM"
const BUS_SFX: StringName = &"SFX"
const MIN_LINEAR_VOLUME: float = 0.0001
const SETTINGS_FILE_PATH: String = "user://settings.cfg"

var player: Node = null
var health_max: float = 1.0
var shown_health: float = 0.0
var shown_stamina: float = 0.0
var base_mouse_sensitivity: float = 0.0
var base_controller_sensitivity: float = 0.0
var base_master_volume_linear: float = 1.0
var base_bgm_volume_linear: float = 1.0
var base_sfx_volume_linear: float = 1.0
var game_manager: Node = null

# Score pop animation
var _last_score: int = -1
var _score_pop_tween: Tween = null

# Kill puns
var _combo_label: Label = null
var _combo_tween: Tween = null
var _last_combo: int = 0

# Pun display RNG
var _pun_rng: RandomNumberGenerator = RandomNumberGenerator.new()
const KILL_PUNS: Array[String] = [
	"Paw-some.",
	"Fur real though.",
	"That's a wrap, tabby.",
	"One less cat-astrophe.",
	"Meow-t for the count.",
	"Couldn't cat-ch a break.",
	"Rat justice served.",
	"Feline defeated.",
	"Nine lives? Not today.",
	"Purr-ished.",
	"Litter-ally destroyed.",
	"Scratch that cat off the list.",
	"Tail of the defeated.",
	"You've gotta be kitten me.",
	"Fur-ocious.",
	"No more cat-napping.",
	"The feline has left the arena.",
	"Rat-ribution.",
	"You shall not paw-ss.",
	"Cat-astrophic failure.",
	"This rat bites back.",
	"Justice in fur.",
	"Squeaky... and deadly.",
	"No more mr mice guy.",
	"Rodent rage.",
	"A rat to be reckoned with.",
	"Rat king material.",
	"Pounced back.",
	"MOUSE-CLES!!!",
	"Cheese the day.",
	"Cat-ch me if you can.",
	"That's un-fur-tunate.",
	"Rat-ical victory.",
	"It's not easy being cheesy.",
	"Paw-sitively lethal",
	"Meow-sacre.",
	"Fur-bidden power",
	"Cat-astrophjcally outmatched.",
	"Paw-lease stop.",
	"Claw-ver move.",
	"The cat is purr-manently out of commission."
]
const PUN_COLORS: Array[Color] = [
	Color(1.0, 0.85, 0.2), # Gold
	Color(1.0, 0.4, 0.4),  # Soft Red
	Color(0.4, 1.0, 0.4),  # Soft Green
	Color(0.4, 0.8, 1.0),  # Soft Blue
	Color(1.0, 0.6, 1.0),  # Pink/Purple
	Color(0.8, 1.0, 1.0),  # Cyan
]

# Health bar flash
var _health_flash_tween: Tween = null
var _last_health: float = -1.0

# Death screen
var _you_died_label: Label = null
var _death_fade_rect: ColorRect = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_refresh_player_reference()
	_cache_player_sensitivity_defaults()
	_cache_bus_volume_defaults()
	health_bar.step = 0.01
	stamina_bar.step = 0.01
	pause_panel.hide()
	settings_panel.hide()
	game_over_panel.hide()
	_load_settings()
	_connect_menu_signals()
	_apply_sensitivity_settings()
	_apply_volume_settings()
	target_indicator.hide()
	_apply_stats_immediately()
	_setup_kill_pun_label()
	_setup_death_screen_extras()
	_start_bgm_fade_in()
	_pun_rng.randomize()


func _process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		_refresh_player_reference()

	_update_bars(delta)
	_update_target_indicator()
	_update_score_pop()
	_update_kill_pun_trigger()
	_update_health_flash()


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


func _refresh_game_manager_reference() -> void:
	if game_manager != null and is_instance_valid(game_manager):
		return

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		game_manager = null
		return

	game_manager = scene_root.get_node_or_null("GameManager")


func _get_final_score() -> int:
	_refresh_game_manager_reference()
	if game_manager == null or not is_instance_valid(game_manager):
		return 0
	if not game_manager.has_method("get_score"):
		return 0

	var score_value: Variant = game_manager.call("get_score")
	if score_value is int:
		return max(0, score_value)
	return 0


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
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _on_mouse_sensitivity_slider_value_changed(_value: float) -> void:
	_apply_sensitivity_settings()
	_save_settings()


func _on_controller_sensitivity_slider_value_changed(_value: float) -> void:
	_apply_sensitivity_settings()
	_save_settings()


func _on_master_volume_slider_value_changed(value: float) -> void:
	_apply_bus_volume_multiplier(BUS_MASTER, base_master_volume_linear, value)
	_save_settings()


func _on_bgm_volume_slider_value_changed(value: float) -> void:
	_apply_bus_volume_multiplier(BUS_BGM, base_bgm_volume_linear, value)
	_save_settings()


func _on_sfx_volume_slider_value_changed(value: float) -> void:
	_apply_bus_volume_multiplier(BUS_SFX, base_sfx_volume_linear, value)
	_save_settings()


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


func _on_retry_button_pressed() -> void:
	get_tree().paused = false
	Input.flush_buffered_events()
	get_tree().change_scene_to_file("res://scenes/test_scene.tscn")


func _on_main_menu_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func show_game_over() -> void:
	pause_panel.hide()
	settings_panel.hide()
	final_score_label.text = "Final Score: %d" % _get_final_score()
	# Add combo bonus info if applicable
	var combo: int = 0
	if has_node("/root/ScreenEffects"):
		combo = get_node("/root/ScreenEffects").get_combo_count()
	game_over_panel.show()
	# Dramatic "YOU DIED" sequence
	_play_death_screen_sequence()
	call_deferred("_focus_retry_button")


func _focus_retry_button() -> void:
	if game_over_panel.visible:
		retry_button.grab_focus()


func _load_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	mouse_sensitivity_slider.value = config.get_value("Settings", "mouse_sensitivity", 1.0)
	controller_sensitivity_slider.value = config.get_value("Settings", "controller_sensitivity", 1.0)
	master_volume_slider.value = config.get_value("Settings", "master_volume", 1.0)
	bgm_volume_slider.value = config.get_value("Settings", "bgm_volume", 1.0)
	sfx_volume_slider.value = config.get_value("Settings", "sfx_volume", 1.0)


func _save_settings() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_FILE_PATH)
	config.set_value("Settings", "mouse_sensitivity", mouse_sensitivity_slider.value)
	config.set_value("Settings", "controller_sensitivity", controller_sensitivity_slider.value)
	config.set_value("Settings", "master_volume", master_volume_slider.value)
	config.set_value("Settings", "bgm_volume", bgm_volume_slider.value)
	config.set_value("Settings", "sfx_volume", sfx_volume_slider.value)
	config.save(SETTINGS_FILE_PATH)


# ═══════════════════════════════════════════════════════════════════════════════
# POLISH: Score Pop Animation
# ═══════════════════════════════════════════════════════════════════════════════

func _update_score_pop() -> void:
	if score_label == null:
		return

	_refresh_game_manager_reference()
	var current_score: int = 0
	if game_manager != null and is_instance_valid(game_manager) and game_manager.has_method("get_score"):
		current_score = game_manager.get_score()

	if current_score != _last_score and _last_score >= 0:
		_play_score_pop()
	_last_score = current_score


func _play_score_pop() -> void:
	if score_label == null:
		return

	if _score_pop_tween != null:
		_score_pop_tween.kill()

	score_label.scale = Vector2.ONE
	_score_pop_tween = create_tween()
	_score_pop_tween.set_trans(Tween.TRANS_ELASTIC)
	_score_pop_tween.set_ease(Tween.EASE_OUT)
	_score_pop_tween.tween_property(score_label, "scale", Vector2(1.35, 1.35), 0.15)
	_score_pop_tween.tween_property(score_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


# ═══════════════════════════════════════════════════════════════════════════════
# POLISH: Per-Kill Pun Display
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_kill_pun_label() -> void:
	_combo_label = Label.new()
	_combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_combo_label.anchors_preset = Control.PRESET_CENTER_TOP
	_combo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_label.offset_top = 80.0
	_combo_label.offset_left = -300.0
	_combo_label.offset_right = 300.0
	_combo_label.offset_bottom = 140.0
	var font_res: Font = load("res://assets/fonts/Micro5-Regular.ttf") as Font
	if font_res != null:
		_combo_label.add_theme_font_override("font", font_res)
		_combo_label.add_theme_font_size_override("font_size", 72)
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2, 1.0))
	_combo_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	_combo_label.add_theme_constant_override("shadow_offset_x", 2)
	_combo_label.add_theme_constant_override("shadow_offset_y", 2)
	_combo_label.text = ""
	_combo_label.modulate.a = 0.0
	_combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_combo_label)


func _update_kill_pun_trigger() -> void:
	if not has_node("/root/ScreenEffects"):
		return
	var current_kills: int = get_node("/root/ScreenEffects").get_combo_count()
	# Detect a new kill by tracking the running total
	if current_kills != _last_combo and current_kills > _last_combo:
		_show_kill_pun()
	_last_combo = current_kills


func _show_kill_pun() -> void:
	if _combo_label == null or KILL_PUNS.is_empty():
		return
	var pun: String = KILL_PUNS[_pun_rng.randi() % KILL_PUNS.size()]
	_combo_label.text = pun
	
	var random_color: Color = PUN_COLORS[_pun_rng.randi() % PUN_COLORS.size()]
	_combo_label.add_theme_color_override("font_color", random_color)

	if _combo_tween != null:
		_combo_tween.kill()
	_combo_label.modulate.a = 1.0
	_combo_label.scale = Vector2(1.4, 1.4)
	_combo_tween = create_tween()
	_combo_tween.tween_property(_combo_label, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_combo_tween.tween_interval(1.8)
	_combo_tween.tween_property(_combo_label, "modulate:a", 0.0, 0.4)


# ═══════════════════════════════════════════════════════════════════════════════
# POLISH: Health Bar Damage Flash
# ═══════════════════════════════════════════════════════════════════════════════

func _update_health_flash() -> void:
	if player == null or not is_instance_valid(player):
		return

	var current_health: float = float(player.get("health"))
	if _last_health < 0.0:
		_last_health = current_health
		return

	if current_health < _last_health:
		_flash_health_bar()
	_last_health = current_health


func _flash_health_bar() -> void:
	if _health_flash_tween != null:
		_health_flash_tween.kill()

	health_bar.modulate = Color(3.0, 0.5, 0.5, 1.0)  # Bright red flash
	_health_flash_tween = create_tween()
	_health_flash_tween.tween_property(health_bar, "modulate", Color.WHITE, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


# ═══════════════════════════════════════════════════════════════════════════════
# POLISH: Dramatic Death Screen
# ═══════════════════════════════════════════════════════════════════════════════

func _setup_death_screen_extras() -> void:
	# "YOU DIED" label — large, centered, dramatic
	_you_died_label = Label.new()
	_you_died_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_you_died_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_you_died_label.anchors_preset = Control.PRESET_CENTER
	_you_died_label.set_anchors_preset(Control.PRESET_CENTER)
	_you_died_label.offset_left = -400.0
	_you_died_label.offset_right = 400.0
	_you_died_label.offset_top = -120.0
	_you_died_label.offset_bottom = 120.0
	var font_res: Font = load("res://assets/fonts/Micro5-Regular.ttf") as Font
	if font_res != null:
		_you_died_label.add_theme_font_override("font", font_res)
	_you_died_label.add_theme_font_size_override("font_size", 220)
	_you_died_label.add_theme_color_override("font_color", Color(0.85, 0.12, 0.1, 1.0))
	_you_died_label.text = "YOU DIED"
	_you_died_label.modulate.a = 0.0
	_you_died_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_you_died_label.visible = false
	game_over_panel.add_child(_you_died_label)

	# Red fade overlay behind everything
	_death_fade_rect = ColorRect.new()
	_death_fade_rect.anchors_preset = Control.PRESET_FULL_RECT
	_death_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death_fade_rect.color = Color(0.15, 0.0, 0.0, 0.0)
	_death_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_fade_rect.visible = false
	# Insert behind game_over_panel content
	game_over_panel.add_child(_death_fade_rect)
	game_over_panel.move_child(_death_fade_rect, 0)


func _play_death_screen_sequence() -> void:
	if _you_died_label == null or _death_fade_rect == null:
		return

	# Hide existing game over elements initially
	var game_over_label: Label = game_over_panel.get_node_or_null("GameOverLabel") as Label
	var sad_hampter: TextureRect = game_over_panel.get_node_or_null("SadHampter") as TextureRect
	var buttons_container: VBoxContainer = game_over_panel.get_node_or_null("VBoxContainer") as VBoxContainer

	if game_over_label:
		game_over_label.modulate.a = 0.0
	if final_score_label:
		final_score_label.modulate.a = 0.0
	if sad_hampter:
		sad_hampter.modulate.a = 0.0
	if buttons_container:
		buttons_container.modulate.a = 0.0

	# Show "YOU DIED" first
	_you_died_label.visible = true
	_you_died_label.modulate.a = 0.0
	_death_fade_rect.visible = true
	_death_fade_rect.color = Color(0.15, 0.0, 0.0, 0.0)

	var tween: Tween = create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_IDLE)

	# Phase 1: Red tint fades in with "YOU DIED"
	tween.tween_property(_death_fade_rect, "color:a", 0.4, 1.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_you_died_label, "modulate:a", 1.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# Phase 2: Hold "YOU DIED"
	tween.tween_interval(2.0)

	# Phase 3: Fade out "YOU DIED", fade in game over content
	tween.tween_property(_you_died_label, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_death_fade_rect, "color:a", 0.0, 0.5)

	if game_over_label:
		tween.parallel().tween_property(game_over_label, "modulate:a", 1.0, 0.6).set_trans(Tween.TRANS_SINE)
	if final_score_label:
		tween.parallel().tween_property(final_score_label, "modulate:a", 1.0, 0.6).set_delay(0.15)
	if sad_hampter:
		tween.parallel().tween_property(sad_hampter, "modulate:a", 1.0, 0.6).set_delay(0.3)
	if buttons_container:
		tween.parallel().tween_property(buttons_container, "modulate:a", 1.0, 0.6).set_delay(0.4)


# ═══════════════════════════════════════════════════════════════════════════════
# POLISH: BGM Fade-In
# ═══════════════════════════════════════════════════════════════════════════════

func _start_bgm_fade_in() -> void:
	# Find the BGM node in the current scene and fade it in
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return

	var bgm: AudioStreamPlayer = scene_root.get_node_or_null("BGM") as AudioStreamPlayer
	if bgm == null:
		return

	# Start silent and fade in over 3 seconds
	var target_db: float = bgm.volume_db
	if target_db <= -79.0:
		# BGM volume is already set to -80 in the scene, fade to a reasonable level
		target_db = -12.0
	bgm.volume_db = -60.0
	var fade_tween: Tween = create_tween()
	fade_tween.tween_property(bgm, "volume_db", target_db, 3.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

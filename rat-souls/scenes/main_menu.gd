extends Node3D

@onready var title_label: Label = $Elements/Root/Title/TitleLabel
@onready var click_continue_label: Label = $Elements/Root/Title/ClickContinueLabel
@onready var controls_panel: Control = $Elements/Root/ControlsPanel
@onready var camera_3d: Camera3D = $Camera3D
@onready var rat_animation_player: AnimationPlayer = get_node_or_null("rat-rigged/AnimationPlayer") as AnimationPlayer

var has_started_transition: bool = false
var title_fade_tween: Tween
var click_pulse_tween: Tween


func _ready() -> void:
	title_label.visible = false
	title_label.modulate.a = 0.0
	click_continue_label.visible = false
	click_continue_label.modulate.a = 0.0
	controls_panel.visible = false
	_play_rat_intro_animation()
	_play_title_intro_sequence()


func _input(event: InputEvent) -> void:
	if has_started_transition:
		return

	if event is InputEventMouseButton and event.pressed:
		_start_click_transition()
		return

	if event is InputEventScreenTouch and event.pressed:
		_start_click_transition()
		return

	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y]:
			_start_click_transition()


func _play_rat_intro_animation() -> void:
	if rat_animation_player == null:
		return

	if rat_animation_player.has_animation("Idle"):
		rat_animation_player.play("Idle")

	if rat_animation_player.has_animation("Death"):
		await get_tree().create_timer(0.4).timeout
		rat_animation_player.play("Death")


func _play_title_intro_sequence() -> void:
	await get_tree().create_timer(2.0).timeout
	_fade_in_title_label()

	await get_tree().create_timer(2.0).timeout
	_start_click_continue_pulse()


func _fade_in_title_label() -> void:
	title_label.visible = true
	title_fade_tween = create_tween()
	title_fade_tween.set_trans(Tween.TRANS_SINE)
	title_fade_tween.set_ease(Tween.EASE_IN_OUT)
	title_fade_tween.tween_property(title_label, "modulate:a", 1.0, 1.5)


func _start_click_continue_pulse() -> void:
	click_continue_label.visible = true
	click_pulse_tween = create_tween()
	click_pulse_tween.set_trans(Tween.TRANS_SINE)
	click_pulse_tween.set_ease(Tween.EASE_IN_OUT)
	click_pulse_tween.set_loops()
	click_pulse_tween.tween_property(click_continue_label, "modulate:a", 1.0, 0.9)
	click_pulse_tween.tween_property(click_continue_label, "modulate:a", 0.35, 0.9)


func _start_click_transition() -> void:
	has_started_transition = true
	if title_fade_tween != null:
		title_fade_tween.kill()
	if click_pulse_tween != null:
		click_pulse_tween.kill()
	title_label.visible = false
	click_continue_label.visible = false

	var camera_tween: Tween = create_tween()
	camera_tween.set_trans(Tween.TRANS_SINE)
	camera_tween.set_ease(Tween.EASE_IN_OUT)
	camera_tween.tween_property(
		camera_3d,
		"rotation_degrees:x",
		camera_3d.rotation_degrees.x + 105.0,
		1.0
	)

	await camera_tween.finished
	controls_panel.visible = true

	var start_button: Button = controls_panel.get_node_or_null("StartGameButton") as Button
	if start_button:
		start_button.call_deferred("grab_focus")


func _on_start_game_button_pressed() -> void:
	Input.flush_buffered_events()
	get_tree().change_scene_to_file("res://scenes/test_scene.tscn")

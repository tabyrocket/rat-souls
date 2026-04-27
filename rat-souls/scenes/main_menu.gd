extends Node3D

@onready var title: Control = $Elements/Root/Title
@onready var controls_panel: Control = $Elements/Root/ControlsPanel
@onready var camera_3d: Camera3D = $Camera3D
@onready var rat_animation_player: AnimationPlayer = get_node_or_null("rat-rigged/AnimationPlayer") as AnimationPlayer

var has_started_transition: bool = false


func _ready() -> void:
	title.visible = true
	controls_panel.visible = false
	_play_rat_intro_animation()


func _input(event: InputEvent) -> void:
	if has_started_transition:
		return

	if event is InputEventMouseButton and event.pressed:
		_start_click_transition()
		return

	if event is InputEventScreenTouch and event.pressed:
		_start_click_transition()


func _play_rat_intro_animation() -> void:
	if rat_animation_player == null:
		return

	if rat_animation_player.has_animation("Idle"):
		rat_animation_player.play("Idle")

	if rat_animation_player.has_animation("Death"):
		await get_tree().create_timer(0.4).timeout
		rat_animation_player.play("Death")


func _start_click_transition() -> void:
	has_started_transition = true
	title.visible = false

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


func _on_start_game_button_pressed() -> void:
	Input.flush_buffered_events()
	get_tree().change_scene_to_file("res://scenes/test_scene.tscn")

extends CharacterBody3D

# Camera settings
@onready var camera_pivot = $CameraPivot
@export var mouse_sensitivity = 0.002
@export var controller_look_sensitivity: float = 2.0
@export var min_look_angle_deg: float = -60.0
@export var max_look_angle_deg: float = 20.0

# SFX
@onready var dodge_sfx: AudioStreamPlayer3D = $DodgeSFX

# Dodge settings
@export var dodge_speed: float = 14.0
@export var dodge_duration: float = 0.20
@export var dodge_cooldown: float = 0.60
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO

# Movement variables
var speed = 6.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	# Handle mouse look
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_angle_deg), deg_to_rad(max_look_angle_deg))

func _physics_process(delta):
	# Update dodge cooldown
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	# Handle controller look input
	var look_input = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input != Vector2.ZERO:
		rotate_y(-look_input.x * controller_look_sensitivity * delta)
		camera_pivot.rotation.x -= look_input.y * controller_look_sensitivity * delta
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_angle_deg), deg_to_rad(max_look_angle_deg))

	# Handle movement input
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if Input.is_action_just_pressed("dodge") and dodge_cooldown_timer <= 0.0 and not is_dodging:
		is_dodging = true
		dodge_timer = dodge_duration
		dodge_cooldown_timer = dodge_cooldown
		dodge_sfx.play()

		dodge_direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
		if dodge_direction == Vector3.ZERO:
			dodge_direction = -transform.basis.z

	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if is_dodging:
		dodge_timer -= delta
		velocity.x = dodge_direction.x * dodge_speed
		velocity.z = dodge_direction.z * dodge_speed
		if dodge_timer <= 0.0:
			is_dodging = false
	elif direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Stop sliding
		velocity.x = 0
		velocity.z = 0

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Lock rotation
	rotation.x = 0
	rotation.z = 0

	move_and_slide()

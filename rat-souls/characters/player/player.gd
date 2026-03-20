extends CharacterBody3D

# Camera settings
@onready var camera_pivot = $CameraPivot
@export var mouse_sensitivity = 0.002
@export var controller_look_sensitivity: float = 2.0
@export var min_look_angle_deg: float = -60.0
@export var max_look_angle_deg: float = 20.0
var camera_offset: Vector3

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

# Player model rotation speed (how quickly the character turns to face movement direction)
var player_model_rotation_speed: float = 10.0

# Movement variables
var speed = 6.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Detach the camera pivot from the player's rotation so they can spin independently
	camera_offset = camera_pivot.position
	camera_pivot.top_level = true

func _input(event):
	# Handle mouse look
	if event is InputEventMouseMotion:
		camera_pivot.rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_angle_deg), deg_to_rad(max_look_angle_deg))

func _physics_process(delta):
	# Keep camera following the player's position
	camera_pivot.global_position = global_position + camera_offset

	# Update dodge cooldown
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta

	# Handle controller look input
	var look_input = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input != Vector2.ZERO:
		camera_pivot.rotate_y(-look_input.x * controller_look_sensitivity * delta)
		camera_pivot.rotation.x -= look_input.y * controller_look_sensitivity * delta
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_angle_deg), deg_to_rad(max_look_angle_deg))

	# Handle movement input
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	# Calculate move direction relative to camera
	var cam_basis = camera_pivot.global_transform.basis
	var direction = (cam_basis * Vector3(input_dir.x, 0, input_dir.y))
	direction.y = 0 # keep it flat
	direction = direction.normalized()

	if Input.is_action_just_pressed("dodge") and dodge_cooldown_timer <= 0.0 and not is_dodging:
		is_dodging = true
		dodge_timer = dodge_duration
		dodge_cooldown_timer = dodge_cooldown
		dodge_sfx.play()

		dodge_direction = direction
		if dodge_direction == Vector3.ZERO:
			# Dodge backwards relative to camera if not moving
			dodge_direction = (cam_basis * Vector3.BACK).normalized()

	if is_dodging:
		dodge_timer -= delta
		velocity.x = dodge_direction.x * dodge_speed
		velocity.z = dodge_direction.z * dodge_speed
		
		# Rotate character instantly to face the dodge direction
		var look_target = global_position - dodge_direction
		if global_position.is_equal_approx(look_target) == false:
			look_at(look_target, Vector3.UP)
			
		if dodge_timer <= 0.0:
			is_dodging = false
	elif direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Rotate the player model towards the movement direction smoothly
		var target_angle = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, player_model_rotation_speed * delta)
	else:
		# Stop sliding
		velocity.x = 0
		velocity.z = 0

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Lock constraints
	rotation.x = 0
	rotation.z = 0

	move_and_slide()
	

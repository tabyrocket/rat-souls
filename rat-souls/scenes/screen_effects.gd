extends Node
## Global screen effects manager: screen shake, hitstop (time freeze), and low-health vignette.
## Add as an Autoload named "ScreenEffects".

# ─── Screen Shake ──────────────────────────────────────────────────────────────
var _shake_intensity: float = 0.0
var _shake_duration: float = 0.0
var _shake_timer: float = 0.0
var _shake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

# ─── Hitstop ────────────────────────────────────────────────────────────────────
var _hitstop_timer: float = 0.0
var _hitstop_previous_time_scale: float = 1.0

# ─── Low-health vignette ───────────────────────────────────────────────────────
var _vignette_overlay: ColorRect = null
var _vignette_canvas: CanvasLayer = null
var _vignette_pulse_time: float = 0.0
var _vignette_active: bool = false
const LOW_HEALTH_THRESHOLD: float = 0.30
const VIGNETTE_PULSE_SPEED: float = 3.5
const VIGNETTE_MAX_ALPHA: float = 0.22

# ─── Combo counter ─────────────────────────────────────────────────────────────
var combo_count: int = 0
var combo_timer: float = 0.0
const COMBO_TIMEOUT: float = 3.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_shake_rng.randomize()
	_setup_vignette_overlay()


func _process(delta: float) -> void:
	_process_hitstop(delta)
	# Use unscaled delta for shake (hitstop freezes _process, but we set PROCESS_MODE_ALWAYS)
	_process_shake(delta)
	_process_vignette(delta)
	_process_combo(delta)


# ═══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ═══════════════════════════════════════════════════════════════════════════════

## Shake the camera for `duration` seconds at `intensity` strength.
func shake(intensity: float, duration: float) -> void:
	if intensity > _shake_intensity:
		_shake_intensity = intensity
		_shake_duration = duration
		_shake_timer = duration


## Freeze time for `duration` seconds (hitstop).
func hitstop(duration: float) -> void:
	if _hitstop_timer > 0.0:
		_hitstop_timer = max(_hitstop_timer, duration)
		return

	_hitstop_previous_time_scale = Engine.time_scale
	_hitstop_timer = duration
	Engine.time_scale = 0.05


## Register a kill for the combo counter.
func register_kill() -> void:
	combo_count += 1
	combo_timer = COMBO_TIMEOUT


## Get the current combo count.
func get_combo_count() -> int:
	return combo_count


## Check and update the low-health vignette based on player state.
func update_health_vignette(health_ratio: float) -> void:
	_vignette_active = health_ratio > 0.0 and health_ratio <= LOW_HEALTH_THRESHOLD


# ═══════════════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════════════

func _process_shake(_delta: float) -> void:
	if _shake_timer <= 0.0:
		_shake_intensity = 0.0
		return

	# Use real (unscaled) time so shake works during hitstop
	var real_delta: float = _delta / max(Engine.time_scale, 0.001)
	_shake_timer -= real_delta

	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return

	var decay: float = clamp(_shake_timer / max(_shake_duration, 0.001), 0.0, 1.0)
	var offset := Vector3(
		_shake_rng.randf_range(-1.0, 1.0),
		_shake_rng.randf_range(-1.0, 1.0),
		0.0
	) * _shake_intensity * decay

	camera.h_offset = offset.x
	camera.v_offset = offset.y

	if _shake_timer <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0
		_shake_intensity = 0.0


func _process_hitstop(delta: float) -> void:
	if _hitstop_timer <= 0.0:
		return

	# Use real time
	var real_delta: float = delta / max(Engine.time_scale, 0.001)
	_hitstop_timer -= real_delta

	if _hitstop_timer <= 0.0:
		_hitstop_timer = 0.0
		Engine.time_scale = _hitstop_previous_time_scale


func _setup_vignette_overlay() -> void:
	_vignette_canvas = CanvasLayer.new()
	_vignette_canvas.layer = 100
	add_child(_vignette_canvas)

	_vignette_overlay = ColorRect.new()
	_vignette_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_vignette_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette_overlay.color = Color(0.6, 0.0, 0.0, 0.0)

	# Use a shader for the radial vignette effect
	var shader_code := """
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.5, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv) * 1.5;
	float vignette = smoothstep(0.25, 0.9, dist);
	COLOR = vec4(vignette_color.rgb, vignette * intensity);
}
"""
	var shader := Shader.new()
	shader.code = shader_code
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	_vignette_overlay.material = shader_material
	_vignette_canvas.add_child(_vignette_overlay)


func _process_vignette(delta: float) -> void:
	if _vignette_overlay == null:
		return

	var mat: ShaderMaterial = _vignette_overlay.material as ShaderMaterial
	if mat == null:
		return

	if _vignette_active:
		_vignette_pulse_time += delta * VIGNETTE_PULSE_SPEED
		var pulse: float = (sin(_vignette_pulse_time) * 0.5 + 0.5) * VIGNETTE_MAX_ALPHA
		mat.set_shader_parameter("intensity", pulse)
	else:
		# Fade out quickly
		var current_val = mat.get_shader_parameter("intensity")
		var current: float = float(current_val) if current_val != null else 0.0
		if current > 0.001:
			mat.set_shader_parameter("intensity", move_toward(current, 0.0, delta * 2.0))
		else:
			mat.set_shader_parameter("intensity", 0.0)
			_vignette_pulse_time = 0.0


func _process_combo(delta: float) -> void:
	if combo_count <= 0:
		return

	combo_timer -= delta
	if combo_timer <= 0.0:
		combo_count = 0
		combo_timer = 0.0

extends DirectionalLight3D

@export_range(1.0, 1200.0, 0.5)
var cycle_length_seconds: float = 15.0

@export_range(0.05, 0.95, 0.01)
var night_fraction: float = 0.33

@export var night_color: Color = Color(0.14, 0.18, 0.32)
@export var dawn_color: Color = Color(1.0, 0.55, 0.28)
@export var day_color: Color = Color(1.0, 1.0, 0.82)
@export var dusk_color: Color = Color(1.0, 0.42, 0.24)

var _cycle_time_seconds: float = 0.0


func _ready() -> void:
	_apply_cycle()


func _process(delta: float) -> void:
	_cycle_time_seconds = fposmod(_cycle_time_seconds + delta, cycle_length_seconds)
	_apply_cycle()


func _apply_cycle() -> void:
	var night_length_seconds := cycle_length_seconds * night_fraction
	var day_length_seconds := cycle_length_seconds - night_length_seconds

	if _cycle_time_seconds < night_length_seconds:
		var night_phase := _cycle_time_seconds / night_length_seconds
		rotation_degrees.x = lerp(-90.0, 90.0, night_phase)
		light_color = night_color.lerp(dawn_color, night_phase)
		return

	var day_phase := (_cycle_time_seconds - night_length_seconds) / day_length_seconds
	rotation_degrees.x = lerp(90.0, 270.0, day_phase)
	light_color = _get_day_color(day_phase)


func _get_day_color(day_phase: float) -> Color:
	if day_phase < 0.33:
		return dawn_color.lerp(day_color, day_phase / 0.33)

	if day_phase < 0.66:
		return day_color.lerp(dusk_color, (day_phase - 0.33) / 0.33)

	return dusk_color.lerp(night_color, (day_phase - 0.66) / 0.34)

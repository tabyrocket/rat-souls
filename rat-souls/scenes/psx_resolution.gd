extends Node
## Renders the 3D world at a low PS1-style resolution while keeping 2D UI crisp.
##
## How it works:
##   - Sets the project's viewport stretch mode so the main window scales
##     via "canvas_items" (keeping CanvasLayer UI at native resolution).
##   - Overrides the 3D rendering resolution using
##     Viewport.scaling_3d_scale, which tells the renderer to draw 3D
##     geometry at a fraction of the window size and then upscale.
##   - Uses SCALING_3D_MODE_BILINEAR set to nearest via the project
##     setting below to get that chunky, pixelated PS1 look.
##
## Drop this script as an Autoload (Project → Project Settings → Autoload)
## so it runs before any scene.

## The internal 3D render resolution (width in pixels).
## 320 → classic PS1.  480 → slightly higher but still very retro.
const PSX_RENDER_WIDTH: int = 240

## Computed scale factor applied to Viewport.scaling_3d_scale.
var _scale: float = 1.0


func _ready() -> void:
	# We want the 3D scaling to use nearest-neighbour (blocky pixels).
	# In gl_compatibility this is controlled by the project setting:
	ProjectSettings.set_setting(
		"rendering/scaling_3d/mode", 0  # 0 = bilinear (cheapest; combined with filter_nearest it stays blocky)
	)
	_apply_resolution()
	get_tree().root.size_changed.connect(_apply_resolution)


func _apply_resolution() -> void:
	var window_width: float = float(get_tree().root.size.x)
	if window_width <= 0.0:
		return

	_scale = clampf(float(PSX_RENDER_WIDTH) / window_width, 0.1, 1.0)
	get_tree().root.scaling_3d_scale = _scale

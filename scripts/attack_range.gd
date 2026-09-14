extends CanvasLayer
## A screen-space footprint of the direct strike, beneath the existing HUD.
const ResponsiveUI = preload("res://scripts/responsive_ui.gd")

class RangeRing extends Control:
	var radius := 0.0
	var stroke_scale := 1.0

	func _draw() -> void:
		# A quiet fill and contrasting rim remain readable on every ore theme.
		draw_circle(Vector2.ZERO, radius, Color(1.0, 0.87, 0.56, 0.045))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(0.035, 0.055, 0.06, 0.52), 3.8 * stroke_scale, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(1.0, 0.91, 0.67, 0.78), 1.35 * stroke_scale, true)
		for side in 4:
			var direction := Vector2.from_angle(float(side) * PI * 0.5)
			draw_line(direction * (radius - 2.5 * stroke_scale), direction * (radius + 2.5 * stroke_scale), Color(1.0, 0.94, 0.77, 0.9), 1.5 * stroke_scale, true)

var ring := RangeRing.new()

func _ready() -> void:
	layer = 8
	ring.name = "RangeRing"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.hide()
	add_child(ring)

func show_range(center: Vector2, screen_radius: float) -> void:
	var scale: float = ResponsiveUI.metrics(get_viewport()).scale
	ring.position = center
	if not is_equal_approx(ring.radius, screen_radius) or not is_equal_approx(ring.stroke_scale, scale):
		ring.radius = screen_radius
		ring.stroke_scale = scale
		ring.queue_redraw()
	ring.show()

func clear() -> void:
	ring.hide()

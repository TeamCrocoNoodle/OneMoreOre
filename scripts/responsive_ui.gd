extends RefCounted
## A shared UI coordinate system, independent of the project's stretch transform.

static func metrics(viewport: Viewport) -> Dictionary:
	var logical := viewport.get_visible_rect().size
	var transform := viewport.get_final_transform()
	var pixel_ratio := maxf(minf(transform.x.length(), transform.y.length()), 0.001)
	var pixels := logical * pixel_ratio
	var portrait := pixels.x < pixels.y
	var screen_scale: float
	if portrait:
		# Phone layout remains a phone layout at high resolution, including HiDPI.
		screen_scale = minf(pixels.x / 420.0, pixels.y / 740.0)
	else:
		# Grow without an upper cap. Small windows reflow before reducing text.
		screen_scale = maxf(0.85, minf(pixels.x / 1200.0, pixels.y / 850.0))
		screen_scale = minf(screen_scale, minf(pixels.x / 760.0, pixels.y / 500.0))
	var scale := maxf(screen_scale / pixel_ratio, 0.001)
	return {"scale": scale, "view": logical / scale, "portrait": portrait}


static func render_size(viewport: Viewport, ui_size: Vector2, scale: float, limit: int = 2560) -> Vector2i:
	var transform := viewport.get_final_transform()
	var pixels := ui_size * scale * minf(transform.x.length(), transform.y.length())
	pixels *= minf(1.15, float(limit) / maxf(maxf(pixels.x, pixels.y), 1.0))
	return Vector2i(pixels.ceil()).max(Vector2i(2, 2))

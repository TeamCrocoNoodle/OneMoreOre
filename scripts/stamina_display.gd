extends RefCounted
## Presentation units only. The round keeps its existing health and drain math.
const UNITS_PER_POINT := 10.0

static func counter(points: float) -> int:
	if not is_finite(points) or points <= 0.0:
		return 0
	# Avoid a floating-point residue delaying a digit at exact 0.1 s boundaries.
	# Positive health always remains visible until the round actually expires.
	return maxi(1, ceili(points * UNITS_PER_POINT - 0.000001))

static func amount(points: float) -> String:
	# Tooltips and healing notices retain fractional gains, e.g. 0.35 -> 3.5.
	var text := "%.2f" % (points * UNITS_PER_POINT)
	return text.trim_suffix("0").trim_suffix("0").trim_suffix(".")

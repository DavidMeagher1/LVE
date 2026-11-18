extends RefCounted


static func weight_at(distance: float, size: float, falloff: float, inner := 0.0) -> float:
	var radius := size * 0.5
	if radius <= 0.0:
		return 1.0
	var start := clampf(inner, 0.0, radius)
	var span := radius - start
	if span <= 0.0:
		return 1.0
	var t := clampf((distance - start) / span, 0.0, 1.0)
	var smooth := 1.0 - (t * t * (3.0 - 2.0 * t))
	return lerpf(1.0, smooth, clampf(falloff, 0.0, 1.0))

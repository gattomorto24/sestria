extends RefCounted

# Logical coordinates; testable independently from the Android window manager.
static func measure(logical: Vector2, pixels: Vector2, safe: Rect2, cutouts: Array) -> Vector4:
	if pixels.x <= 0 or pixels.y <= 0:
		return Vector4(24,24,24,24)
	var factor := logical / pixels
	var inset := Vector4(24,24,24,24)
	if safe.size.x > 0 and safe.size.y > 0:
		inset.x = maxf(inset.x,safe.position.x*factor.x+12)
		inset.y = maxf(inset.y,safe.position.y*factor.y+12)
		inset.z = maxf(inset.z,(pixels.x-safe.end.x)*factor.x+12)
		inset.w = maxf(inset.w,(pixels.y-safe.end.y)*factor.y+16)
	for cutout: Rect2 in cutouts:
		if cutout.position.y < pixels.y*.16:
			inset.y = maxf(inset.y,cutout.end.y*factor.y+20)
		elif cutout.end.y > pixels.y*.9:
			inset.w = maxf(inset.w,(pixels.y-cutout.position.y)*factor.y+20)
	return inset

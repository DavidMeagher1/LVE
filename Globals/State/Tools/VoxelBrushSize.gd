extends RefCounted


const MIN_SIZE := 1
const MAX_SIZE := 64


static func clamp_size(size: int) -> int:
	return clampi(size, MIN_SIZE, MAX_SIZE)


static func first_offset(size: int) -> int:
	return -floori(size * 0.5)


static func last_offset(size: int) -> int:
	return first_offset(size) + size - 1


static func center(size: int) -> float:
	return (size - 1) * 0.5


static func center_offset(size: int) -> float:
	return first_offset(size) + center(size)


static func radius(size: int) -> float:
	return size * 0.5


static func radius_squared(size: int) -> float:
	return size * size * 0.25


static func contains_cube(size: int, offset: Vector3i) -> bool:
	var low := first_offset(size)
	var high := last_offset(size)
	return (
		offset.x >= low and offset.x <= high
		and offset.y >= low and offset.y <= high
		and offset.z >= low and offset.z <= high
	)


static func contains_sphere(size: int, offset: Vector3i) -> bool:
	var c := center_offset(size)
	var relative := Vector3(offset.x - c, offset.y - c, offset.z - c)
	return relative.length_squared() <= radius_squared(size)


static func contains(size: int, offset: Vector3i, sphere: bool) -> bool:
	return contains_sphere(size, offset) if sphere else contains_cube(size, offset)


static func sphere_offsets(size: int) -> Array[Vector3i]:
	var offsets: Array[Vector3i] = []
	var low := first_offset(size)
	var high := last_offset(size)
	var c := center_offset(size)
	var limit := radius_squared(size)
	for x in range(low, high + 1):
		for y in range(low, high + 1):
			for z in range(low, high + 1):
				var relative := Vector3(x - c, y - c, z - c)
				if relative.length_squared() <= limit:
					offsets.append(Vector3i(x, y, z))
	return offsets


static func reach(size: int) -> int:
	var low := first_offset(size)
	var high := last_offset(size)
	var c := center_offset(size)
	var limit := radius_squared(size)
	var longest := 0
	for x in range(low, high + 1):
		var dx := float(x) - c
		var rest_x := limit - dx * dx
		if rest_x < 0.0:
			continue
		for y in range(low, high + 1):
			var dy := float(y) - c
			var rest_y := rest_x - dy * dy
			if rest_y < 0.0:
				continue
			var span := sqrt(rest_y)
			var z_high := mini(high, floori(c + span))
			var z_low := maxi(low, ceili(c - span))
			if z_low > z_high:
				continue
			var z := maxi(absi(z_low), absi(z_high))
			longest = maxi(longest, x * x + y * y + z * z)
	return ceili(sqrt(float(longest)))


static func disk_contains(size: int, u: int, v: int) -> bool:
	var c := center_offset(size)
	var du := float(u) - c
	var dv := float(v) - c
	return du * du + dv * dv <= radius_squared(size)


static func disk_offsets(size: int) -> Array:
	var offsets := []
	var low := first_offset(size)
	var high := last_offset(size)
	var c := center_offset(size)
	var limit := radius_squared(size)
	for u in range(low, high + 1):
		var du := float(u) - c
		for v in range(low, high + 1):
			var dv := float(v) - c
			var distance_squared := du * du + dv * dv
			if distance_squared > limit:
				continue
			offsets.append({"u": u, "v": v, "distance": sqrt(distance_squared)})
	return offsets


static func disk_outline(size: int) -> PackedVector3Array:
	var use_size := clampi(size, 1, 64)
	var cells := {}
	for entry in disk_offsets(use_size):
		cells[Vector2i(entry["u"], entry["v"])] = true
	var vertices := PackedVector3Array()
	var edges := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for key in cells:
		for edge in edges:
			if cells.has(key + edge):
				continue
			var edge_midpoint := Vector3(key.x + 0.5 * edge.x, key.y + 0.5 * edge.y, 0.0)
			var half := Vector3(-0.5 * edge.y, 0.5 * edge.x, 0.0)
			vertices.append(edge_midpoint - half)
			vertices.append(edge_midpoint + half)
	return vertices


static func radius_to_size(radius: int) -> int:
	return maxi(MIN_SIZE, 2 * radius + 1)


static func size_to_radius(size: int) -> int:
	return (size - 1) / 2

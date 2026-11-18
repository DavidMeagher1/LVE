extends RefCounted


const NEIGHBOR_OFFSETS := [
	Vector3i(-1, 0, 0), Vector3i(1, 0, 0),
	Vector3i(0, -1, 0), Vector3i(0, 1, 0),
	Vector3i(0, 0, -1), Vector3i(0, 0, 1),
]

const KERNEL_RADIUS := 1

const BROAD_RADIUS := 2

const THIN_MULTIPLIER := 3

const MAX_ROUNDING_RADIUS := 4

const REMOVE_THRESHOLD := 0.5
const ADD_THRESHOLD := 0.5

const MAX_PASSES_PER_CALL := 8

const CHECKPOINT_INTERVAL := 512

static var _kernel_cache := {}
static var _ball_cache := {}
static var _read_cache := {}
static var _cache_lock := Mutex.new()


static func surface_normal(occupied: Dictionary, cell: Vector3i) -> Variant:
	var gradient := Vector3i.ZERO
	for offset: Vector3i in NEIGHBOR_OFFSETS:
		if occupied.has(cell + offset):
			gradient += offset
	if gradient == Vector3i.ZERO:
		return null
	return -Vector3(gradient).normalized()


static func _has_face_neighbor(occupied: Dictionary, cell: Vector3i) -> bool:
	for offset: Vector3i in NEIGHBOR_OFFSETS:
		if occupied.has(cell + offset):
			return true
	return false


static func occupied_fraction(occupied: Dictionary, cell: Vector3i, radius := KERNEL_RADIUS) -> float:
	var offsets: Array = kernel_offsets(radius)
	var count := 0
	for offset: Vector3i in offsets:
		if occupied.has(cell + offset):
			count += 1
	return float(count) / float(offsets.size())


static func kernel_offsets(radius: int) -> Array:
	var use_radius := maxi(radius, 1)
	_cache_lock.lock()
	if _kernel_cache.has(use_radius):
		var cached: Array = _kernel_cache[use_radius]
		_cache_lock.unlock()
		return cached
	var offsets: Array = []
	for x in range(-use_radius, use_radius + 1):
		for y in range(-use_radius, use_radius + 1):
			for z in range(-use_radius, use_radius + 1):
				offsets.append(Vector3i(x, y, z))
	offsets.make_read_only()
	_kernel_cache[use_radius] = offsets
	_cache_lock.unlock()
	return offsets


static func ball_offsets(radius: int) -> Array:
	var use_radius := clampi(radius, 1, 2 * MAX_ROUNDING_RADIUS)
	_cache_lock.lock()
	if not _ball_cache.has(use_radius):
		var offsets: Array = []
		var squared := use_radius * use_radius
		for x in range(-use_radius, use_radius + 1):
			for y in range(-use_radius, use_radius + 1):
				for z in range(-use_radius, use_radius + 1):
					var point := Vector3i(x, y, z)
					if point.length_squared() <= squared:
						offsets.append(point)
		offsets.sort_custom(_order_offsets)
		_ball_cache[use_radius] = offsets
	var cached: Array = _ball_cache[use_radius]
	_cache_lock.unlock()
	return cached.duplicate()


static func required_halo(radius: int) -> int:
	if radius < BROAD_RADIUS:
		return 1
	var use_radius := clampi(radius, 1, MAX_ROUNDING_RADIUS)
	return maxi(2 * use_radius, THIN_MULTIPLIER * use_radius)


static func read_offsets(radius: int) -> Array:
	if radius < BROAD_RADIUS:
		return kernel_offsets(1).duplicate()
	var use_radius := clampi(radius, 1, MAX_ROUNDING_RADIUS)
	var ball := ball_offsets(use_radius * 2)
	_cache_lock.lock()
	if not _read_cache.has(use_radius):
		var seen := {}
		for offset: Vector3i in ball:
			seen[offset] = true
		var reach := THIN_MULTIPLIER * use_radius
		for axis in 3:
			for step in range(1, reach + 1):
				seen[NEIGHBOR_OFFSETS[axis * 2] * step] = true
				seen[NEIGHBOR_OFFSETS[axis * 2 + 1] * step] = true
		var offsets: Array = seen.keys()
		offsets.sort_custom(_order_offsets)
		_read_cache[use_radius] = offsets
	var cached: Array = _read_cache[use_radius]
	_cache_lock.unlock()
	return cached.duplicate()


static func _order_offsets(a: Vector3i, b: Vector3i) -> bool:
	var distance_a := a.length_squared()
	var distance_b := b.length_squared()
	if distance_a != distance_b:
		return distance_a < distance_b
	if a.z != b.z:
		return a.z < b.z
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x


static func weighted_pass(occupied: Dictionary, cells: Array, budget: Dictionary, pass_index: int, radius := KERNEL_RADIUS, remove_threshold := REMOVE_THRESHOLD, add_threshold := ADD_THRESHOLD, cancel := Callable()) -> Dictionary:
	var use_radius := clampi(radius, 1, MAX_ROUNDING_RADIUS)
	var broad := use_radius >= BROAD_RADIUS
	var ball: Array = []
	if broad:
		ball = ball_offsets(use_radius)
	var host_memo := {}
	var touch_memo := {}
	var base_radius := mini(radius, KERNEL_RADIUS)
	var remove := []
	var add := []
	var evaluated := []
	var completed := 0
	for cell: Vector3i in cells:
		if pass_index >= int(budget.get(cell, 0)):
			continue
		evaluated.append(cell)
		completed += 1
		if cancel.is_valid() and completed % CHECKPOINT_INTERVAL == 0 and not cancel.call(completed):
			return {"cancelled": true}
		if surface_normal(occupied, cell) == null:
			if occupied.has(cell) and not _has_face_neighbor(occupied, cell):
				remove.append(cell)
			continue
		if occupied.has(cell):
			if _protected_thin(occupied, cell):
				continue
			if broad and not _thin_solid(occupied, cell, use_radius):
				var normal: Vector3 = surface_normal(occupied, cell)
				var inward := -Vector3i(int(signf(normal.x)), int(signf(normal.y)), int(signf(normal.z)))
				if not _covered(occupied, host_memo, ball, cell, inward):
					remove.append(cell)
			elif occupied_fraction(occupied, cell, base_radius) < remove_threshold:
				remove.append(cell)
		else:
			if broad and not _thin_around(occupied, cell, use_radius) and _enclosed(occupied, touch_memo, ball, cell):
				add.append(cell)
			elif occupied_fraction(occupied, cell, base_radius) > add_threshold:
				add.append(cell)
	remove.sort()
	add.sort()
	return {"remove": remove, "add": add, "evaluated": evaluated}


static func _covered(occupied: Dictionary, memo: Dictionary, ball: Array, cell: Vector3i, inward: Vector3i) -> bool:
	var direction := Vector3(inward)
	for offset: Vector3i in ball:
		if Vector3(offset).dot(direction) >= 0.0 and _hosts(occupied, memo, ball, cell + offset):
			return true
	for offset: Vector3i in ball:
		if Vector3(offset).dot(direction) < 0.0 and _hosts(occupied, memo, ball, cell + offset):
			return true
	return false


static func _enclosed(occupied: Dictionary, memo: Dictionary, ball: Array, cell: Vector3i) -> bool:
	for index in range(ball.size() - 1, -1, -1):
		if not _touches(occupied, memo, ball, cell + ball[index]):
			return false
	return true


static func _hosts(occupied: Dictionary, memo: Dictionary, ball: Array, cell: Vector3i) -> bool:
	if memo.has(cell):
		return memo[cell]
	var result := true
	for offset: Vector3i in NEIGHBOR_OFFSETS:
		if not occupied.has(cell + offset):
			result = false
			break
	if result:
		for offset: Vector3i in ball:
			if not occupied.has(cell + offset):
				result = false
				break
	memo[cell] = result
	return result


static func _touches(occupied: Dictionary, memo: Dictionary, ball: Array, cell: Vector3i) -> bool:
	if memo.has(cell):
		return memo[cell]
	var result := false
	for offset: Vector3i in ball:
		if occupied.has(cell + offset):
			result = true
			break
	memo[cell] = result
	return result


static func _thin_solid(occupied: Dictionary, cell: Vector3i, radius: int) -> bool:
	var limit := THIN_MULTIPLIER * clampi(radius, 1, MAX_ROUNDING_RADIUS)
	for axis in 3:
		var negative := _run(occupied, cell, NEIGHBOR_OFFSETS[axis * 2], limit)
		if negative >= limit:
			continue
		var positive := _run(occupied, cell, NEIGHBOR_OFFSETS[axis * 2 + 1], limit)
		if positive >= limit:
			continue
		if 1 + negative + positive <= limit:
			return true
	return false


static func _thin_around(occupied: Dictionary, cell: Vector3i, radius: int) -> bool:
	var limit := THIN_MULTIPLIER * clampi(radius, 1, MAX_ROUNDING_RADIUS)
	for axis in 3:
		var negative := _run(occupied, cell, NEIGHBOR_OFFSETS[axis * 2], limit)
		var positive := _run(occupied, cell, NEIGHBOR_OFFSETS[axis * 2 + 1], limit)
		if negative == 0 and positive == 0:
			continue
		if negative >= limit or positive >= limit:
			continue
		if negative + positive <= limit:
			return true
	return false


static func _run(occupied: Dictionary, cell: Vector3i, direction: Vector3i, limit: int) -> int:
	var length := 0
	var point := cell
	while length < limit and occupied.has(point + direction):
		point += direction
		length += 1
	return length


static func _protected_thin(occupied: Dictionary, cell: Vector3i) -> bool:
	var opposite_empty := false
	var supported := false
	for axis in 3:
		var negative := occupied.has(cell + NEIGHBOR_OFFSETS[axis * 2])
		var positive := occupied.has(cell + NEIGHBOR_OFFSETS[axis * 2 + 1])
		if not negative and not positive:
			opposite_empty = true
		elif negative and positive:
			supported = true
	return opposite_empty and supported


static func relax(occupied: Dictionary, cells: Array, passes := 1, radius := KERNEL_RADIUS, remove_threshold := REMOVE_THRESHOLD, add_threshold := ADD_THRESHOLD, weights := {}, cancel := Callable()) -> Dictionary:
	var current := occupied.duplicate()
	var ordered := cells.duplicate()
	ordered.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y if a.y != b.y else (a.z < b.z if a.z != b.z else a.x < b.x))
	var use_passes := maxi(passes, 0)
	var budget := {}
	for cell: Vector3i in ordered:
		budget[cell] = roundi(float(use_passes) * clampf(float(weights.get(cell, 1.0)), 0.0, 1.0))
	for pass_index in use_passes:
		var outcome := weighted_pass(current, ordered, budget, pass_index, radius, remove_threshold, add_threshold, cancel)
		if outcome.has("cancelled"):
			return {"occupied": occupied.duplicate(), "remove": [], "add": [], "cancelled": true}
		for cell: Vector3i in outcome["remove"]:
			current.erase(cell)
		for cell: Vector3i in outcome["add"]:
			current[cell] = true
		if not (outcome["remove"] as Array).is_empty() or not (outcome["add"] as Array).is_empty():
			var completed := 0
			for cell: Vector3i in outcome["evaluated"]:
				if current.has(cell) and not _has_face_neighbor(current, cell):
					current.erase(cell)
				completed += 1
				if cancel.is_valid() and completed % CHECKPOINT_INTERVAL == 0 and not cancel.call(completed):
					return {"occupied": occupied.duplicate(), "remove": [], "add": [], "cancelled": true}
	var remove := []
	var add := []
	for cell: Vector3i in cells:
		var before := occupied.has(cell)
		var after := current.has(cell)
		if before and not after:
			remove.append(cell)
		elif not before and after:
			add.append(cell)
	remove.sort()
	add.sort()
	return {"occupied": current, "remove": remove, "add": add}


static func advance(occupied: Dictionary, cells: Array, passes: int, radius := KERNEL_RADIUS, remove_threshold := REMOVE_THRESHOLD, add_threshold := ADD_THRESHOLD, weights := {}, cancel := Callable()) -> Dictionary:
	if cells.is_empty():
		return {"occupied": occupied.duplicate(), "remove": [], "add": [], "passes": 0}
	var use_passes := mini(maxi(passes, 0), MAX_PASSES_PER_CALL)
	var outcome := relax(occupied, cells, use_passes, radius, remove_threshold, add_threshold, weights, cancel)
	outcome["passes"] = use_passes
	return outcome

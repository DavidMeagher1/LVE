class_name TerrainGeometry
extends RefCounted

const BrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")
const VoxelFalloff := preload("res://Globals/State/Tools/VoxelFalloff.gd")


const MIN_NORMAL_TILT := 0.3
const AXIS_TIE_EPSILON := 1e-3
const READ_CANCEL_CHECKPOINT := 32

static func axis_of(step: Vector3i) -> int:
	for axis in 3:
		if step[axis] != 0:
			return axis
	return -1


static func read_depth(radius: int) -> int:
	return mini(64, maxi(16, maxi(radius, 1)))


static func cardinal_axis(direction: Vector3) -> int:
	for axis in 3:
		if direction[axis] == 0.0:
			continue
		for other in 3:
			if other != axis and direction[other] != 0.0:
				return -1
		return axis
	return -1


static func dominant_axis(vector: Vector3) -> int:
	var axis := 0
	var best := absf(vector.x)
	if absf(vector.y) > best + AXIS_TIE_EPSILON:
		axis = 1
		best = absf(vector.y)
	if absf(vector.z) > best + AXIS_TIE_EPSILON:
		axis = 2
	return axis


static func sign_of(step: Vector3i, axis: int) -> int:
	return 1 if step[axis] >= 0 else -1


static func column_key(cell: Vector3i, normal: Vector3) -> Vector3i:
	var axis := dominant_axis(normal)
	var sign_bit := 1 if normal[axis] >= 0.0 else 0
	return Vector3i(axis * 2 + sign_bit, cell[(axis + 1) % 3], cell[(axis + 2) % 3])


static func dominant_step(surface: Vector3i, normal: Vector3, direction: int) -> Vector3i:
	var axis := dominant_axis(normal)
	var sign := 1 if normal[axis] >= 0.0 else -1
	if direction < 0:
		sign = -sign
	var cell := surface
	cell[axis] += sign
	return cell


static func build_layer_cells(frame: VoxelFrame, changes: Dictionary, surface: Vector3i, normal: Vector3, seed: Vector3i, add: bool, selection: Dictionary) -> Dictionary:
	var cells: Array[Vector3i] = []
	if surface == VoxelPicking.NONE:
		if not add:
			return {"cells": cells, "next": VoxelPicking.NONE}
		if is_occupied(frame, changes, seed) or not allows(selection, seed):
			return {"cells": cells, "next": VoxelPicking.NONE}
		cells.append(seed)
		return {"cells": cells, "next": seed}
	if add:
		var destination := dominant_step(surface, normal, 1)
		if is_occupied(frame, changes, destination) or not allows(selection, destination):
			return {"cells": cells, "next": VoxelPicking.NONE}
		cells.append(destination)
		return {"cells": cells, "next": destination}
	if not allows(selection, surface):
		return {"cells": cells, "next": VoxelPicking.NONE}
	cells.append(surface)
	var inward := dominant_step(surface, normal, -1)
	var next := VoxelPicking.NONE
	if is_occupied(frame, changes, inward):
		next = inward
	return {"cells": cells, "next": next}


static func disk_inner(size: int) -> float:
	var center := BrushSize.center_offset(clampi(size, 1, 64))
	var offset := absf(float(roundi(center)) - center)
	return offset * sqrt(2.0)


static func cell_at(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x), roundi(point.y), roundi(point.z))


static func resolve_samples(candidates: Array) -> Dictionary:
	var built := {}
	var claim_owner := {}
	for row in candidates:
		var anchor: Vector3i = row["anchor"]
		var claim: Vector3i = row["claim"]
		var weight := float(row["weight"])
		if claim_owner.has(claim):
			var owner: Vector3i = claim_owner[claim]
			if float(built[owner]["weight"]) >= weight:
				continue
			claim_owner.erase(claim)
			built.erase(owner)
		if built.has(anchor):
			var previous: Vector3i = built[anchor]["claim"]
			claim_owner.erase(previous)
		built[anchor] = row
		claim_owner[claim] = anchor
	return built


static func disk_offsets(size: int) -> Array:
	var use_size := clampi(size, 1, 64)
	_disk_lock.lock()
	var cached: Array = _disk_cache.get(use_size, [])
	_disk_lock.unlock()
	if not cached.is_empty():
		return cached
	var offsets := BrushSize.disk_offsets(use_size)
	for entry in offsets:
		entry.make_read_only()
	offsets.make_read_only()
	_disk_lock.lock()
	var existing: Array = _disk_cache.get(use_size, [])
	if existing.is_empty():
		_disk_cache[use_size] = offsets
		cached = offsets
	else:
		cached = existing
	_disk_lock.unlock()
	return cached


static var _disk_cache := {}
static var _disk_lock := Mutex.new()


static func sphere_offsets(size: int) -> Array:
	var use_size := clampi(size, 1, 64)
	_disk_lock.lock()
	var cached: Array = _sphere_cache.get(use_size, [])
	_disk_lock.unlock()
	if not cached.is_empty():
		return cached
	var radius := float(use_size) * 0.5
	var limit := ceili(radius)
	var squared := radius * radius
	var offsets := []
	for x in range(-limit, limit + 1):
		for y in range(-limit, limit + 1):
			for z in range(-limit, limit + 1):
				var cell := Vector3i(x, y, z)
				if cell.length_squared() > squared:
					continue
				var entry := {"offset": cell, "distance": Vector3(cell).length()}
				entry.make_read_only()
				offsets.append(entry)
	offsets.make_read_only()
	_disk_lock.lock()
	var existing: Array = _sphere_cache.get(use_size, [])
	if existing.is_empty():
		_sphere_cache[use_size] = offsets
		cached = offsets
	else:
		cached = existing
	_disk_lock.unlock()
	return cached


static var _sphere_cache := {}


static func march_cells(origin: Vector3, direction: Vector3, steps: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if steps <= 0 or direction == Vector3.ZERO:
		return cells
	var dir := direction.normalized()
	var g := origin + Vector3(0.5, 0.5, 0.5)
	var cell := Vector3i(floori(g.x), floori(g.y), floori(g.z))
	cells.append(cell)
	var step := Vector3i(
		1 if dir.x > 0.0 else -1, 1 if dir.y > 0.0 else -1, 1 if dir.z > 0.0 else -1
	)
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	for axis in 3:
		if dir[axis] == 0.0:
			continue
		t_delta[axis] = absf(1.0 / dir[axis])
		t_max[axis] = ((float(cell[axis]) + (1.0 if step[axis] > 0 else 0.0)) - g[axis]) / dir[axis]
	for _index in steps:
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			t_max.z += t_delta.z
		cells.append(cell)
	return cells


static func next_cell(cell_position: Vector3i, direction: Vector3, ray_origin := Vector3.INF) -> Vector3i:
	if direction == Vector3.ZERO:
		return cell_position
	var origin := Vector3(cell_position) if ray_origin == Vector3.INF else ray_origin
	var crossing := Vector3(INF, INF, INF)
	var step := Vector3i.ZERO
	for axis in 3:
		if direction[axis] == 0.0:
			continue
		step[axis] = 1 if direction[axis] > 0.0 else -1
		var boundary := float(cell_position[axis]) + 0.5 * float(step[axis])
		crossing[axis] = (boundary - origin[axis]) / direction[axis]
	var exit_axis := 2
	if crossing.x < crossing.y and crossing.x < crossing.z:
		exit_axis = 0
	elif crossing.y < crossing.z:
		exit_axis = 1
	var next := cell_position
	next[exit_axis] += step[exit_axis]
	return next


static func previous_cell(cell_position: Vector3i, direction: Vector3, ray_origin := Vector3.INF) -> Vector3i:
	return next_cell(cell_position, -direction, ray_origin)


static func surface_along(frame: VoxelFrame, point: Vector3, normal: Vector3, depth: int, changes := {}, context: TerrainQueryContext = null) -> Vector3i:
	if normal == Vector3.ZERO:
		return VoxelPicking.NONE
	if changes.is_empty() and (frame == null or frame.chunks.is_empty()):
		return VoxelPicking.NONE
	var use_depth := maxi(depth, 0)
	var g := point + Vector3(0.5, 0.5, 0.5)
	var origin_cell := Vector3i(floori(g.x), floori(g.y), floori(g.z))
	if context != null and changes.is_empty():
		var cardinal := cardinal_axis(normal)
		if cardinal >= 0 and context.column_empty(cardinal, origin_cell):
			return VoxelPicking.NONE
		if context.misses_bounds(point, normal):
			return VoxelPicking.NONE
	var nearest := VoxelPicking.NONE
	var first_distance := 1
	if is_occupied(frame, changes, origin_cell):
		nearest = origin_cell
	elif use_depth >= 1:
		nearest = _first_neighbor_along(frame, changes, origin_cell, normal, point)
		first_distance = 2
	if nearest == VoxelPicking.NONE:
		if use_depth < first_distance:
			return nearest
		var outward := SurfaceWalk.new(point, normal)
		var inward: SurfaceWalk = null
		for _index in first_distance:
			outward.advance()
		for distance in range(first_distance, use_depth + 1):
			if is_occupied(frame, changes, outward.cell):
				nearest = outward.cell
				break
			if inward == null:
				inward = SurfaceWalk.new(point, -normal)
				for _index in first_distance:
					inward.advance()
			if is_occupied(frame, changes, inward.cell):
				nearest = inward.cell
				break
			outward.advance()
			inward.advance()
	if nearest == VoxelPicking.NONE:
		return nearest
	var current := nearest
	var walked := 0
	while walked < use_depth + 1:
		var next := next_cell(current, normal, point)
		if not is_occupied(frame, changes, next):
			break
		current = next
		walked += 1
	if is_occupied(frame, changes, next_cell(current, normal, point)):
		return VoxelPicking.NONE
	return current


class SurfaceWalk extends RefCounted:
	var cell := Vector3i.ZERO
	var step := Vector3i.ZERO
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)

	func _init(origin: Vector3, direction: Vector3) -> void:
		var dir := direction.normalized()
		var g := origin + Vector3(0.5, 0.5, 0.5)
		cell = Vector3i(floori(g.x), floori(g.y), floori(g.z))
		step = Vector3i(
			1 if dir.x > 0.0 else -1, 1 if dir.y > 0.0 else -1, 1 if dir.z > 0.0 else -1
		)
		for axis in 3:
			if dir[axis] == 0.0:
				continue
			t_delta[axis] = absf(1.0 / dir[axis])
			t_max[axis] = ((float(cell[axis]) + (1.0 if step[axis] > 0 else 0.0)) - g[axis]) / dir[axis]

	func advance() -> void:
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			t_max.z += t_delta.z


static func _first_neighbor_along(frame: VoxelFrame, changes: Dictionary, origin_cell: Vector3i, normal: Vector3, point: Vector3) -> Vector3i:
	var outward := next_cell(origin_cell, normal, point)
	if is_occupied(frame, changes, outward):
		return outward
	var inward := next_cell(origin_cell, -normal, point)
	if is_occupied(frame, changes, inward):
		return inward
	return VoxelPicking.NONE


static func is_occupied(frame: VoxelFrame, changes: Dictionary, cell_position: Vector3i) -> bool:
	if changes.has(cell_position):
		var changed: PackedFloat32Array = changes[cell_position]
		return not VoxelFrame.is_empty(changed)
	return frame != null and frame.has(cell_position)


static func allows(selection: Dictionary, cell_position: Vector3i) -> bool:
	return selection.is_empty() or selection.has(cell_position)


static func flatten_action(frame: VoxelFrame, changes: Dictionary, surface: Vector3i, normal: Vector3, anchor: Vector3i, plane_origin: Vector3, threshold: float, selection: Dictionary) -> Dictionary:
	if surface == VoxelPicking.NONE:
		var axis := dominant_axis(normal)
		var sign := 1 if normal[axis] >= 0.0 else -1
		var plane_seed := anchor
		plane_seed[axis] = roundi(plane_origin[axis] - float(sign) * 0.5)
		if is_occupied(frame, changes, plane_seed) or not allows(selection, plane_seed):
			return {"cell": VoxelPicking.NONE}
		return {"cell": plane_seed, "add": true, "seed": true}
	var distance := (Vector3(surface) - plane_origin).dot(normal)
	if absf(distance + 0.5) <= threshold:
		return {"cell": VoxelPicking.NONE, "settled": true}
	if distance + 0.5 > 0.0:
		if not allows(selection, surface):
			return {"cell": VoxelPicking.NONE}
		return {"cell": surface, "add": false}
	var destination := dominant_step(surface, normal, 1)
	if is_occupied(frame, changes, destination) or not allows(selection, destination):
		return {"cell": VoxelPicking.NONE}
	return {"cell": destination, "add": true}


static func surface_points(frame: VoxelFrame, hit: Vector3i, entry: Vector3i, radius: int, job: VoxelFrame.EditJob = null, context: TerrainQueryContext = null) -> Array:
	var points := []
	if frame == null or entry == Vector3i.ZERO:
		return points
	var entry_normal := Vector3(entry).normalized()
	var use_radius := maxi(radius, 1)
	var axis := axis_of(entry)
	var u_axis := (axis + 1) % 3
	var v_axis := (axis + 2) % 3
	var columns := {}
	var completed := 0
	for offset in disk_offsets(use_radius):
		var point := Vector3(hit)
		point[u_axis] += float(offset["u"])
		point[v_axis] += float(offset["v"])
		var surface := surface_along(frame, point, entry_normal, read_depth(use_radius), {}, context)
		completed += 1
		if job != null and completed % READ_CANCEL_CHECKPOINT == 0 and not job.checkpoint(completed):
			return []
		if surface == VoxelPicking.NONE:
			continue
		var key := Vector2i(offset["u"], offset["v"])
		columns[key] = {
			"point": Vector3(surface) + entry_normal * 0.5,
			"weight": VoxelFalloff.weight_at(offset["distance"], float(use_radius), 0.5, disk_inner(use_radius)),
		}
	var queue: Array[Vector2i] = [Vector2i.ZERO]
	var visited := {Vector2i.ZERO: true}
	var index := 0
	while index < queue.size():
		var key := queue[index]
		index += 1
		if not columns.has(key):
			continue
		points.append(columns[key])
		for offset: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var neighbor := key + offset
			if not visited.has(neighbor) and columns.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)
	return points


static func surface_gradient(points: Array, seed: Vector3) -> Dictionary:
	if seed == Vector3.ZERO:
		return {"ok": false}
	var axis := dominant_axis(seed)
	var height_axis := Vector3.ZERO
	height_axis[axis] = 1.0 if seed[axis] >= 0.0 else -1.0
	var u := Vector3.ZERO
	u[(axis + 1) % 3] = 1.0
	var v := Vector3.ZERO
	v[(axis + 2) % 3] = 1.0
	var centroid := Vector3.ZERO
	var total := 0.0
	for sample in points:
		var weight: float = sample["weight"]
		total += weight
		centroid += (sample["point"] as Vector3) * weight
	if total <= 0.0:
		return {"ok": false}
	centroid /= total
	var uu := 0.0
	var uv := 0.0
	var vv := 0.0
	var uh := 0.0
	var vh := 0.0
	for sample in points:
		var delta: Vector3 = sample["point"] - centroid
		var weight: float = sample["weight"]
		var x := delta.dot(u)
		var y := delta.dot(v)
		var height := delta.dot(height_axis)
		uu += weight * x * x
		uv += weight * x * y
		vv += weight * y * y
		uh += weight * x * height
		vh += weight * y * height
	var determinant := uu * vv - uv * uv
	if determinant <= 1e-6 * maxf(1.0, uu * vv):
		return {"ok": false}
	var slope_u := (uh * vv - vh * uv) / determinant
	var slope_v := (vh * uu - uh * uv) / determinant
	var normal := (height_axis - slope_u * u - slope_v * v).normalized()
	if normal.dot(seed) < MIN_NORMAL_TILT:
		return {"ok": false}
	return {"ok": true, "normal": normal, "centroid": centroid}

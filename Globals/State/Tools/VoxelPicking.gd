class_name VoxelPicking
extends RefCounted


const NONE:Vector3i = Vector3i(Vector3.INF)

static func start_pick(origin: Vector3, dir: Vector3, frame: VoxelFrame, forward: Vector3, slice := false) -> PickResult:
	if slice:
		var sliced := ray_voxel(origin, dir, frame, AABB(), State.floor_axis, State.slice_first(), State.slice_count())
		if sliced.hit != VoxelPicking.NONE:
			sliced.target = sliced.hit
			sliced.add_target = sliced.hit + sliced.entry
			sliced.plane = view_plane(sliced.target, origin, forward)
			return sliced
		return slice_pick(origin, dir, frame)
	var res := ray_voxel(origin, dir, frame)
	if res.hit != VoxelPicking.NONE:
		res.target = res.hit
		res.add_target = res.hit + res.entry
		res.plane = view_plane(res.target, origin, forward)
		return res
	return ground_pick(origin, dir, forward)


static func slice_pick(origin: Vector3, dir: Vector3, frame: VoxelFrame) -> PickResult:
	var axis := State.floor_axis
	var denom := dir[axis]
	if absf(denom) < 1e-8:
		return PickResult.new()
	var level := State.slice_level()
	var t: float = (level - origin[axis]) / denom
	if t <= 0.0:
		return PickResult.new()
	var point: Vector3 = origin + dir * t
	var cell := Vector3i(floori(point.x + 0.5), floori(point.y + 0.5), floori(point.z + 0.5))
	cell[axis] = State.floor_index
	var res := PickResult.new()
	res.target = cell
	res.add_target = cell
	res.hit = cell if frame != null and frame.has(cell) else VoxelPicking.NONE
	res.plane = slice_plane()
	return res


static func slice_plane() -> StrokePlane:
	var axis := State.floor_axis
	var plane := StrokePlane.new()
	plane.axis = axis
	plane.cell_index = State.floor_index
	var point := Vector3.ZERO
	point[axis] = State.slice_level()
	plane.point = point
	var normal := Vector3.ZERO
	normal[axis] = 1.0
	plane.normal = normal
	return plane


static func drag_pick(origin: Vector3, dir: Vector3, frame: VoxelFrame, plane: StrokePlane) -> PickResult:
	var denom := dir.dot(plane.normal)
	if absf(denom) < 1e-8:
		return PickResult.new()
	var t: float = (plane.point - origin).dot(plane.normal) / denom
	if t <= 0.0:
		return PickResult.new()
	var gp: Vector3 = origin + dir * t
	var c := Vector3i(int(floori(gp.x + 0.5)), int(floori(gp.y + 0.5)), int(floori(gp.z + 0.5)))
	c[plane.axis] = plane.cell_index
	var res := PickResult.new()
	res.target = c
	res.hit = c if frame != null and frame.has(c) else VoxelPicking.NONE
	return res


static func view_axis(forward: Vector3) -> int:
	var toward: Vector3 = -forward
	var x := absf(toward.x)
	var y := absf(toward.y)
	var z := absf(toward.z)
	if y >= x and y >= z:
		return 1
	if z >= x:
		return 2
	return 0


static func view_plane(target: Vector3i, origin: Vector3, forward: Vector3) -> StrokePlane:
	var axis := view_axis(forward)
	var side := 1.0 if origin[axis] >= float(target[axis]) else -1.0
	var plane := StrokePlane.new()
	plane.axis = axis
	plane.cell_index = target[axis]
	var pt := Vector3.ZERO
	pt[axis] += float(target[axis]) + 0.5 * side
	plane.point = pt
	var n := Vector3.ZERO
	n[axis] = 1.0
	plane.normal = n
	return plane


static func view_plane_through(point: Vector3, forward: Vector3) -> StrokePlane:
	var plane := StrokePlane.new()
	plane.axis = view_axis(forward)
	plane.cell_index = 0
	plane.point = point
	var n := Vector3.ZERO
	n[plane.axis] = 1.0
	plane.normal = n
	return plane


static func ray_voxel(origin: Vector3, dir: Vector3, frame: VoxelFrame, supplied_bounds := AABB(), slice_axis := -1, slice_first := 0, slice_count := 0) -> PickResult:
	var res := PickResult.new()
	if frame == null:
		return res
	if dir == Vector3.ZERO:
		return res
	var bounds := supplied_bounds
	if not bounds.has_volume():
		bounds = frame.get_bounds()
	if not bounds.has_volume():
		return res
	var shifted_origin := origin + Vector3(0.5, 0.5, 0.5)
	var lo := bounds.position + Vector3(0.5, 0.5, 0.5)
	var hi := bounds.end + Vector3(0.5, 0.5, 0.5)
	var t_enter := -INF
	var t_exit := INF
	for axis in 3:
		var d: float = dir[axis]
		if d == 0.0:
			if shifted_origin[axis] < lo[axis] or shifted_origin[axis] > hi[axis]:
				return res
			continue
		var near: float = (lo[axis] - shifted_origin[axis]) / d
		var far: float = (hi[axis] - shifted_origin[axis]) / d
		if near > far:
			var swap := near
			near = far
			far = swap
		t_enter = maxf(t_enter, near)
		t_exit = minf(t_exit, far)
	if t_enter > t_exit or t_exit <= 0.0:
		return res
	var step := Vector3i(
		1 if dir.x > 0.0 else -1, 1 if dir.y > 0.0 else -1, 1 if dir.z > 0.0 else -1
	)
	var cell_min := Vector3i(floori(lo.x), floori(lo.y), floori(lo.z))
	var cell_max := Vector3i(floori(hi.x) - 1, floori(hi.y) - 1, floori(hi.z) - 1)
	var t := 0.0
	var entry := Vector3i.ZERO
	var cell := Vector3i(floori(shifted_origin.x), floori(shifted_origin.y), floori(shifted_origin.z))
	if t_enter > 0.0:
		t = t_enter
		cell = _entry_cell(shifted_origin + dir * t_enter, dir)
		cell = Vector3i(
			clampi(cell.x, cell_min.x, cell_max.x),
			clampi(cell.y, cell_min.y, cell_max.y),
			clampi(cell.z, cell_min.z, cell_max.z)
		)
		entry = _entry_face(shifted_origin, dir, lo, hi, step)
	var t_max := Vector3(INF, INF, INF)
	var t_delta := Vector3(INF, INF, INF)
	if dir.x != 0.0:
		t_delta.x = absf(1.0 / dir.x)
		t_max.x = ((float(cell.x) + (1.0 if step.x > 0 else 0.0)) - shifted_origin.x) / dir.x
	if dir.y != 0.0:
		t_delta.y = absf(1.0 / dir.y)
		t_max.y = ((float(cell.y) + (1.0 if step.y > 0 else 0.0)) - shifted_origin.y) / dir.y
	if dir.z != 0.0:
		t_delta.z = absf(1.0 / dir.z)
		t_max.z = ((float(cell.z) + (1.0 if step.z > 0 else 0.0)) - shifted_origin.z) / dir.z
	var extent := cell_max - cell_min + Vector3i.ONE
	var max_steps := extent.x + extent.y + extent.z + 2
	for i in max_steps:
		if frame.has(cell) and (slice_axis < 0 or (cell[slice_axis] >= slice_first and cell[slice_axis] < slice_first + slice_count)):
			res.hit = cell
			res.entry = entry
			return res
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			entry = Vector3i(-step.x, 0, 0)
			t = t_max.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			entry = Vector3i(0, -step.y, 0)
			t = t_max.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			entry = Vector3i(0, 0, -step.z)
			t = t_max.z
			t_max.z += t_delta.z
		if t > t_exit:
			break
	return res


static func _entry_cell(point: Vector3, dir: Vector3) -> Vector3i:
	var cell := Vector3i.ZERO
	for axis in 3:
		cell[axis] = ceili(point[axis]) - 1 if dir[axis] < 0.0 else floori(point[axis])
	return cell


static func _entry_face(shifted_origin: Vector3, dir: Vector3, lo: Vector3, hi: Vector3, step: Vector3i) -> Vector3i:
	var axis := -1
	var nearest := -INF
	for a in 3:
		var d: float = dir[a]
		if d == 0.0:
			continue
		var near: float = (lo[a] - shifted_origin[a]) / d if d > 0.0 else (hi[a] - shifted_origin[a]) / d
		if near > nearest:
			nearest = near
			axis = a
	var entry := Vector3i.ZERO
	if axis >= 0:
		entry[axis] = -step[axis]
	return entry


static func ground_pick(origin: Vector3, dir: Vector3, forward: Vector3) -> PickResult:
	var axis := State.floor_axis
	var denom := dir[axis]
	if absf(denom) < 1e-8:
		return PickResult.new()
	var level := float(State.floor_index) - 0.5
	var t: float = (level - origin[axis]) / denom
	if t <= 0.0:
		return PickResult.new()
	var p: Vector3 = origin + dir * t
	var c := Vector3i.ZERO
	for i in 3:
		if i != axis:
			c[i] = int(floori(p[i] + 0.5))
	if origin[axis] >= level:
		c[axis] = State.floor_index
	else:
		c[axis] = State.floor_index - 1
	var res := PickResult.new()
	res.target = c
	res.add_target = c
	res.plane = view_plane(c, origin, forward)
	return res

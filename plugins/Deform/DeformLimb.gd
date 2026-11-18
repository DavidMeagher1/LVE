extends RefCounted


const NEIGHBORS: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const NEIGHBORS_26: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 1, 0), Vector3i(1, -1, 0), Vector3i(-1, 1, 0), Vector3i(-1, -1, 0),
	Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1),
	Vector3i(0, 1, 1), Vector3i(0, 1, -1), Vector3i(0, -1, 1), Vector3i(0, -1, -1),
	Vector3i(1, 1, 1), Vector3i(1, 1, -1), Vector3i(1, -1, 1), Vector3i(1, -1, -1),
	Vector3i(-1, 1, 1), Vector3i(-1, 1, -1), Vector3i(-1, -1, 1), Vector3i(-1, -1, -1),
]
const JOINT_CELL_LIMIT := 2048
const CHECKPOINT := 512
const JOINT_EDGE_WEIGHT := 1.0
const JOINT_PLANE_WEIGHT := 3.0
const JOINT_FACE_WEIGHT := 1.0


static func masks_for(context: VoxelFrame.EditContext) -> Array:
	var masks := []
	if context == null:
		masks.append(0)
		return masks
	for mask in 8:
		if (mask & ~context.axes) == 0:
			masks.append(mask)
	return masks


static func joint_pivot(frame: VoxelFrame, anchor: Vector3i, size: int, context: VoxelFrame.EditContext, connected := false, view_forward := Vector3.ZERO, face_axis := -1, touch := Vector2.ZERO) -> Dictionary:
	var result := {"found": false, "pivot": Vector3(anchor), "bone_dir": Vector3.ZERO, "reach": 0.0}
	if frame == null or anchor == VoxelPicking.NONE or not frame.has(anchor):
		return result
	var origin := Vector3(anchor)
	var brush_reach := float(clampi(size, 1, 32)) * 0.5
	var ahead := view_forward.normalized()
	var touch_dir := Vector2.ZERO
	var touch_strength := 0.0
	if face_axis >= 0:
		var touch_length := touch.length()
		if touch_length > 0.0:
			touch_dir = touch / touch_length
			touch_strength = clampf(touch_length / 0.5, 0.0, 1.0)
	var axis_u := (face_axis + 1) % 3 if face_axis >= 0 else 0
	var axis_v := (face_axis + 2) % 3 if face_axis >= 0 else 0
	var offsets := NEIGHBORS
	if not connected:
		offsets = NEIGHBORS_26
	var visited := {anchor: true}
	var queue: Array[Vector3i] = [anchor]
	var head := 0
	var base := anchor
	var base_score := -INF
	while head < queue.size() and visited.size() < JOINT_CELL_LIMIT:
		var cell: Vector3i = queue[head]
		head += 1
		for offset: Vector3i in offsets:
			var next := cell + offset
			if visited.has(next):
				continue
			if Vector3(next).distance_to(origin) > brush_reach:
				continue
			if context != null and not context.allows(next):
				continue
			if not frame.has(next):
				continue
			visited[next] = true
			queue.append(next)
			var delta := Vector3(next) - origin
			var score := JOINT_EDGE_WEIGHT * (delta.length() / brush_reach)
			if ahead != Vector3.ZERO:
				score += JOINT_PLANE_WEIGHT * (1.0 - absf(delta.dot(ahead)) / brush_reach)
			if touch_strength > 0.0:
				var in_face := Vector2(delta[axis_u], delta[axis_v])
				var in_face_length := in_face.length()
				if in_face_length > 0.0:
					score += JOINT_FACE_WEIGHT * (in_face / in_face_length).dot(touch_dir) * touch_strength
			if score > base_score:
				base = next
				base_score = score
	if base == anchor:
		return result
	var bone := origin - Vector3(base)
	var reach := bone.length()
	if reach < 0.5:
		return result
	result["found"] = true
	result["bone_dir"] = bone / reach
	result["reach"] = reach
	result["pivot"] = Vector3(base)
	return result


static func capture_limb(frame: VoxelFrame, anchor: Vector3i, pivot: Vector3, bone_dir: Vector3, band: float, radius: float, limit: int, context: VoxelFrame.EditContext, connected := true, job: VoxelFrame.EditJob = null) -> Dictionary:
	var captured := {}
	if frame == null or anchor == VoxelPicking.NONE or bone_dir == Vector3.ZERO:
		return captured
	var cap := maxi(limit, 1)
	var reach := maxf(radius, 0.5)
	var reach_squared := reach * reach
	var origin := Vector3(anchor)
	var offsets := NEIGHBORS
	if not connected:
		offsets = NEIGHBORS_26
	var visited := {anchor: true}
	var queue: Array[Vector3i] = [anchor]
	var head := 0
	var completed := 0
	while head < queue.size():
		if captured.size() >= cap:
			break
		var cell: Vector3i = queue[head]
		head += 1
		if context != null and not context.allows(cell):
			continue
		if Vector3(cell).distance_squared_to(origin) > reach_squared:
			continue
		var along := (Vector3(cell) - pivot).dot(bone_dir)
		if along < 0.0:
			continue
		captured[cell] = limb_weight(along, band)
		if along <= 0.0:
			continue
		for offset: Vector3i in offsets:
			var next := cell + offset
			if visited.has(next) or not frame.has(next):
				continue
			visited[next] = true
			queue.append(next)
		completed += 1
		if job != null and completed % CHECKPOINT == 0 and not job.checkpoint(completed):
			return {}
	return captured


static func limb_weight(along: float, band: float) -> float:
	if band <= 0.0:
		return 1.0 if along >= 0.0 else 0.0
	var t := clampf((along + band) / (2.0 * band), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


const NECK_LIMIT := 2.0


static func joint_band(size: int, falloff: float) -> float:
	var use_size := float(clampi(size, 1, 32))
	return minf(lerpf(0.5, use_size, clampf(falloff, 0.0, 1.0)), NECK_LIMIT)


static func round_cell(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x), roundi(point.y), roundi(point.z))


static func turn_point(pose: Dictionary, cell: Vector3i, weight: float, angle := NAN) -> Vector3:
	var pivot: Vector3 = pose["pivot"]
	var use_angle: float = float(pose["angle"]) if is_nan(angle) else angle
	var axis: Vector3 = pose["axis"]
	return pivot + Basis(axis, use_angle * weight) * (Vector3(cell) - pivot)


static func screen_length(direction: Vector3, right: Vector3, up: Vector3) -> float:
	return Vector2(direction.dot(right), direction.dot(up)).length()


static func screen_vector(direction: Vector3, right: Vector3, up: Vector3) -> Vector2:
	return Vector2(direction.dot(right), direction.dot(up))


static func mask_handedness(mask: int) -> float:
	var odd := 0
	for axis in 3:
		if mask & (1 << axis):
			odd ^= 1
	return -1.0 if odd == 1 else 1.0


static func mirror_direction(direction: Vector3, mask: int) -> Vector3:
	var mirrored := direction
	for axis in 3:
		if mask & (1 << axis):
			mirrored[axis] = -mirrored[axis]
	return mirrored


static func mirror_point(point: Vector3, context: VoxelFrame.EditContext, mask: int) -> Vector3:
	if context == null or mask == 0:
		return point
	var origin := Vector3(context.origin_twice) * 0.5
	var mirrored := point - origin
	for axis in 3:
		if mask & (1 << axis):
			mirrored[axis] = -mirrored[axis]
	return mirrored + origin

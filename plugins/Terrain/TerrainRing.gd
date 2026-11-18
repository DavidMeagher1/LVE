extends RefCounted


const BrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")

const LIFT := 0.02
const MIN_SEGMENTS := 16
const MAX_SEGMENTS := 256
const SPLIT_DEPTH := 12
const SPLIT_ANGLE := 0.001
const CHECKPOINT := 32
const SLAB_EPSILON := 1e-6
const PLANE_EPSILON := 1e-4


static func segments_for(size: int) -> int:
	var use_size := BrushSize.clamp_size(size)
	return clampi(int(ceil(PI * float(use_size))), MIN_SEGMENTS, MAX_SEGMENTS)


static func depth_for(size: int) -> int:
	return clampi(BrushSize.clamp_size(size), 8, 64)


static func floor_ring_applies(tool: int, build_mode: int) -> bool:
	if tool == TerrainToolSettings.Tools.FLATTEN:
		return true
	return tool == TerrainToolSettings.Tools.BUILD and build_mode == TerrainToolSettings.BuildMode.ADD


static func surface_ring_data(frame: VoxelFrame, surface_frame: TerrainFrame, center_point: Vector3, size: int, context: VoxelFrame.EditContext, tester := Callable(), job: VoxelFrame.EditJob = null, query: TerrainQueryContext = null, lift := LIFT) -> Dictionary:
	var result := {
		"vertices": PackedVector3Array(), "segments": 0, "breaks": 0,
		"queries": 0, "samples": 0, "masks": 0,
	}
	if surface_frame == null:
		return result
	var use_size := BrushSize.clamp_size(size)
	var radius := BrushSize.radius(use_size)
	var offset := BrushSize.center_offset(use_size)
	var sample_count := segments_for(use_size)
	var depth := depth_for(use_size)
	var vertices := PackedVector3Array()
	var queries := 0
	var breaks := 0
	var completed := 0
	var cancelled := false
	var masks := TerrainPreview.masks_for(context)
	var no_changes := {}
	for mask: int in masks:
		var axis_frame := surface_frame
		var center := center_point
		if context != null and mask != 0:
			axis_frame = surface_frame.reflected(context, mask)
			center = TerrainFrame.mirror_point(center_point, context, mask)
		var normal := axis_frame.normal.normalized()
		if normal == Vector3.ZERO:
			continue
		var first := axis_frame.tangent_u.normalized()
		var second := axis_frame.tangent_v.normalized()
		if first == Vector3.ZERO or second == Vector3.ZERO:
			continue
		var local_center := center + offset * (first + second)
		var cells: Array[Vector3i] = []
		var faces: Array = []
		cells.resize(sample_count)
		faces.resize(sample_count)
		for index in sample_count:
			var angle := TAU * float(index) / float(sample_count)
			var rim := _rim_point(local_center, radius, angle, first, second)
			var cell := _probe(frame, rim, normal, depth, query, tester, no_changes)
			queries += 1
			completed += 1
			cells[index] = cell
			faces[index] = _front_face(cell, rim, normal)
			if job != null and completed % CHECKPOINT == 0 and not job.checkpoint(completed):
				cancelled = true
				break
		if cancelled:
			break
		var traced := _trace(frame, vertices, cells, faces, sample_count, local_center, radius, first, second, normal, depth, query, tester, no_changes, lift)
		vertices = traced["vertices"]
		breaks += int(traced["breaks"])
	result["samples"] = sample_count
	result["masks"] = masks.size()
	result["queries"] = queries
	result["breaks"] = breaks
	result["segments"] = vertices.size() / 2
	result["vertices"] = PackedVector3Array() if cancelled else vertices
	return result


static func surface_ring(frame: VoxelFrame, surface_frame: TerrainFrame, center_point: Vector3, size: int, context: VoxelFrame.EditContext, tester := Callable(), job: VoxelFrame.EditJob = null, query: TerrainQueryContext = null, lift := LIFT) -> PackedVector3Array:
	var data := surface_ring_data(frame, surface_frame, center_point, size, context, tester, job, query, lift)
	return data["vertices"]


static func plane_ring(surface_frame: TerrainFrame, center_point: Vector3, size: int, context: VoxelFrame.EditContext, lift := LIFT) -> PackedVector3Array:
	var vertices := PackedVector3Array()
	if surface_frame == null:
		return vertices
	var use_size := BrushSize.clamp_size(size)
	var radius := BrushSize.radius(use_size)
	var offset := BrushSize.center_offset(use_size)
	var sample_count := segments_for(use_size)
	for mask: int in TerrainPreview.masks_for(context):
		var axis_frame := surface_frame
		var center := center_point
		if context != null and mask != 0:
			axis_frame = surface_frame.reflected(context, mask)
			center = TerrainFrame.mirror_point(center_point, context, mask)
		var normal := axis_frame.normal.normalized()
		if normal == Vector3.ZERO:
			continue
		var first := axis_frame.tangent_u.normalized()
		var second := axis_frame.tangent_v.normalized()
		if first == Vector3.ZERO or second == Vector3.ZERO:
			continue
		var local_center := center + offset * (first + second) + normal * lift
		for index in sample_count:
			var angle := TAU * float(index) / float(sample_count)
			var next_angle := TAU * float(index + 1) / float(sample_count)
			vertices.append(_rim_point(local_center, radius, angle, first, second))
			vertices.append(_rim_point(local_center, radius, next_angle, first, second))
	return vertices


static func _trace(frame: VoxelFrame, vertices: PackedVector3Array, cells: Array, faces: Array, sample_count: int, local_center: Vector3, radius: float, first: Vector3, second: Vector3, normal: Vector3, depth: int, query: TerrainQueryContext, tester: Callable, no_changes: Dictionary, lift: float) -> Dictionary:
	var run := PackedVector3Array()
	var breaks := 0
	var previous_cell := VoxelPicking.NONE
	var previous_face := {}
	var previous_angle := 0.0
	for step_index in sample_count + 1:
		var index := step_index % sample_count
		var angle := TAU * float(step_index) / float(sample_count)
		var cell := cells[index] as Vector3i
		var face: Dictionary = faces[index]
		if cell == VoxelPicking.NONE or face.is_empty():
			if run.size() > 1:
				_emit_run(vertices, run)
				breaks += 1
			run = PackedVector3Array()
			previous_face = {}
			previous_angle = angle
			continue
		if previous_face.is_empty():
			run.append((face["point"] as Vector3) + normal * lift)
			previous_cell = cell
			previous_face = face
			previous_angle = angle
			continue
		if cell == previous_cell or _same_plane(previous_face, face):
			run.append((face["point"] as Vector3) + normal * lift)
			previous_cell = cell
			previous_face = face
			previous_angle = angle
			continue
		var step := _resolve_step(frame, local_center, radius, first, second, previous_angle, angle, previous_face, face, normal, depth, query, tester, no_changes)
		if step.is_empty():
			if run.size() > 1:
				_emit_run(vertices, run)
				breaks += 1
			run = PackedVector3Array()
			previous_face = {}
			previous_angle = angle
			continue
		run.append((step["low"] as Vector3) + normal * lift)
		run.append((step["high"] as Vector3) + normal * lift)
		run.append((face["point"] as Vector3) + normal * lift)
		previous_cell = cell
		previous_face = face
		previous_angle = angle
	if run.size() > 1:
		_emit_run(vertices, run)
	return {"vertices": vertices, "breaks": breaks}


static func _resolve_step(frame: VoxelFrame, local_center: Vector3, radius: float, first: Vector3, second: Vector3, low_angle: float, high_angle: float, low_face: Dictionary, high_face: Dictionary, normal: Vector3, depth: int, query: TerrainQueryContext, tester: Callable, no_changes: Dictionary) -> Dictionary:
	var lo_angle := low_angle
	var hi_angle := high_angle
	var lo_face := low_face
	var hi_face := high_face
	for _split in SPLIT_DEPTH:
		if absf(hi_angle - lo_angle) <= SPLIT_ANGLE:
			break
		var mid_angle := (lo_angle + hi_angle) * 0.5
		var mid_rim := _rim_point(local_center, radius, mid_angle, first, second)
		var mid_cell := _probe(frame, mid_rim, normal, depth, query, tester, no_changes)
		if mid_cell == VoxelPicking.NONE:
			return {}
		var mid_face := _front_face(mid_cell, mid_rim, normal)
		if mid_face.is_empty():
			return {}
		if _same_plane(lo_face, mid_face):
			lo_angle = mid_angle
			lo_face = mid_face
		else:
			hi_angle = mid_angle
			hi_face = mid_face
	if _same_plane(lo_face, hi_face):
		return {}
	return {"low": lo_face["point"], "high": hi_face["point"]}


static func _emit_run(vertices: PackedVector3Array, run: PackedVector3Array) -> void:
	for index in range(run.size() - 1):
		vertices.append(run[index])
		vertices.append(run[index + 1])


static func _same_plane(one: Dictionary, other: Dictionary) -> bool:
	return (
		int(one["axis"]) == int(other["axis"])
		and int(one["side"]) == int(other["side"])
		and absf(float(one["plane"]) - float(other["plane"])) <= PLANE_EPSILON
	)


static func _probe(frame: VoxelFrame, point: Vector3, normal: Vector3, depth: int, query: TerrainQueryContext, tester: Callable, no_changes: Dictionary) -> Vector3i:
	var cell := TerrainGeometry.surface_along(frame, point, normal, depth, no_changes, query)
	if cell == VoxelPicking.NONE:
		return cell
	if tester.is_valid() and not bool(tester.call(cell, normal, point)):
		return VoxelPicking.NONE
	return cell


static func _front_face(cell: Vector3i, point: Vector3, normal: Vector3) -> Dictionary:
	if cell == VoxelPicking.NONE:
		return {}
	var direction := normal.normalized()
	if direction == Vector3.ZERO:
		return {}
	var box := AABB(Vector3(cell) - Vector3(0.5, 0.5, 0.5), Vector3.ONE)
	var reach := absf((box.get_center() - point).dot(direction)) + box.size.length() + 1.0
	var hit: Variant = box.intersects_ray(point + direction * reach, -direction)
	if hit == null:
		hit = _slab_exit(box, point, direction)
	if hit == null:
		var snapped := Vector3(cell)
		var dominant := TerrainGeometry.dominant_axis(direction)
		snapped[dominant] += 0.5 if direction[dominant] >= 0.0 else -0.5
		hit = snapped
	var axis := _face_axis(hit, box, direction)
	var center := box.get_center()
	var side := 1 if hit[axis] >= center[axis] else -1
	var plane := box.position[axis] + (box.size[axis] if side > 0 else 0.0)
	return {"point": hit, "axis": axis, "side": side, "plane": plane}


static func _face_axis(point: Vector3, box: AABB, direction: Vector3) -> int:
	var axis := TerrainGeometry.dominant_axis(direction)
	var closest := INF
	for index in 3:
		if absf(direction[index]) <= SLAB_EPSILON:
			continue
		var low := box.position[index]
		var high := low + box.size[index]
		var gap := minf(absf(point[index] - low), absf(point[index] - high))
		if gap < closest:
			closest = gap
			axis = index
	return axis


static func _slab_exit(box: AABB, point: Vector3, direction: Vector3) -> Variant:
	var enter := -INF
	var exit := INF
	for axis in 3:
		var low := box.position[axis]
		var high := low + box.size[axis]
		if absf(direction[axis]) <= SLAB_EPSILON:
			if point[axis] < low - SLAB_EPSILON or point[axis] > high + SLAB_EPSILON:
				return null
			continue
		var first := (low - point[axis]) / direction[axis]
		var second := (high - point[axis]) / direction[axis]
		enter = maxf(enter, minf(first, second))
		exit = minf(exit, maxf(first, second))
	if enter > exit + SLAB_EPSILON or not is_finite(exit):
		return null
	return point + direction * exit


static func _rim_point(center: Vector3, radius: float, angle: float, first: Vector3, second: Vector3) -> Vector3:
	return center + radius * (cos(angle) * first + sin(angle) * second)

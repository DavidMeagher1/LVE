extends "./DeformTool.gd"


const VoxelFalloff := preload("res://Globals/State/Tools/VoxelFalloff.gd")
const DeformLimb := preload("./DeformLimb.gd")

const GRAB_MAX_DISTANCE := 48.0


class GrabJob extends DeformJob:
	var moves: Array = []
	var sources := {}
	var work := 0

	func estimated_work() -> int:
		return maxi(1, work)

	func compute_changes() -> Dictionary:
		stage("Grabbing voxels", moves.size())
		destination_selection = {}
		removed_cells = {}
		var planned := []
		for move in moves:
			var source: Vector3i = move["source"]
			var destination: Vector3i = source + move["delta"]
			if destination == source or not allows(destination) or _blocked(destination):
				continue
			planned.append(move)
		planned.sort_custom(func(a, b):
			var weight_a := float(a["weight"])
			var weight_b := float(b["weight"])
			if weight_a != weight_b:
				return weight_a > weight_b
			var source_a: Vector3i = a["source"]
			var source_b: Vector3i = b["source"]
			if source_a.y != source_b.y:
				return source_a.y < source_b.y
			if source_a.z != source_b.z:
				return source_a.z < source_b.z
			return source_a.x < source_b.x
		)
		var changes := {}
		for move in planned:
			changes[move["source"]] = VoxelFrame.material(Color.TRANSPARENT)
			removed_cells[move["source"]] = true
		var writes := {}
		var completed := 0
		for move in planned:
			var source: Vector3i = move["source"]
			var material: PackedFloat32Array = move["material"]
			var destination: Vector3i = source + move["delta"]
			for cell in StrokeLine.cells(source, destination):
				if cell == source or _blocked(cell) or not allows(cell) or writes.has(cell):
					continue
				writes[cell] = material
			completed += 1
			if completed % 512 == 0 and not checkpoint(completed):
				return {}
		for cell in writes:
			changes[cell] = writes[cell]
		for cell in writes:
			destination_selection[cell] = true
		for move in moves:
			var source: Vector3i = move["source"]
			if not removed_cells.has(source):
				destination_selection[source] = true
		return changes

	func _blocked(cell: Vector3i) -> bool:
		return edited_frame.has(cell) and not sources.has(cell)


var _sources: Array = []
var _source_cells := {}
var _ball_cache := {}


func _action_name() -> String:
	return "Grab"


func _operation_label() -> String:
	return "Grabbing voxels"


func _capture_gesture(pick: PickResult) -> bool:
	_sources = []
	_source_cells = {}
	for mask in DeformLimb.masks_for(_stroke_context):
		var center := _stroke_context.reflect(_anchor, mask)
		for offset: Vector3i in _ball_offsets(_stroke_size):
			var cell := center + offset
			if _source_cells.has(cell) or not _source_frame.has(cell):
				continue
			if not _allows(cell):
				continue
			var weight := VoxelFalloff.weight_at(Vector3(offset).length(), float(_stroke_size), _stroke_falloff)
			if weight <= 0.0:
				continue
			_source_cells[cell] = true
			_sources.append({
				"cell": cell,
				"material": _source_frame.get_material(cell),
				"mask": mask,
				"weight": weight,
			})
	return not _sources.is_empty()


func _make_job(target: Vector3i) -> DeformJob:
	if _sources.is_empty():
		return null
	var delta := _clamp_delta(target - _anchor)
	if delta == Vector3i.ZERO:
		return null
	var moves := []
	var work := 0
	for source in _sources:
		var mask: int = source["mask"]
		var anchor_mirror := _stroke_context.reflect(_anchor, mask)
		var moved_mirror := _stroke_context.reflect(_anchor + delta, mask)
		var mirrored: Vector3i = moved_mirror - anchor_mirror
		var weight: float = source["weight"]
		var scaled := Vector3i(
			roundi(float(mirrored.x) * weight),
			roundi(float(mirrored.y) * weight),
			roundi(float(mirrored.z) * weight)
		)
		if scaled == Vector3i.ZERO:
			continue
		moves.append({
			"source": source["cell"],
			"material": source["material"],
			"delta": scaled,
			"weight": weight,
		})
		work += absi(scaled.x) + absi(scaled.y) + absi(scaled.z) + 1
	if moves.is_empty():
		return null
	var job := GrabJob.new()
	job.moves = moves
	job.sources = _source_cells
	job.work = work
	return job


func _clamp_delta(delta: Vector3) -> Vector3i:
	if delta.length() <= GRAB_MAX_DISTANCE:
		return Vector3i(delta)
	var clamped := delta.normalized() * GRAB_MAX_DISTANCE
	return Vector3i(clamped.round())


func _allows(cell: Vector3i) -> bool:
	return _stroke_context == null or _stroke_context.allows(cell)


func _ball_offsets(size: int) -> Array[Vector3i]:
	if _ball_cache.has(size):
		return _ball_cache[size]
	var offsets: Array[Vector3i] = []
	var ball_reach := float(size) * 0.5
	var reach_squared := ball_reach * ball_reach
	var reach := ceili(ball_reach)
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			for z in range(-reach, reach + 1):
				if x * x + y * y + z * z <= reach_squared:
					offsets.append(Vector3i(x, y, z))
	_ball_cache[size] = offsets
	return offsets

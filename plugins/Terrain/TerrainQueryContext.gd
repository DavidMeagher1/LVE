class_name TerrainQueryContext
extends RefCounted


const CHECKPOINT := 4096
const BOUNDS_MARGIN := 1.0

var _frame: VoxelFrame
var _columns := {}
var _cancelled := false
var _column_index := true
var _local_bounds := AABB()
var _has_local_bounds := false
var _job: WeakRef
var builds := 0
var build_attempts := 0
var grid_reads := 0
var column_queries := 0
var bounds_queries := 0
var bounds_rejects := 0


func _init(frame: VoxelFrame, job: VoxelFrame.EditJob = null, column_index := true) -> void:
	_frame = frame
	_job = weakref(job) if job != null else null
	_column_index = column_index


func column_empty(axis: int, cell: Vector3i) -> bool:
	if not _column_index or _cancelled:
		return false
	if not _columns.has(axis):
		var built := _build(axis)
		if _cancelled:
			return false
		_columns[axis] = built
		builds += 1
	column_queries += 1
	var columns: Dictionary = _columns[axis]
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	return not columns.has(Vector2i(cell[u], cell[v]))


func misses_bounds(point: Vector3, normal: Vector3) -> bool:
	if _cancelled or normal == Vector3.ZERO:
		return false
	var bounds := _local_bounds_of()
	if not bounds.has_volume():
		return false
	bounds_queries += 1
	if bounds.has_point(point):
		return false
	if bounds.grow(BOUNDS_MARGIN).intersects_ray(point, normal) != null:
		return false
	if bounds.grow(BOUNDS_MARGIN).intersects_ray(point, -normal) != null:
		return false
	bounds_rejects += 1
	return true


func has_axis(axis: int) -> bool:
	return _columns.has(axis)


func _local_bounds_of() -> AABB:
	if not _has_local_bounds:
		_local_bounds = _frame.get_bounds() if _frame != null else AABB()
		_has_local_bounds = true
	return _local_bounds


func _build(axis: int) -> Dictionary:
	var columns := {}
	if _frame == null:
		return columns
	build_attempts += 1
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var size := VoxelFrame.CHUNK_SIZE
	var scanned := 0
	for location: Vector3i in _frame.chunks:
		var chunk: VoxelFrame.Chunk = _frame.chunks[location]
		var origin := location * size
		var rows := chunk.occupancy_rows()
		for row in rows.masks.size():
			var mask := rows.masks[row]
			if mask == 0:
				continue
			var local_y := row % size
			var local_z := row / size
			while mask != 0:
				var local_x := VoxelFrame.Chunk.first_column(mask)
				mask &= mask - 1
				scanned += 1
				if scanned % CHECKPOINT == 0 and not _checkpoint(scanned):
					_cancelled = true
					return {}
				grid_reads += 1
				var world := origin + Vector3i(local_x, local_y, local_z)
				columns[Vector2i(world[u], world[v])] = true
	return columns


func _checkpoint(completed: int) -> bool:
	if _job == null:
		return true
	var job: VoxelFrame.EditJob = _job.get_ref() as VoxelFrame.EditJob
	if job == null:
		return true
	return job.checkpoint(completed)

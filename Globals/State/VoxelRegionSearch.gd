class_name VoxelRegionSearch
extends RefCounted


const CHUNK_SIZE := VoxelFrame.CHUNK_SIZE
const CHUNK_CELLS := CHUNK_SIZE * CHUNK_SIZE * CHUNK_SIZE
const MATERIAL_STRIDE := VoxelFrame.MATERIAL_STRIDE
const DIRECTIONS := VoxelFrame.DIRECTIONS
const STREAM_BATCH := 512


class BatchQueue extends RefCounted:
	const LIMIT := 4

	var _batches: Array = []
	var _mutex := Mutex.new()
	var _free := Semaphore.new()
	var _cancelled := false

	func push(batch: Dictionary) -> bool:
		while true:
			_mutex.lock()
			if _cancelled:
				_mutex.unlock()
				return false
			if _batches.size() < LIMIT:
				_batches.append(batch)
				_mutex.unlock()
				return true
			_mutex.unlock()
			_free.wait()
		return false

	func take() -> Dictionary:
		_mutex.lock()
		var batch := {}
		if not _batches.is_empty():
			batch = _batches.pop_front()
		_mutex.unlock()
		if not batch.is_empty():
			_free.post()
		return batch

	func cancel() -> void:
		_mutex.lock()
		_cancelled = true
		_mutex.unlock()
		_free.post()

	func is_cancelled() -> bool:
		_mutex.lock()
		var value := _cancelled
		_mutex.unlock()
		return value

	func is_empty() -> bool:
		_mutex.lock()
		var value := _batches.is_empty()
		_mutex.unlock()
		return value

	func depth() -> int:
		_mutex.lock()
		var value := _batches.size()
		_mutex.unlock()
		return value


class BatchCursor extends RefCounted:
	var queue: BatchQueue
	var keys: Array = []
	var cursor := 0
	var _applying := false

	func _init(batch_queue: BatchQueue = null) -> void:
		queue = batch_queue

	func is_done() -> bool:
		return cursor >= keys.size() and queue.is_empty()

	func next_end(limit: int) -> int:
		if cursor >= keys.size():
			var batch := queue.take()
			if batch.is_empty():
				return -1
			keys = batch.keys()
			cursor = 0
		return mini(cursor + limit, keys.size())

	func apply_slice(limit: int, apply: Callable) -> bool:
		if queue == null or _applying:
			return false
		var end := next_end(limit)
		if end <= cursor:
			return false
		var start := cursor
		_applying = true
		var accepted: bool = apply.call(keys, start, end)
		_applying = false
		if not accepted:
			return false
		cursor = end
		return true


static func _in_slice(cell: Vector3i, slice_axis: int, slice_index: int, slice_count: int) -> bool:
	if slice_axis < 0:
		return true
	var layer := cell[slice_axis]
	return layer >= slice_index and layer < slice_index + slice_count


static func find(result: Dictionary, frame: VoxelFrame, seed_cell: Vector3i, target_material: PackedFloat32Array, connected: bool, value: Variant = true, selection_mask: Dictionary = {}, job: VoxelFrame.EditJob = null, stream: Callable = Callable(), slice_axis := -1, slice_index := 0, slice_count := 1) -> bool:
	if frame == null:
		return true
	if job and not job.checkpoint(0):
		return false
	if connected:
		if slice_axis >= 0 and not _in_slice(seed_cell, slice_axis, slice_index, slice_count):
			return true
		return _find_connected(result, frame, seed_cell, target_material, value, selection_mask, job, stream, slice_axis, slice_index, slice_count)
	return _find_occupied(result, frame, target_material, value, selection_mask, job, stream, slice_axis, slice_index, slice_count)


static func _find_connected(result: Dictionary, frame: VoxelFrame, seed_cell: Vector3i, target_material: PackedFloat32Array, value: Variant, selection_mask: Dictionary, job: VoxelFrame.EditJob, stream: Callable, slice_axis := -1, slice_index := 0, slice_count := 1) -> bool:
	var seed_chunk: VoxelFrame.Chunk = frame.chunks.get(VoxelFrame.chunk_position(seed_cell))
	if not _chunk_matches(seed_chunk, seed_cell, target_material):
		return true
	var streaming := stream.is_valid()
	var batch: Array[Vector3i] = []
	var pending: Array[Vector3i] = [seed_cell]
	result[seed_cell] = value
	if streaming:
		batch.append(seed_cell)
	var mask_active := not selection_mask.is_empty()
	var examined := 0
	var current_location := Vector3i.MAX
	var current_chunk: VoxelFrame.Chunk = null
	var current_materials := PackedFloat32Array()
	var current_origin := Vector3i.ZERO
	var cached := false
	var matches := {}
	while not pending.is_empty():
		var cell_position: Vector3i = pending.pop_back()
		var location := VoxelFrame.chunk_position(cell_position)
		if location != current_location:
			current_location = location
			current_chunk = frame.chunks.get(location)
			if current_chunk:
				current_materials = current_chunk.materials
				current_origin = location * CHUNK_SIZE
			cached = _cache_pays(current_chunk)
			matches.clear()
		var origin_x := current_origin.x
		var origin_y := current_origin.y
		var origin_z := current_origin.z
		for direction in DIRECTIONS:
			var neighbor: Vector3i = cell_position + direction
			if result.has(neighbor):
				continue
			if slice_axis >= 0 and not _in_slice(neighbor, slice_axis, slice_index, slice_count):
				continue
			if mask_active and not selection_mask.has(neighbor):
				continue
			var local_x := neighbor.x - origin_x
			var local_y := neighbor.y - origin_y
			var local_z := neighbor.z - origin_z
			if local_x >= 0 and local_y >= 0 and local_z >= 0 and local_x < CHUNK_SIZE and local_y < CHUNK_SIZE and local_z < CHUNK_SIZE:
				var slot := local_x + CHUNK_SIZE * (local_y + CHUNK_SIZE * local_z)
				var id := current_chunk.cell_id_at_slot(slot)
				if cached:
					if not _id_matches_cached(current_materials, id, target_material, matches):
						continue
				elif not _id_matches(current_materials, id, target_material):
					continue
			else:
				var neighbor_location := VoxelFrame.chunk_position(neighbor)
				var neighbor_chunk: VoxelFrame.Chunk = frame.chunks.get(neighbor_location)
				if neighbor_chunk == null:
					continue
				var neighbor_origin := neighbor_location * CHUNK_SIZE
				var neighbor_local_x := neighbor.x - neighbor_origin.x
				var neighbor_local_y := neighbor.y - neighbor_origin.y
				var neighbor_local_z := neighbor.z - neighbor_origin.z
				var neighbor_slot := neighbor_local_x + CHUNK_SIZE * (neighbor_local_y + CHUNK_SIZE * neighbor_local_z)
				if not _id_matches(neighbor_chunk.materials, neighbor_chunk.cell_id_at_slot(neighbor_slot), target_material):
					continue
			result[neighbor] = value
			pending.append(neighbor)
			if streaming:
				batch.append(neighbor)
				if batch.size() >= STREAM_BATCH:
					stream.call(batch)
					batch = []
		examined += 1
		if job and examined % 4096 == 0 and not job.checkpoint(result.size()):
			return false
	if streaming and not batch.is_empty():
		stream.call(batch)
	return true


static func _find_occupied(result: Dictionary, frame: VoxelFrame, target_material: PackedFloat32Array, value: Variant, selection_mask: Dictionary, job: VoxelFrame.EditJob, stream: Callable, slice_axis := -1, slice_index := 0, slice_count := 1) -> bool:
	var streaming := stream.is_valid()
	var batch: Array[Vector3i] = []
	var mask_active := not selection_mask.is_empty()
	var examined := 0
	for chunk: VoxelFrame.Chunk in frame.chunks.values():
		if job and not job.checkpoint(examined):
			return false
		var origin := chunk.origin()
		var materials := chunk.materials
		var rows := chunk.occupancy_rows()
		var cached := _cache_pays(chunk)
		var matches := {}
		for row in rows.masks.size():
			var mask := rows.masks[row]
			if mask == 0:
				continue
			var local_y := row % CHUNK_SIZE
			var local_z := row / CHUNK_SIZE
			while mask != 0:
				var local_x := VoxelFrame.Chunk.first_column(mask)
				var id := chunk.cell_id_at_slot(row * CHUNK_SIZE + local_x)
				var cell_position := origin + Vector3i(local_x, local_y, local_z)
				var hit := _id_matches_cached(materials, id, target_material, matches) if cached else _id_matches(materials, id, target_material)
				if hit and (slice_axis < 0 or _in_slice(cell_position, slice_axis, slice_index, slice_count)) and (not mask_active or selection_mask.has(cell_position)):
					result[cell_position] = value
					if streaming:
						batch.append(cell_position)
						if batch.size() >= STREAM_BATCH:
							stream.call(batch)
							batch = []
				examined += 1
				if job and examined % 4096 == 0 and not job.checkpoint(examined):
					return false
				mask &= mask - 1
	if streaming and not batch.is_empty():
		stream.call(batch)
	return true


static func _cache_pays(chunk: VoxelFrame.Chunk) -> bool:
	if chunk == null:
		return false
	return chunk.occupied_count > 2 * (chunk.materials.size() / MATERIAL_STRIDE)


static func _chunk_matches(chunk: VoxelFrame.Chunk, cell_position: Vector3i, target_material: PackedFloat32Array) -> bool:
	if chunk == null:
		return false
	return _id_matches(chunk.materials, chunk.material_id(cell_position), target_material)


static func _id_matches_cached(materials: PackedFloat32Array, id: int, target_material: PackedFloat32Array, cache: Dictionary) -> bool:
	if id == 0:
		return false
	if cache.has(id):
		return cache[id]
	var equal := _id_matches(materials, id, target_material)
	cache[id] = equal
	return equal


static func _id_matches(materials: PackedFloat32Array, id: int, target_material: PackedFloat32Array) -> bool:
	if id == 0:
		return false
	var base := (id - 1) * MATERIAL_STRIDE
	for offset in MATERIAL_STRIDE:
		if materials[base + offset] != target_material[offset]:
			return false
	return true

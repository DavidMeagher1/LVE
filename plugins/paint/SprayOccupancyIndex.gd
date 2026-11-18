class_name SprayOccupancyIndex
extends RefCounted


const VoxelBrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")

const POPCOUNT4 := [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]
const SELECTION_BUCKET_LIMIT := 4096


static func row_index(local_y: int, local_z: int) -> int:
	return local_y + VoxelFrame.CHUNK_SIZE * local_z


static func popcount16(mask: int) -> int:
	return POPCOUNT4[mask & 15] + POPCOUNT4[(mask >> 4) & 15] + POPCOUNT4[(mask >> 8) & 15] + POPCOUNT4[(mask >> 12) & 15]


static func span_mask(low: int, high: int) -> int:
	if high < low:
		return 0
	return ((1 << (high - low + 1)) - 1) << low


static func count_in_span(mask: int, low: int, high: int) -> int:
	return popcount16(mask & span_mask(low, high))


static func nth_in_span(mask: int, low: int, high: int, rank: int) -> int:
	var bits := mask & span_mask(low, high)
	for x in range(low, high + 1):
		if bits & (1 << x) == 0:
			continue
		if rank == 0:
			return x
		rank -= 1
	return -1


static func sphere_x_span_relative(size: int, dy: int, dz: int) -> Vector2i:
	var even := 1 if size % 2 == 0 else 0
	var u := 2 * dy + even
	var v := 2 * dz + even
	var rest := size * size - u * u - v * v
	if rest < 0:
		return Vector2i(1, 0)
	var limit := int(sqrt(float(rest)))
	while (limit + 1) * (limit + 1) <= rest:
		limit += 1
	while limit * limit > rest:
		limit -= 1
	var low := 0
	var high := 0
	if even == 0:
		low = -2 * (limit / 2)
		high = 2 * (limit / 2)
	else:
		if limit < 1:
			return Vector2i(1, 0)
		var odd := 2 * ((limit - 1) / 2) + 1
		low = -odd
		high = odd
	return Vector2i((low - even) / 2, (high - even) / 2)


static func sphere_x_span(center: Vector3i, size: int, y: int, z: int) -> Vector2i:
	var relative := sphere_x_span_relative(size, y - center.y, z - center.z)
	if relative.x > relative.y:
		return relative
	return Vector2i(center.x + relative.x, center.x + relative.y)


static func cell_bounds(center: Vector3i, size: int) -> Array[Vector3i]:
	var first := VoxelBrushSize.first_offset(size)
	var last := VoxelBrushSize.last_offset(size)
	return [center + Vector3i.ONE * first, center + Vector3i.ONE * last]


static func chunk_intersects(center: Vector3i, size: int, chunk: VoxelFrame.Chunk) -> bool:
	var origin := chunk.origin()
	var high := origin + Vector3i.ONE * (VoxelFrame.CHUNK_SIZE - 1)
	var even := 1 if size % 2 == 0 else 0
	var u := 2 * (clampi(center.x, origin.x, high.x) - center.x) + even
	var v := 2 * (clampi(center.y, origin.y, high.y) - center.y) + even
	var w := 2 * (clampi(center.z, origin.z, high.z) - center.z) + even
	return u * u + v * v + w * w <= size * size


static func capture_chunks(center: Vector3i, search_size: int, spot_size: int, axes: int, origin_twice: Vector3i) -> Array[Vector3i]:
	var first := VoxelBrushSize.first_offset(search_size) + VoxelBrushSize.first_offset(spot_size)
	var last := VoxelBrushSize.last_offset(search_size) + VoxelBrushSize.last_offset(spot_size)
	var low := center + Vector3i.ONE * first
	var high := center + Vector3i.ONE * last
	var locations := {}
	for mask in 8:
		if (mask & ~axes) != 0:
			continue
		var reflected_low := low
		var reflected_high := high
		for axis in 3:
			if mask & (1 << axis):
				reflected_low[axis] = origin_twice[axis] - high[axis]
				reflected_high[axis] = origin_twice[axis] - low[axis]
		var min_chunk := VoxelFrame.chunk_position(reflected_low)
		var max_chunk := VoxelFrame.chunk_position(reflected_high)
		for x in range(min_chunk.x, max_chunk.x + 1):
			for y in range(min_chunk.y, max_chunk.y + 1):
				for z in range(min_chunk.z, max_chunk.z + 1):
					locations[Vector3i(x, y, z)] = true
	var result: Array[Vector3i] = []
	for location: Vector3i in locations:
		result.append(location)
		for direction in VoxelFrame.DIRECTIONS:
			result.append(location + direction)
	return result


class SphereSpans extends RefCounted:
	var sphere_size := 1
	var first := 0
	var spans: Array[Vector2i] = []

	func span(dy: int, dz: int) -> Vector2i:
		if dy < first or dz < first or dy >= first + sphere_size or dz >= first + sphere_size:
			return Vector2i(1, 0)
		return spans[(dy - first) * sphere_size + (dz - first)]

	static func build(value_size: int) -> SphereSpans:
		var result := SphereSpans.new()
		result.sphere_size = value_size
		result.first = VoxelBrushSize.first_offset(value_size)
		result.spans.resize(value_size * value_size)
		for dy in range(result.first, result.first + value_size):
			for dz in range(result.first, result.first + value_size):
				result.spans[(dy - result.first) * value_size + (dz - result.first)] = SprayOccupancyIndex.sphere_x_span_relative(value_size, dy, dz)
		return result


class SelectionIndex extends RefCounted:
	var masks_by_chunk := {}
	var selected_count := 0

	func masks_for(location: Vector3i) -> Dictionary:
		var bucket: Variant = masks_by_chunk.get(location)
		return bucket if bucket != null else {}

	static func build(selection: Dictionary, job: VoxelFrame.EditJob = null) -> SelectionIndex:
		var result := SelectionIndex.new()
		var completed := 0
		for cell: Vector3i in selection:
			completed += 1
			if job and completed % 4096 == 0 and not job.checkpoint(completed):
				return null
			var location := VoxelFrame.chunk_position(cell)
			var local := cell - location * VoxelFrame.CHUNK_SIZE
			var row := local.y + VoxelFrame.CHUNK_SIZE * local.z
			var bucket: Variant = result.masks_by_chunk.get(location)
			if bucket == null:
				bucket = {}
				result.masks_by_chunk[location] = bucket
			bucket[row] = bucket.get(row, 0) | (1 << local.x)
			result.selected_count += 1
		return result


class SurfaceIndex extends RefCounted:
	var frame: VoxelFrame
	var index_builds := 0
	var index_grid_reads := 0
	var index_build_slots := 0
	var _masks := {}

	func masks_for(location: Vector3i) -> PackedInt32Array:
		var cached: Variant = _masks.get(location)
		if cached != null:
			return cached
		var built := _build(location)
		_masks[location] = built
		return built

	func exposed(cell: Vector3i) -> bool:
		var location := VoxelFrame.chunk_position(cell)
		var masks := masks_for(location)
		var local := cell - location * VoxelFrame.CHUNK_SIZE
		var row := local.y + VoxelFrame.CHUNK_SIZE * local.z
		return masks[row] & (1 << local.x) != 0

	func _build(location: Vector3i) -> PackedInt32Array:
		var masks := PackedInt32Array()
		masks.resize(VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE)
		var own := _row_masks(location)
		if own.is_empty():
			return masks
		var east := _row_masks(location + Vector3i.RIGHT)
		var west := _row_masks(location + Vector3i.LEFT)
		var north := _row_masks(location + Vector3i.UP)
		var south := _row_masks(location + Vector3i.DOWN)
		var above := _row_masks(location + Vector3i.BACK)
		var below := _row_masks(location + Vector3i.FORWARD)
		for row in masks.size():
			if own[row] == 0:
				continue
			masks[row] = surface_row(own, east, west, north, south, above, below, row)
		return masks

	func _row_masks(location: Vector3i) -> PackedInt32Array:
		var chunk: VoxelFrame.Chunk = frame.chunks.get(location)
		if chunk == null or chunk.occupied_count == 0:
			return PackedInt32Array()
		var was_current := chunk.occupancy_index_current()
		var rows := chunk.occupancy_rows()
		if not was_current:
			index_builds += 1
			index_grid_reads += rows.grid_reads
			index_build_slots += rows.build_slots
		return rows.masks

	static func surface_row(own: PackedInt32Array, east: PackedInt32Array, west: PackedInt32Array, north: PackedInt32Array, south: PackedInt32Array, above: PackedInt32Array, below: PackedInt32Array, row: int) -> int:
		var occupied := own[row]
		if occupied == 0:
			return 0
		var local_y := row & (VoxelFrame.CHUNK_SIZE - 1)
		var local_z := row >> VoxelFrame.CHUNK_SHIFT
		var neighbour_east := occupied >> 1
		if not east.is_empty():
			neighbour_east |= (east[row] & 1) << (VoxelFrame.CHUNK_SIZE - 1)
		var neighbour_west := (occupied << 1) & 0xFFFF
		if not west.is_empty():
			neighbour_west |= (west[row] >> (VoxelFrame.CHUNK_SIZE - 1)) & 1
		var neighbour_north := 0
		if local_y < VoxelFrame.CHUNK_SIZE - 1:
			neighbour_north = own[row + 1]
		elif not north.is_empty():
			neighbour_north = north[row - (VoxelFrame.CHUNK_SIZE - 1)]
		var neighbour_south := 0
		if local_y > 0:
			neighbour_south = own[row - 1]
		elif not south.is_empty():
			neighbour_south = south[row + (VoxelFrame.CHUNK_SIZE - 1)]
		var neighbour_above := 0
		if local_z < VoxelFrame.CHUNK_SIZE - 1:
			neighbour_above = own[row + VoxelFrame.CHUNK_SIZE]
		elif not above.is_empty():
			neighbour_above = above[row - VoxelFrame.CHUNK_SIZE * (VoxelFrame.CHUNK_SIZE - 1)]
		var neighbour_below := 0
		if local_z > 0:
			neighbour_below = own[row - VoxelFrame.CHUNK_SIZE]
		elif not below.is_empty():
			neighbour_below = below[row + VoxelFrame.CHUNK_SIZE * (VoxelFrame.CHUNK_SIZE - 1)]
		return occupied & (~neighbour_east | ~neighbour_west | ~neighbour_north | ~neighbour_south | ~neighbour_above | ~neighbour_below)


class Candidates extends RefCounted:
	var total := 0
	var rank_calls := 0
	var rank_rows := 0
	var chunks_scanned := 0
	var rows_scanned := 0
	var index_builds := 0
	var index_grid_reads := 0
	var index_build_slots := 0
	var selection_checked := 0
	var selection_builds := 0
	var selection_work := 0
	var selection_index: RefCounted = null
	var surface: RefCounted = null
	var _center := Vector3i.ZERO
	var _size := 1
	var _spans: RefCounted = null
	var _selected: Array[Vector3i] = []
	var _records: Array = []
	var _use_selection := false

	func candidate(index: int) -> Vector3i:
		rank_calls += 1
		if _use_selection:
			return _selected[index]
		var low := 0
		var high := _records.size() - 1
		while low <= high:
			var mid := (low + high) / 2
			var record: Array = _records[mid]
			var start: int = record[1]
			var count: int = record[2]
			if index < start:
				high = mid - 1
			elif index >= start + count:
				low = mid + 1
			else:
				var chunk: VoxelFrame.Chunk = record[0]
				var rows := [0]
				var masks := {}
				if selection_index != null:
					masks = selection_index.masks_for(chunk.location)
				var surface_masks := PackedInt32Array()
				if surface != null:
					surface_masks = surface.masks_for(chunk.location)
				var cell := SprayOccupancyIndex._nth_chunk(chunk, _center, _size, _spans, index - start, rows, masks, surface_masks)
				rank_rows += rows[0]
				return cell
		return Vector3i.ZERO


static func build_candidates(center: Vector3i, frame: VoxelFrame, size: int, selection: Dictionary, job: VoxelFrame.EditJob = null, selection_index: RefCounted = null, spans: RefCounted = null, surface: RefCounted = null) -> Candidates:
	var result := Candidates.new()
	result._center = center
	result._size = size
	result._spans = spans if spans != null else SphereSpans.build(size)
	result.surface = surface
	if selection.is_empty():
		_build_indexed(center, frame, size, result, job)
		return result
	if selection_index != null:
		result.selection_index = selection_index
		_build_indexed(center, frame, size, result, job)
		return result
	if selection.size() <= SELECTION_BUCKET_LIMIT:
		_build_bucket(center, frame, size, selection, job, result)
		return result
	var built := SelectionIndex.build(selection, job)
	if built == null:
		result.total = 0
		return result
	result.selection_builds = 1
	result.selection_work = built.selected_count
	result.selection_index = built
	_build_indexed(center, frame, size, result, job)
	return result


static func _build_indexed(center: Vector3i, frame: VoxelFrame, size: int, result: Candidates, job: VoxelFrame.EditJob) -> void:
	var bounds := cell_bounds(center, size)
	var min_chunk := VoxelFrame.chunk_position(bounds[0])
	var max_chunk := VoxelFrame.chunk_position(bounds[1])
	var start := 0
	var completed := 0
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				result.chunks_scanned += 1
				var location := Vector3i(x, y, z)
				var chunk: VoxelFrame.Chunk = frame.chunks.get(location)
				var masks := {}
				if result.selection_index != null:
					masks = result.selection_index.masks_for(location)
					if masks.is_empty():
						completed += 1
						if job and completed % 8 == 0 and not job.checkpoint(completed):
							result.total = 0
							result._records.clear()
							return
						continue
				if chunk != null and chunk.occupied_count > 0 and chunk_intersects(center, size, chunk):
					var was_current := chunk.occupancy_index_current()
					var rows := [0]
					var surface_masks := PackedInt32Array()
					if result.surface != null:
						surface_masks = result.surface.masks_for(location)
					elif not was_current:
						result.index_builds += 1
					var count := _count_chunk(chunk, center, size, result._spans, rows, masks, surface_masks)
					result.rows_scanned += rows[0]
					if result.surface == null and not was_current:
						var built := chunk.occupancy_rows()
						result.index_grid_reads += built.grid_reads
						result.index_build_slots += built.build_slots
					if count > 0:
						result._records.append([chunk, start, count])
						start += count
				completed += 1
				if job and completed % 8 == 0 and not job.checkpoint(completed):
					result.total = 0
					result._records.clear()
					return
	result.total = start


static func _build_bucket(center: Vector3i, frame: VoxelFrame, size: int, selection: Dictionary, job: VoxelFrame.EditJob, result: Candidates) -> void:
	var buckets := {}
	var completed := 0
	for cell: Vector3i in selection:
		completed += 1
		result.selection_checked += 1
		if job and completed % 4096 == 0 and not job.checkpoint(completed):
			result.total = 0
			return
		if not frame.has(cell):
			continue
		if not VoxelBrushSize.contains_sphere(size, cell - center):
			continue
		if result.surface != null and not result.surface.exposed(cell):
			continue
		var location := VoxelFrame.chunk_position(cell)
		var bucket: Variant = buckets.get(location)
		if bucket == null:
			bucket = []
			buckets[location] = bucket
		var local := cell - location * VoxelFrame.CHUNK_SIZE
		bucket.append(local.x + VoxelFrame.CHUNK_SIZE * (local.y + VoxelFrame.CHUNK_SIZE * local.z))
	var bounds := cell_bounds(center, size)
	var min_chunk := VoxelFrame.chunk_position(bounds[0])
	var max_chunk := VoxelFrame.chunk_position(bounds[1])
	var cells: Array[Vector3i] = []
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var location := Vector3i(x, y, z)
				var bucket: Variant = buckets.get(location)
				if bucket == null:
					continue
				var slots: Array = bucket
				slots.sort()
				var origin := location * VoxelFrame.CHUNK_SIZE
				for slot: int in slots:
					var local := Vector3i(slot % VoxelFrame.CHUNK_SIZE, (slot / VoxelFrame.CHUNK_SIZE) % VoxelFrame.CHUNK_SIZE, slot / (VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE))
					cells.append(origin + local)
				completed += 1
				if job and not job.checkpoint(completed):
					result.total = 0
					return
	result._use_selection = true
	result._selected = cells
	result.total = cells.size()
	result.selection_work = result.selection_checked / 2


static func work_estimate(frame: VoxelFrame, center: Vector3i, search_size: int, spot_size: int, selection: Dictionary, speed: int, selection_index: RefCounted = null) -> int:
	var search_first := VoxelBrushSize.first_offset(search_size)
	var search_last := VoxelBrushSize.last_offset(search_size)
	var spot_first := VoxelBrushSize.first_offset(spot_size)
	var spot_last := VoxelBrushSize.last_offset(spot_size)
	var low := center + Vector3i.ONE * (search_first + spot_first)
	var high := center + Vector3i.ONE * (search_last + spot_last)
	var min_chunk := VoxelFrame.chunk_position(low)
	var max_chunk := VoxelFrame.chunk_position(high)
	var search_chunks := 0
	var combined_chunks := 0
	var occupied_hint := 0
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(x, y, z))
				if chunk == null or chunk.occupied_count == 0:
					continue
				combined_chunks += 1
				occupied_hint += chunk.occupied_count
				if chunk_intersects(center, search_size, chunk):
					search_chunks += 1
	var selection_work := 0
	if not selection.is_empty() and selection_index == null:
		if selection.size() <= SELECTION_BUCKET_LIMIT:
			selection_work = selection.size() / 2
		else:
			selection_work = selection.size()
	var spot_count := mini(speed, occupied_hint)
	var footprint_rows := 0
	if spot_size > 1 and spot_count > 0:
		if occupied_hint <= spot_count * 4:
			footprint_rows = spot_count * combined_chunks * VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE
		else:
			footprint_rows = spot_count * spot_size * spot_size
	var span_work := mini(search_size * search_size, combined_chunks * VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE)
	return search_chunks * VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE + span_work + selection_work + spot_count + footprint_rows


static func _count_chunk(chunk: VoxelFrame.Chunk, center: Vector3i, size: int, spans: RefCounted, rows: Array, selection_masks: Dictionary, surface_masks: PackedInt32Array) -> int:
	var origin := chunk.origin()
	var index := chunk.occupancy_rows()
	if index == null:
		return 0
	var total := 0
	for row in VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE:
		rows[0] += 1
		if index.counts[row] == 0:
			continue
		var local_y := row & (VoxelFrame.CHUNK_SIZE - 1)
		var local_z := row >> VoxelFrame.CHUNK_SHIFT
		var y := origin.y + local_y
		var z := origin.z + local_z
		var relative: Vector2i = spans.span(y - center.y, z - center.z)
		if relative.x > relative.y:
			continue
		var low := maxi(center.x + relative.x, origin.x) - origin.x
		var high := mini(center.x + relative.y, origin.x + VoxelFrame.CHUNK_SIZE - 1) - origin.x
		if low > high:
			continue
		var mask := index.masks[row]
		if not surface_masks.is_empty():
			mask &= surface_masks[row]
		if not selection_masks.is_empty():
			mask &= selection_masks.get(row, 0)
		if mask == 0:
			continue
		total += count_in_span(mask, low, high)
	return total


static func _nth_chunk(chunk: VoxelFrame.Chunk, center: Vector3i, size: int, spans: RefCounted, rank: int, rows: Array, selection_masks: Dictionary, surface_masks: PackedInt32Array) -> Vector3i:
	var origin := chunk.origin()
	var index := chunk.occupancy_rows()
	if index == null:
		return Vector3i.ZERO
	for row in VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE:
		rows[0] += 1
		if index.counts[row] == 0:
			continue
		var local_y := row & (VoxelFrame.CHUNK_SIZE - 1)
		var local_z := row >> VoxelFrame.CHUNK_SHIFT
		var y := origin.y + local_y
		var z := origin.z + local_z
		var relative: Vector2i = spans.span(y - center.y, z - center.z)
		if relative.x > relative.y:
			continue
		var low := maxi(center.x + relative.x, origin.x) - origin.x
		var high := mini(center.x + relative.y, origin.x + VoxelFrame.CHUNK_SIZE - 1) - origin.x
		if low > high:
			continue
		var mask := index.masks[row]
		if not surface_masks.is_empty():
			mask &= surface_masks[row]
		if not selection_masks.is_empty():
			mask &= selection_masks.get(row, 0)
		if mask == 0:
			continue
		var count := count_in_span(mask, low, high)
		if rank >= count:
			rank -= count
			continue
		var x := nth_in_span(mask, low, high, rank)
		if x >= 0:
			return Vector3i(origin.x + x, y, z)
	return Vector3i.ZERO

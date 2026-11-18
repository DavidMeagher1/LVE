extends RefCounted


const VoxelBrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")
const SprayIndex := preload("./SprayOccupancyIndex.gd")


class ShapeCache extends RefCounted:
	var _lock := Mutex.new()
	var _offsets := {}
	var _patterns := {}
	var _rows := {}
	var _spans := {}

	func offsets(size: int) -> Variant:
		_lock.lock()
		var value: Variant = _offsets.get(size)
		_lock.unlock()
		return value

	func put_offsets(size: int, value: Variant) -> void:
		_lock.lock()
		_offsets[size] = value
		_lock.unlock()

	func pattern(size: int) -> Variant:
		_lock.lock()
		var value: Variant = _patterns.get(size)
		_lock.unlock()
		return value

	func put_pattern(size: int, value: Variant) -> void:
		_lock.lock()
		_patterns[size] = value
		_lock.unlock()

	func rows(size: int) -> Variant:
		_lock.lock()
		var value: Variant = _rows.get(size)
		_lock.unlock()
		return value

	func put_rows(size: int, value: Variant) -> void:
		_lock.lock()
		_rows[size] = value
		_lock.unlock()

	func spans(size: int) -> Variant:
		_lock.lock()
		var value: Variant = _spans.get(size)
		_lock.unlock()
		return value

	func put_spans(size: int, value: Variant) -> void:
		_lock.lock()
		_spans[size] = value
		_lock.unlock()

	func clear() -> void:
		_lock.lock()
		_offsets.clear()
		_patterns.clear()
		_rows.clear()
		_spans.clear()
		_lock.unlock()

	func size() -> int:
		_lock.lock()
		var count := _offsets.size()
		_lock.unlock()
		return count


static func offsets(cache: ShapeCache, size: int) -> Array[Vector3i]:
	var cached: Variant = cache.offsets(size)
	if cached != null:
		var value: Array[Vector3i] = cached
		return value
	var built := VoxelBrushSize.sphere_offsets(size)
	cache.put_offsets(size, built)
	return built


static func pattern(cache: ShapeCache, size: int) -> Dictionary:
	var cached: Variant = cache.pattern(size)
	if cached != null:
		var value: Dictionary = cached
		return value
	var built := {}
	for offset in offsets(cache, size):
		built[offset] = true
	built.make_read_only()
	cache.put_pattern(size, built)
	return built


static func sphere_spans(cache: ShapeCache, size: int) -> RefCounted:
	var cached: Variant = cache.spans(size)
	if cached != null:
		return cached
	var built := SprayIndex.SphereSpans.build(size)
	cache.put_spans(size, built)
	return built


static func rows(cache: ShapeCache, size: int) -> Array:
	var cached: Variant = cache.rows(size)
	if cached != null:
		var value: Array = cached
		return value
	var built := build_rows(size)
	cache.put_rows(size, built)
	return built


static func build_rows(size: int) -> Array:
	var rows := []
	var first := VoxelBrushSize.first_offset(size)
	var last := VoxelBrushSize.last_offset(size)
	var c := VoxelBrushSize.center_offset(size)
	var limit := VoxelBrushSize.radius_squared(size)
	for dy in range(first, last + 1):
		var along_y := float(dy) - c
		var rest_y := limit - along_y * along_y
		if rest_y < 0.0:
			continue
		for dz in range(first, last + 1):
			var along_z := float(dz) - c
			var rest := rest_y - along_z * along_z
			if rest < 0.0:
				continue
			var span := sqrt(rest)
			var low := maxi(first, ceili(c - span))
			var high := mini(last, floori(c + span))
			if low > high:
				continue
			rows.append(Vector4i(dy, dz, low, high))
	return rows


static func occupied_estimate(frame: VoxelFrame, center: Vector3i, reach: int) -> int:
	var side := 2 * reach + 1
	var cube := side * side * side
	var min_chunk := VoxelFrame.chunk_position(center - Vector3i.ONE * reach)
	var max_chunk := VoxelFrame.chunk_position(center + Vector3i.ONE * reach)
	var total := 0
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(x, y, z))
				if chunk != null:
					total += chunk.occupied_count
					if total >= cube:
						return cube
	return total


static func capture_chunks(center: Vector3i, search_size: int, spot_size: int, axes: int, origin_twice: Vector3i) -> Array[Vector3i]:
	return SprayIndex.capture_chunks(center, search_size, spot_size, axes, origin_twice)


static func work_estimate(frame: VoxelFrame, center: Vector3i, search_size: int, spot_size: int, selection: Dictionary, speed: int, selection_index: RefCounted = null) -> int:
	return SprayIndex.work_estimate(frame, center, search_size, spot_size, selection, speed, selection_index)


static func in_slice(cells: Array[Vector3i], axis: int, index: int, count: int) -> Array[Vector3i]:
	if axis < 0:
		return cells
	var kept: Array[Vector3i] = []
	for cell in cells:
		if cell[axis] >= index and cell[axis] < index + count:
			kept.append(cell)
	return kept


static func sample(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, spot_size: int, search_size: int, speed: int, rng: RandomNumberGenerator, material: PackedFloat32Array, cache: ShapeCache, job: VoxelFrame.EditJob = null, report: Dictionary = {}, selection_index: RefCounted = null) -> Array[Vector3i]:
	var search_spans := sphere_spans(cache, search_size)
	var surface := SprayIndex.SurfaceIndex.new()
	surface.frame = frame
	var candidates := SprayIndex.build_candidates(center, frame, search_size, context.selection, job, selection_index, search_spans, surface)
	report["local"] = 0
	report["candidates"] = candidates.total
	report["chunks"] = candidates.chunks_scanned
	report["rows"] = candidates.rows_scanned
	report["index_builds"] = candidates.index_builds
	report["index_grid_reads"] = candidates.index_grid_reads
	report["index_build_slots"] = candidates.index_build_slots
	report["selection_checked"] = candidates.selection_checked
	report["selection_builds"] = candidates.selection_builds
	report["selection_work"] = candidates.selection_work
	if candidates.selection_index != null:
		report["selection_index"] = candidates.selection_index
	var count := mini(speed, candidates.total)
	if count <= 0:
		_add_surface_stats(report, surface)
		report["spots"] = 0
		return []
	var spots: Array[Vector3i] = []
	var overrides := {}
	for i in count:
		if job and not job.checkpoint(i):
			return []
		var pick := rng.randi_range(i, candidates.total - 1)
		var first: Vector3i = overrides[i] if overrides.has(i) else candidates.candidate(i)
		var second: Vector3i = overrides[pick] if overrides.has(pick) else candidates.candidate(pick)
		overrides[i] = second
		if pick != i:
			overrides[pick] = first
		spots.append(second)
	report["spots"] = spots.size()
	report["rank_calls"] = candidates.rank_calls
	report["rank_rows"] = candidates.rank_rows
	var changes := footprints_selected(spots, frame, context, spot_size, material, cache, job, report, surface)
	_add_surface_stats(report, surface)
	report["row_ops"] = int(report.get("rows", 0)) + int(report.get("rank_rows", 0)) + int(report.get("footprint_rows", 0)) + int(report.get("selection_work", 0))
	if job and not job.checkpoint(0):
		return []
	return _expanded_cells(changes, frame, context, job, true)


class Occupancy extends RefCounted:
	var frame: VoxelFrame
	var grids := {}

	func occupied(cell: Vector3i) -> bool:
		return _material_id(cell) > 0

	func exposed(cell: Vector3i) -> bool:
		if not occupied(cell):
			return false
		for direction in VoxelFrame.DIRECTIONS:
			if not occupied(cell + direction):
				return true
		return false

	func _material_id(cell: Vector3i) -> int:
		var location := VoxelFrame.chunk_position(cell)
		var cached: Variant = grids.get(location)
		if cached == null and not grids.has(location):
			cached = frame.chunks.get(location)
			grids[location] = cached
		if cached == null:
			return 0
		var chunk: VoxelFrame.Chunk = cached
		var local := cell - location * VoxelFrame.CHUNK_SIZE
		return chunk.cell_id_at_slot(local.x + VoxelFrame.CHUNK_SIZE * (local.y + VoxelFrame.CHUNK_SIZE * local.z))


static func expand_occupied(changes: Dictionary, occupancy: Occupancy, axes: int, origin_twice: Vector3i, selection: Dictionary, job: VoxelFrame.EditJob = null, surface_only := false) -> Dictionary:
	var expanded := {}
	var masks: Array[int] = []
	for mask in 8:
		if (mask & ~axes) == 0:
			masks.append(mask)
	var filtered := not selection.is_empty()
	var completed := 0
	for cell: Vector3i in changes:
		var value: PackedFloat32Array = changes[cell]
		for mask in masks:
			var destination := _reflect(cell, mask, origin_twice)
			var held := occupancy.exposed(destination) if surface_only else occupancy.occupied(destination)
			if (not filtered or selection.has(destination)) and held:
				expanded[destination] = value
			completed += 1
			if job and completed % 4096 == 0 and not job.checkpoint(completed):
				return {}
	if axes == 0:
		return expanded
	for cell: Vector3i in changes:
		var held := occupancy.exposed(cell) if surface_only else occupancy.occupied(cell)
		if (not filtered or selection.has(cell)) and held:
			expanded[cell] = changes[cell]
		completed += 1
		if job and completed % 4096 == 0 and not job.checkpoint(completed):
			return {}
	return expanded


static func _reflect(cell: Vector3i, mask: int, origin_twice: Vector3i) -> Vector3i:
	var destination := cell
	for axis in 3:
		if mask & (1 << axis):
			destination[axis] = origin_twice[axis] - cell[axis]
	return destination


static func footprints_selected(spots: Array[Vector3i], frame: VoxelFrame, context: VoxelFrame.EditContext, spot_size: int, material: PackedFloat32Array, cache: ShapeCache, job: VoxelFrame.EditJob = null, report: Dictionary = {}, surface: RefCounted = null) -> Dictionary:
	var changes := {}
	if spots.is_empty():
		report["footprint_cells"] = 0
		report["footprint_visits"] = 0
		report["footprint_rows"] = 0
		return changes
	if spot_size == 1:
		for spot in spots:
			if surface == null or surface.exposed(spot):
				changes[spot] = material
		report["footprint_cells"] = changes.size()
		report["footprint_visits"] = changes.size()
		report["footprint_rows"] = 0
		return changes
	var first := VoxelBrushSize.first_offset(spot_size)
	var last := VoxelBrushSize.last_offset(spot_size)
	var min_spot := spots[0]
	var max_spot := spots[0]
	for spot in spots:
		min_spot = Vector3i(mini(min_spot.x, spot.x), mini(min_spot.y, spot.y), mini(min_spot.z, spot.z))
		max_spot = Vector3i(maxi(max_spot.x, spot.x), maxi(max_spot.y, spot.y), maxi(max_spot.z, spot.z))
	var min_chunk := VoxelFrame.chunk_position(min_spot + Vector3i.ONE * first)
	var max_chunk := VoxelFrame.chunk_position(max_spot + Vector3i.ONE * last)
	var occupied_hint := 0
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(x, y, z))
				if chunk != null:
					occupied_hint += chunk.occupied_count
	var stats := {"index_builds": 0, "index_grid_reads": 0, "index_build_slots": 0}
	if occupied_hint <= spots.size() * 4:
		var scanned := footprints_scan(spots, frame, context, spot_size, material, cache, job, report, stats, surface)
		_add_footprint_stats(report, stats)
		return scanned
	var spot_rows := rows(cache, spot_size)
	var selection: Dictionary = context.selection
	var filtered := not selection.is_empty()
	var by_row := {}
	var completed := 0
	for spot in spots:
		for row in spot_rows:
			var key := Vector2i(spot.y + row.x, spot.z + row.y)
			var span := Vector2i(spot.x + row.z, spot.x + row.w)
			var bucket: Variant = by_row.get(key)
			if bucket == null:
				by_row[key] = [span]
			else:
				bucket.append(span)
			completed += 1
			if job and completed % 4096 == 0 and not job.checkpoint(completed):
				return {}
	report["footprint_rows"] = by_row.size()
	var visits := 0
	for key: Vector2i in by_row:
		var spans: Array = by_row[key]
		spans.sort()
		var first_span: Vector2i = spans[0]
		var low := first_span.x
		var high := first_span.y
		for i in range(1, spans.size()):
			var span: Vector2i = spans[i]
			if span.x <= high + 1:
				high = maxi(high, span.y)
			else:
				visits += _emit_row_span(changes, frame, key, low, high, filtered, selection, material, stats, surface)
				low = span.x
				high = span.y
			completed += 1
			if job and completed % 4096 == 0 and not job.checkpoint(completed):
				return {}
		visits += _emit_row_span(changes, frame, key, low, high, filtered, selection, material, stats, surface)
		completed += 1
		if job and completed % 4096 == 0 and not job.checkpoint(completed):
			return {}
	report["footprint_cells"] = changes.size()
	report["footprint_visits"] = visits
	_add_footprint_stats(report, stats)
	return changes


static func _add_footprint_stats(report: Dictionary, stats: Dictionary) -> void:
	report["index_builds"] = int(report.get("index_builds", 0)) + int(stats.get("index_builds", 0))
	report["index_grid_reads"] = int(report.get("index_grid_reads", 0)) + int(stats.get("index_grid_reads", 0))
	report["index_build_slots"] = int(report.get("index_build_slots", 0)) + int(stats.get("index_build_slots", 0))


static func _add_surface_stats(report: Dictionary, surface: RefCounted) -> void:
	report["index_builds"] = int(report.get("index_builds", 0)) + surface.index_builds
	report["index_grid_reads"] = int(report.get("index_grid_reads", 0)) + surface.index_grid_reads
	report["index_build_slots"] = int(report.get("index_build_slots", 0)) + surface.index_build_slots


static func footprints_scan(spots: Array[Vector3i], frame: VoxelFrame, context: VoxelFrame.EditContext, spot_size: int, material: PackedFloat32Array, cache: ShapeCache, job: VoxelFrame.EditJob = null, report: Dictionary = {}, stats: Dictionary = {}, surface: RefCounted = null) -> Dictionary:
	var changes := {}
	var selection: Dictionary = context.selection
	var filtered := not selection.is_empty()
	var spans := sphere_spans(cache, spot_size)
	var first := VoxelBrushSize.first_offset(spot_size)
	var last := VoxelBrushSize.last_offset(spot_size)
	var completed := 0
	var visits := 0
	for spot in spots:
		var min_chunk := VoxelFrame.chunk_position(spot + Vector3i.ONE * first)
		var max_chunk := VoxelFrame.chunk_position(spot + Vector3i.ONE * last)
		for x in range(min_chunk.x, max_chunk.x + 1):
			for y in range(min_chunk.y, max_chunk.y + 1):
				for z in range(min_chunk.z, max_chunk.z + 1):
					var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(x, y, z))
					if chunk == null or not SprayIndex.chunk_intersects(spot, spot_size, chunk):
						continue
					var was_current := chunk.occupancy_index_current()
					var index := chunk.occupancy_rows()
					if index == null:
						continue
					if not was_current:
						stats["index_builds"] = int(stats.get("index_builds", 0)) + 1
						stats["index_grid_reads"] = int(stats.get("index_grid_reads", 0)) + index.grid_reads
						stats["index_build_slots"] = int(stats.get("index_build_slots", 0)) + index.build_slots
					var origin := chunk.origin()
					for row in VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE:
						completed += 1
						if job and completed % 4096 == 0 and not job.checkpoint(completed):
							return {}
						if index.counts[row] == 0:
							continue
						var local_y := row & (VoxelFrame.CHUNK_SIZE - 1)
						var local_z := row >> VoxelFrame.CHUNK_SHIFT
						var world_y := origin.y + local_y
						var world_z := origin.z + local_z
						var relative: Vector2i = spans.span(world_y - spot.y, world_z - spot.z)
						if relative.x > relative.y:
							continue
						visits += _emit_chunk_row(changes, chunk, index, row, world_y, world_z, spot.x + relative.x, spot.x + relative.y, filtered, selection, material, surface)
					completed += 1
					if job and not job.checkpoint(completed):
						return {}
	report["footprint_cells"] = changes.size()
	report["footprint_visits"] = visits
	report["footprint_rows"] = completed
	return changes


static func _emit_row_span(changes: Dictionary, frame: VoxelFrame, key: Vector2i, low: int, high: int, filtered: bool, selection: Dictionary, material: PackedFloat32Array, stats: Dictionary = {}, surface: RefCounted = null) -> int:
	var visits := 0
	var y := key.x
	var z := key.y
	var chunk_y := y >> VoxelFrame.CHUNK_SHIFT
	var chunk_z := z >> VoxelFrame.CHUNK_SHIFT
	var local_y := y & (VoxelFrame.CHUNK_SIZE - 1)
	var local_z := z & (VoxelFrame.CHUNK_SIZE - 1)
	var row := SprayIndex.row_index(local_y, local_z)
	var first_chunk := low >> VoxelFrame.CHUNK_SHIFT
	var last_chunk := high >> VoxelFrame.CHUNK_SHIFT
	for chunk_x in range(first_chunk, last_chunk + 1):
		var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(chunk_x, chunk_y, chunk_z))
		if chunk == null:
			continue
		var was_current := chunk.occupancy_index_current()
		var index := chunk.occupancy_rows()
		if index == null:
			continue
		if not was_current and not stats.is_empty():
			stats["index_builds"] = int(stats.get("index_builds", 0)) + 1
			stats["index_grid_reads"] = int(stats.get("index_grid_reads", 0)) + index.grid_reads
			stats["index_build_slots"] = int(stats.get("index_build_slots", 0)) + index.build_slots
		visits += _emit_chunk_row(changes, chunk, index, row, y, z, low, high, filtered, selection, material, surface)
	return visits


static func _emit_chunk_row(changes: Dictionary, chunk: VoxelFrame.Chunk, index: VoxelFrame.OccupancyRows, row: int, y: int, z: int, low: int, high: int, filtered: bool, selection: Dictionary, material: PackedFloat32Array, surface: RefCounted = null) -> int:
	var origin_x := chunk.location.x * VoxelFrame.CHUNK_SIZE
	var local_low := maxi(low, origin_x) - origin_x
	var local_high := mini(high, origin_x + VoxelFrame.CHUNK_SIZE - 1) - origin_x
	if local_low > local_high:
		return 0
	var mask := index.masks[row]
	if surface != null:
		mask &= surface.masks_for(chunk.location)[row]
	var bits := mask & SprayIndex.span_mask(local_low, local_high)
	if bits == 0:
		return 0
	var visits := 0
	for local_x in range(local_low, local_high + 1):
		if bits & (1 << local_x) == 0:
			continue
		visits += 1
		var cell := Vector3i(origin_x + local_x, y, z)
		if filtered and not selection.has(cell):
			continue
		changes[cell] = material
	return visits


static func _expanded_cells(changes: Dictionary, frame: VoxelFrame, context: VoxelFrame.EditContext, job: VoxelFrame.EditJob, surface_only := false) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	if context.axes == 0 and context.selection.is_empty():
		if job and not job.checkpoint(0):
			return []
		cells.assign(changes.keys())
		return cells
	var occupancy := Occupancy.new()
	occupancy.frame = frame
	cells.assign(expand_occupied(changes, occupancy, context.axes, context.origin_twice, context.selection, job, surface_only).keys())
	return cells


static func local_cells(center: Vector3i, reach: int, frame: VoxelFrame, context: VoxelFrame.EditContext, job: VoxelFrame.EditJob = null) -> Array[Vector3i]:
	var min_chunk := VoxelFrame.chunk_position(center - Vector3i.ONE * reach)
	var max_chunk := VoxelFrame.chunk_position(center + Vector3i.ONE * reach)
	var limit := reach * reach
	var selection: Dictionary = context.selection
	var filtered := not selection.is_empty()
	var chunk_size := VoxelFrame.CHUNK_SIZE
	var cells: Array[Vector3i] = []
	var completed := 0
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(x, y, z))
				if chunk == null:
					continue
				var origin := chunk.location * chunk_size
				var rows := chunk.occupancy_rows()
				for row in rows.masks.size():
					var mask := rows.masks[row]
					if mask == 0:
						continue
					var local_y := row % chunk_size
					var local_z := row / chunk_size
					while mask != 0:
						var local_x := VoxelFrame.Chunk.first_column(mask)
						mask &= mask - 1
						var cell := origin + Vector3i(local_x, local_y, local_z)
						if Vector3(cell - center).length_squared() > limit:
							continue
						if filtered and not selection.has(cell):
							continue
						cells.append(cell)
						completed += 1
						if job and completed % 4096 == 0 and not job.checkpoint(completed):
							return []
	return cells


static func candidate_cells(center: Vector3i, local: Array[Vector3i], search_size: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	var shell := VoxelBrushSize.reach(search_size)
	var limit := shell * shell
	for cell in local:
		var offset := cell - center
		if offset.x * offset.x + offset.y * offset.y + offset.z * offset.z > limit:
			continue
		if VoxelBrushSize.contains_sphere(search_size, offset):
			cells.append(cell)
	return cells


static func footprints(spots: Array[Vector3i], local: Array[Vector3i], spot_size: int, material: PackedFloat32Array, cache: ShapeCache, job: VoxelFrame.EditJob = null, surface: RefCounted = null) -> Dictionary:
	var changes := {}
	if spot_size == 1:
		for spot in spots:
			changes[spot] = material
		return _exposed_changes(changes, surface)
	var spot_rows := rows(cache, spot_size)
	var completed := 0
	if local.size() <= spot_rows.size():
		var spot_pattern := pattern(cache, spot_size)
		for spot in spots:
			for cell in local:
				completed += 1
				if spot_pattern.has(cell - spot):
					changes[cell] = material
				if job and completed % 4096 == 0 and not job.checkpoint(completed):
					return {}
		return _exposed_changes(changes, surface)
	var allowed := {}
	for cell in local:
		allowed[cell] = true
	var by_row := {}
	for spot in spots:
		for row in spot_rows:
			var key := Vector2i(spot.y + row.x, spot.z + row.y)
			var span := Vector2i(spot.x + row.z, spot.x + row.w)
			var bucket: Variant = by_row.get(key)
			if bucket == null:
				by_row[key] = [span]
			else:
				bucket.append(span)
			completed += 1
			if job and completed % 4096 == 0 and not job.checkpoint(completed):
				return {}
	if job and not job.checkpoint(completed):
		return {}
	for key: Vector2i in by_row:
		var spans: Array = by_row[key]
		spans.sort()
		var first: Vector2i = spans[0]
		var lo := first.x
		var hi := first.y
		for i in range(1, spans.size()):
			var span: Vector2i = spans[i]
			if span.x <= hi + 1:
				hi = maxi(hi, span.y)
			else:
				_add_span(changes, allowed, key.x, key.y, lo, hi, material)
				lo = span.x
				hi = span.y
			completed += 1
			if job and completed % 4096 == 0 and not job.checkpoint(completed):
				return {}
		_add_span(changes, allowed, key.x, key.y, lo, hi, material)
		completed += 1
		if job and completed % 4096 == 0 and not job.checkpoint(completed):
			return {}
	return _exposed_changes(changes, surface)


static func _exposed_changes(changes: Dictionary, surface: RefCounted) -> Dictionary:
	if surface == null:
		return changes
	var exposed := {}
	for cell: Vector3i in changes:
		if surface.exposed(cell):
			exposed[cell] = changes[cell]
	return exposed


static func _add_span(changes: Dictionary, allowed: Dictionary, y: int, z: int, lo: int, hi: int, material: PackedFloat32Array) -> void:
	for x in range(lo, hi + 1):
		var cell := Vector3i(x, y, z)
		if allowed.has(cell):
			changes[cell] = material


static func witness(frame: VoxelFrame, cells: Array[Vector3i]) -> Dictionary:
	var out := {}
	for cell in cells:
		var location := VoxelFrame.chunk_position(cell)
		if out.has(location):
			continue
		var chunk: VoxelFrame.Chunk = frame.chunks.get(location)
		if chunk != null:
			out[location] = [chunk, chunk.voxel_revision]
	return out

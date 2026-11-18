extends RefCounted


const StampPattern := preload("res://plugins/brush/StampPatternJob.gd")
const StampSettings := preload("res://plugins/brush/StampToolSettings.gd")


var _spot_offsets_cache := {}
var _spot_radius_cache := {}
var _sphere_offsets_cache := {}
var _frame: VoxelFrame


func sample(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, spot_diameter: int, spray_radius: int, speed: int, rng: RandomNumberGenerator, material: PackedFloat32Array) -> Array[Vector3i]:
	_frame = frame
	var reach := spray_radius + _spot_radius(spot_diameter)
	var local := _local_cells(center, reach, frame, context)
	var candidates := _candidates(center, local, spray_radius)
	var count := mini(speed, candidates.size())
	if count <= 0:
		return []
	var indices: Array[int] = []
	for i in candidates.size():
		indices.append(i)
	var spots: Array[Vector3i] = []
	for i in count:
		var pick := rng.randi_range(i, indices.size() - 1)
		var swap := indices[i]
		indices[i] = indices[pick]
		indices[pick] = swap
		spots.append(candidates[indices[i]])
	var changes := _footprints(spots, local, spot_diameter, material)
	var cells: Array[Vector3i] = []
	for cell: Vector3i in context.expand(changes, frame, true, null).keys():
		if _exposed(cell):
			cells.append(cell)
	return cells


func _candidates(center: Vector3i, local: Array[Vector3i], spray_radius: int) -> Array[Vector3i]:
	var limit := spray_radius * spray_radius
	var cells: Array[Vector3i] = []
	for cell in local:
		if Vector3(cell - center).length_squared() <= limit and _exposed(cell):
			cells.append(cell)
	return cells


func _footprints(spots: Array[Vector3i], local: Array[Vector3i], spot_diameter: int, material: PackedFloat32Array) -> Dictionary:
	var offsets := _spot_offsets(spot_diameter)
	var changes := {}
	if local.size() < offsets.size():
		var pattern := {}
		for offset in offsets:
			pattern[offset] = true
		for spot in spots:
			for cell in local:
				if pattern.has(cell - spot) and _exposed(cell):
					changes[cell] = material
		return changes
	var occupied := {}
	for cell in local:
		occupied[cell] = true
	for spot in spots:
		for offset in offsets:
			var cell := spot + offset
			if occupied.has(cell) and _exposed(cell):
				changes[cell] = material
	return changes


func _exposed(cell: Vector3i) -> bool:
	if not _frame.has(cell):
		return false
	for direction in VoxelFrame.DIRECTIONS:
		if not _frame.has(cell + direction):
			return true
	return false


func _local_cells(center: Vector3i, reach: int, frame: VoxelFrame, context: VoxelFrame.EditContext) -> Array[Vector3i]:
	var min_chunk := VoxelFrame.chunk_position(center - Vector3i.ONE * reach)
	var max_chunk := VoxelFrame.chunk_position(center + Vector3i.ONE * reach)
	var locations := _chunk_locations(min_chunk, max_chunk)
	var chunk_cells := 0
	for chunk_location in locations:
		if frame.chunks.has(chunk_location):
			chunk_cells += VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE * VoxelFrame.CHUNK_SIZE
	var side := 2 * reach + 1
	var cells: Array[Vector3i] = []
	if chunk_cells > 0 and chunk_cells < side * side * side:
		var limit := reach * reach
		for chunk_location in locations:
			var chunk: VoxelFrame.Chunk = frame.chunks.get(chunk_location)
			if chunk == null:
				continue
			for cell in chunk.world_cells():
				if Vector3(cell - center).length_squared() > limit:
					continue
				if not _allows(cell, frame, context):
					continue
				cells.append(cell)
		return cells
	for offset in _sphere_offsets(reach):
		var cell := center + offset
		if _allows(cell, frame, context):
			cells.append(cell)
	return cells


static func _chunk_locations(min_chunk: Vector3i, max_chunk: Vector3i) -> Array[Vector3i]:
	var locations: Array[Vector3i] = []
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				locations.append(Vector3i(x, y, z))
	return locations


func _spot_offsets(diameter: int) -> Array[Vector3i]:
	if _spot_offsets_cache.has(diameter):
		return _spot_offsets_cache[diameter]
	var offsets: Array[Vector3i] = []
	offsets.assign(StampPattern.build_pattern(diameter, StampSettings.BrushShape.SPHERE).keys())
	_spot_offsets_cache[diameter] = offsets
	return offsets


func _spot_radius(diameter: int) -> int:
	if _spot_radius_cache.has(diameter):
		return _spot_radius_cache[diameter]
	var longest := 0
	for offset in _spot_offsets(diameter):
		longest = maxi(longest, offset.length_squared())
	var radius := ceili(sqrt(float(longest)))
	_spot_radius_cache[diameter] = radius
	return radius


func _sphere_offsets(radius: int) -> Array[Vector3i]:
	if _sphere_offsets_cache.has(radius):
		return _sphere_offsets_cache[radius]
	var offsets: Array[Vector3i] = []
	var limit := radius * radius
	for x in range(-radius, radius + 1):
		for y in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var offset := Vector3i(x, y, z)
				if offset.length_squared() <= limit:
					offsets.append(offset)
	_sphere_offsets_cache[radius] = offsets
	return offsets


func _allows(cell: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext) -> bool:
	return frame.has(cell) and (context.selection.is_empty() or context.selection.has(cell))

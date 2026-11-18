extends RefCounted


static func find(result: Dictionary, frame: VoxelFrame, seed_cell: Vector3i, target_material: PackedFloat32Array, connected: bool, value: Variant = true, selection_mask: Dictionary = {}, job: VoxelFrame.EditJob = null) -> bool:
	if frame == null:
		return true
	if connected:
		return _find_connected(result, frame, seed_cell, target_material, value, selection_mask, job)
	return _find_occupied(result, frame, target_material, value, selection_mask, job)


static func _find_connected(result: Dictionary, frame: VoxelFrame, seed_cell: Vector3i, target_material: PackedFloat32Array, value: Variant, selection_mask: Dictionary, job: VoxelFrame.EditJob) -> bool:
	var pending: Array[Vector3i] = [seed_cell]
	result[seed_cell] = value
	var examined := 0
	while not pending.is_empty():
		var cell_position: Vector3i = pending.pop_back()
		for direction in VoxelFrame.DIRECTIONS:
			var neighbor: Vector3i = cell_position + direction
			if result.has(neighbor) or (not selection_mask.is_empty() and not selection_mask.has(neighbor)):
				continue
			if frame.matches(neighbor, target_material):
				result[neighbor] = value
				pending.append(neighbor)
		examined += 1
		if job and examined % 4096 == 0 and not job.checkpoint(result.size()):
			return false
	return true


static func _find_occupied(result: Dictionary, frame: VoxelFrame, target_material: PackedFloat32Array, value: Variant, selection_mask: Dictionary, job: VoxelFrame.EditJob) -> bool:
	var examined := 0
	for chunk in frame.chunks.values():
		for cell_position in chunk.world_cells():
			if chunk.matches(cell_position, target_material) and (selection_mask.is_empty() or selection_mask.has(cell_position)):
				result[cell_position] = value
			examined += 1
			if job and examined % 4096 == 0 and not job.checkpoint(examined):
				return false
	return true

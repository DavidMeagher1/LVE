extends "res://tests/spray_reference.gd"


const VoxelBrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")

var search_size := 1


func sample_size(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, spot_size: int, search_size_value: int, speed: int, rng: RandomNumberGenerator, material: PackedFloat32Array) -> Array[Vector3i]:
	search_size = search_size_value
	return sample(center, frame, context, spot_size, VoxelBrushSize.reach(search_size_value), speed, rng, material)


func _candidates(center: Vector3i, local: Array[Vector3i], _reach: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for cell in local:
		if VoxelBrushSize.contains_sphere(search_size, cell - center) and _exposed(cell):
			cells.append(cell)
	return cells


func _local_cells(center: Vector3i, reach: int, frame: VoxelFrame, context: VoxelFrame.EditContext) -> Array[Vector3i]:
	var min_chunk := VoxelFrame.chunk_position(center - Vector3i.ONE * reach)
	var max_chunk := VoxelFrame.chunk_position(center + Vector3i.ONE * reach)
	var limit := reach * reach
	var cells: Array[Vector3i] = []
	for x in range(min_chunk.x, max_chunk.x + 1):
		for y in range(min_chunk.y, max_chunk.y + 1):
			for z in range(min_chunk.z, max_chunk.z + 1):
				var chunk: VoxelFrame.Chunk = frame.chunks.get(Vector3i(x, y, z))
				if chunk == null:
					continue
				for cell in chunk.world_cells():
					if Vector3(cell - center).length_squared() > limit:
						continue
					if not _allows(cell, frame, context):
						continue
					cells.append(cell)
	return cells

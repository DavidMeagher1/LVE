extends RefCounted


const TERRAIN := preload("res://plugins/Terrain/TerrainTool.gd")
const SmoothOperation := preload("res://plugins/Terrain/SmoothOperation.gd")


static func new_job() -> SmoothJobReference:
	return SmoothJobReference.new()


class SmoothJobReference extends TERRAIN.SmoothJob:
	var lookups := 0

	func _occupancy(cells: Array) -> Variant:
		var occupied := {}
		var offsets: Array = SmoothOperation.kernel_offsets(radius)
		var completed := 0
		for cell: Vector3i in cells:
			for offset: Vector3i in offsets:
				var point := cell + offset
				if edited_frame.has(point):
					occupied[point] = true
			completed += 1
			lookups += offsets.size()
			if completed % 256 == 0 and not checkpoint(completed):
				return null
		return occupied

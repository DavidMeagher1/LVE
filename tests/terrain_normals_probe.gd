extends "res://plugins/Terrain/TerrainTool.gd"


var surface_frames := 0
var surface_calls := 0


func reset_normals_probe() -> void:
	surface_frames = 0
	surface_calls = 0


func _frame_for_pick(pick: PickResult, origin: Vector3) -> TerrainFrame:
	surface_calls += 1
	var frame := super._frame_for_pick(pick, origin)
	if frame != null and frame.follows_surface:
		surface_frames += 1
	return frame

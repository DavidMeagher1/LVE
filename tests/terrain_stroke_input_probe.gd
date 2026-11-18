extends "res://plugins/Terrain/TerrainTool.gd"


var force_worker := false
var prep_started := false
var last_prep_depth := -1


func reset_probe() -> void:
	prep_started = false
	last_prep_depth = -1


func _dab_is_large(radius: int) -> bool:
	return force_worker or super._dab_is_large(radius)


func _start_prep_dab(center_point: Vector3) -> void:
	prep_started = true
	super._start_prep_dab(center_point)
	last_prep_depth = _tick_job.prep_depth if _tick_job != null else -1

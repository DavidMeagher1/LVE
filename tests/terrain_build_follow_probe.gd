extends "res://plugins/Terrain/TerrainTool.gd"


var build_centers: Array = []
var build_normals: Array = []
var build_origins: Array = []


func reset_dabs() -> void:
	build_centers = []
	build_normals = []
	build_origins = []


func _run_dab(cell: Vector3i) -> void:
	if _stroke_tool == TerrainSettings.Tools.BUILD:
		build_centers.append(_plane_point(cell))
		build_normals.append(_stroke_frame.normal if _stroke_frame != null else Vector3.ZERO)
		build_origins.append(_stroke_frame.origin if _stroke_frame != null else Vector3.ZERO)
		super._run_dab(cell)

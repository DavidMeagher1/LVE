extends "res://plugins/Terrain/TerrainTool.gd"


var dab_anchors: Array[Vector3i] = []


func reset_profile() -> void:
	dab_anchors = []


func _run_dab(cell: Vector3i) -> void:
	super._run_dab(cell)
	if _stroke_tool == TerrainSettings.Tools.BUILD or _stroke_tool == TerrainSettings.Tools.FLATTEN:
		dab_anchors.append(cell)

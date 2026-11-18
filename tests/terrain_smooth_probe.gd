extends "res://plugins/Terrain/TerrainTool.gd"


var dab_hits: Array = []
var dab_entries: Array = []


func reset_dabs() -> void:
	dab_hits = []
	dab_entries = []


func _run_smooth_dab() -> void:
	super._run_smooth_dab()
	dab_hits.append(_smooth_hit)
	dab_entries.append(_smooth_entry)

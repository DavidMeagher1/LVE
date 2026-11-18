extends "res://plugins/brush/BrushPreview.gd"


var request_calls := 0
var installs := 0
var discards := 0
var request_us := 0
var material_us := 0
var show_us := 0
var finish_us := 0
var install_max_us := 0
var job_chunk_count := 0
var build_us := 0
var merge_us := 0
var geometry_bytes := 0
var preview_cells := 0


func reset_probe() -> void:
	request_calls = 0
	installs = 0
	discards = 0
	request_us = 0
	material_us = 0
	show_us = 0
	finish_us = 0
	install_max_us = 0
	job_chunk_count = 0
	build_us = 0
	merge_us = 0
	geometry_bytes = 0
	preview_cells = 0


func set_brush_material(cell_material: PackedFloat32Array) -> void:
	var started := Time.get_ticks_usec()
	super.set_brush_material(cell_material)
	material_us = Time.get_ticks_usec() - started


func show_voxels(colors: Dictionary, color: Color, outline: bool = false, cube_diameter: int = 0, use_voxel_colors: bool = true, token: Variant = null) -> void:
	var started := Time.get_ticks_usec()
	super.show_voxels(colors, color, outline, cube_diameter, use_voxel_colors, token)
	show_us = Time.get_ticks_usec() - started


func submit_prepared(payload) -> void:
	var started := Time.get_ticks_usec()
	super.submit_prepared(payload)
	show_us = Time.get_ticks_usec() - started
	request_us = show_us
	request_calls += 1


func _request(cells: Dictionary, style: PreviewStyle, use_voxel_colors: bool = false, color_key: Color = Color.WHITE, token: Variant = null) -> void:
	var started := Time.get_ticks_usec()
	super._request(cells, style, use_voxel_colors, color_key, token)
	request_us = Time.get_ticks_usec() - started
	request_calls += 1


func _finish_preview() -> void:
	var before := mesh_id()
	var job = _preview_job
	if job != null:
		job_chunk_count = job.chunk_count
		build_us = job.build_us
		merge_us = job.merge_us
		geometry_bytes = job.geometry_bytes
		preview_cells = job.cells.size()
	var started := Time.get_ticks_usec()
	super._finish_preview()
	finish_us = Time.get_ticks_usec() - started
	if mesh_id() != before:
		installs += 1
		install_max_us = maxi(install_max_us, finish_us)
	else:
		discards += 1


func mesh_id() -> int:
	if mesh == null:
		return 0
	return mesh.get_instance_id()

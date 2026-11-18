extends "res://plugins/paint/SprayTool.gd"


var sample_us := 0
var sample_calls := 0
var worker_samples := 0
var sample_cells := 0
var pick_us := 0
var visual_us := 0
var show_us := 0
var show_calls := 0
var input_us := 0
var batch_us := 0


func reset_probe() -> void:
	sample_us = 0
	sample_calls = 0
	worker_samples = 0
	sample_cells = 0
	pick_us = 0
	visual_us = 0
	show_us = 0
	show_calls = 0
	input_us = 0
	batch_us = 0
	last_work_estimate = 0
	last_capture_chunks = 0
	last_index_builds = 0
	last_index_grid_reads = 0
	last_index_build_slots = 0
	last_selection_builds = 0
	last_row_ops = 0
	last_footprint_visits = 0


func clear_shape_caches() -> void:
	super.clear_shape_caches()


func handle_input(event: InputEvent, pos: Vector2) -> bool:
	var started := Time.get_ticks_usec()
	var consumed := super.handle_input(event, pos)
	input_us = Time.get_ticks_usec() - started
	return consumed


func pick_start(request: PickRequest) -> PickResult:
	var started := Time.get_ticks_usec()
	var result := super.pick_start(request)
	pick_us = Time.get_ticks_usec() - started
	return result


func pick_drag(request: PickRequest) -> PickResult:
	var started := Time.get_ticks_usec()
	var result := super.pick_drag(request)
	pick_us = Time.get_ticks_usec() - started
	return result


func update_visual(pick: PickResult) -> void:
	var started := Time.get_ticks_usec()
	super.update_visual(pick)
	visual_us = Time.get_ticks_usec() - started


func _ensure_batch(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array) -> bool:
	var started := Time.get_ticks_usec()
	var fresh := super._ensure_batch(center, frame, context, material)
	batch_us = Time.get_ticks_usec() - started
	return fresh


func _sample(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, rng: RandomNumberGenerator = null, material = null, spot_size := -1, search_size := -1, speed := -1) -> Array[Vector3i]:
	var started := Time.get_ticks_usec()
	var cells := super._sample(center, frame, context, rng, material, spot_size, search_size, speed)
	sample_us = Time.get_ticks_usec() - started
	sample_calls += 1
	sample_cells = cells.size()
	return cells


func _show_spots(cells: Array[Vector3i]) -> void:
	var started := Time.get_ticks_usec()
	super._show_spots(cells)
	show_us = Time.get_ticks_usec() - started
	show_calls += 1


func _build_sample_job(frame: VoxelFrame, center: Vector3i, context: VoxelFrame.EditContext, material: PackedFloat32Array, estimate: int, spot_size := -1, search_size := -1, speed := -1) -> SpraySamplingJob:
	var job := super._build_sample_job(frame, center, context, material, estimate, spot_size, search_size, speed)
	sample_calls += 1
	worker_samples += 1
	return job

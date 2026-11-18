extends "./SelectTool.gd"


const PUBLISH_BUDGET_US := 2000
const MERGE_SLICE := 256

var _source_document: VoxelDocument
var _source_frame: VoxelFrame
var _job: WandJob
var _retired_jobs: Array[WandJob] = []
var _reaping := false
var _operation_id := 0

class WandJob extends VoxelFrame.EditJob:
	var source_frame: VoxelFrame
	var seed_cell := Vector3i.ZERO
	var target_material := VoxelFrame.material(Color.TRANSPARENT)
	var connected := true
	var previous_selection := {}
	var mode := 0
	var result := {}
	var matching_cells := {}
	var batch_queue: VoxelRegionSearch.BatchQueue
	var batch_cursor: VoxelRegionSearch.BatchCursor

	func run() -> void:
		stage("Finding connected voxels" if connected else "Finding matching voxels", -1 if connected else source_frame.count())
		var stream: Callable = Callable(self, "_stream_batch") if batch_queue != null else Callable()
		var slice_axis := edit_context.slice_axis if edit_context else -1
		var slice_index := edit_context.slice_index if edit_context else 0
		var slice_count := edit_context.slice_count if edit_context else 1
		matching_cells = {}
		if not VoxelRegionSearch.find(matching_cells, source_frame, seed_cell, target_material, connected, true, {}, self, stream, slice_axis, slice_index, slice_count):
			return
		if not checkpoint(0):
			return
		if edit_context:
			matching_cells = edit_context.expand(matching_cells, source_frame, false, null, self)
		if not checkpoint(0):
			return
		stage("Applying selection mode", matching_cells.size())
		result = {} if mode == 0 else previous_selection.duplicate()
		var completed := 0
		for cell_position in matching_cells:
			if mode == 2:
				result.erase(cell_position)
			else:
				result[cell_position] = true
			completed += 1
			if completed % 4096 == 0 and not checkpoint(completed):
				return

	func _stream_batch(cells: Array[Vector3i]) -> void:
		var expanded := {}
		for cell_position in cells:
			expanded[cell_position] = true
		if edit_context:
			expanded = edit_context.expand(expanded, source_frame, false, null, self)
		if not batch_queue.push(expanded):
			cancel()


func _enter_tree() -> void:
	if not State.edit_context_changing.is_connected(_cancel_selection):
		State.edit_context_changing.connect(_cancel_selection)


func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	var live := _job
	_job = null
	var tx := _edit
	_edit = null
	_source_document = null
	_source_frame = null
	if tx != null:
		State.cancel_edit(tx)
	State.finish_operation(_operation_id)
	_operation_id = 0
	var joins: Array[WandJob] = _retired_jobs.duplicate()
	_retired_jobs.clear()
	if live != null:
		joins.append(live)
	for job in joins:
		job.cancel()
		if job.batch_queue != null:
			job.batch_queue.cancel()
	for job in joins:
		if job.worker_task_id != -1:
			WorkerThreadPool.wait_for_task_completion(job.worker_task_id)
	if State.edit_context_changing.is_connected(_cancel_selection):
		State.edit_context_changing.disconnect(_cancel_selection)


func handle_input(event: InputEvent, pos: Vector2) -> bool:
	if event.is_action_pressed("ui_cancel") and _job:
		_cancel_selection()
		return true
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			return false
		if event.pressed and _job == null:
			var ray := _ray(pos)
			_commit(_pick_start(ray[0], ray[1]).hit)
		return true
	if event is InputEventMouseMotion and event.button_mask == 0:
		var ray := _ray(pos)
		update_visual(_pick_start(ray[0], ray[1]))
		return true
	return false


func _commit(seed_cell: Vector3i) -> void:
	if _job or State.edit_busy() or seed_cell == VoxelPicking.NONE or not State.has_cell(seed_cell):
		return
	_source_document = State.document
	_source_frame = State.get_current_voxel_frame()
	_job = WandJob.new()
	_job.source_frame = _source_frame.copy_frame()
	_job.edit_context = State.selection_context()
	_job.seed_cell = seed_cell
	_job.target_material = _source_frame.get_material(seed_cell)
	_job.connected = _settings.connected
	_job.previous_selection = State.selection.capture()
	_job.mode = _settings.mode
	var work := _job.estimate_work(_source_frame.count() + State.selection.count())
	if work <= 4096:
		_job.run()
		_finish_selection()
		return
	_job.batch_queue = VoxelRegionSearch.BatchQueue.new()
	_job.batch_cursor = VoxelRegionSearch.BatchCursor.new(_job.batch_queue)
	_edit = State.begin_edit()
	if _edit == null:
		_job = null
		_source_document = null
		_source_frame = null
		return
	_operation_id = State.begin_operation("Selecting", work, true, self, _cancel_selection)
	if _job.mode == 0:
		State.selection.clear()
	_publish_selection()
	_job.worker_task_id = WorkerThreadPool.add_task(_job.run, true, "Wand selection")
	_service_selection()


func _service_selection() -> void:
	var job := _job
	while job != null and _selection_current(job):
		var done := WorkerThreadPool.is_task_completed(job.worker_task_id)
		_drain_selection_batches(job)
		if done and job.batch_cursor.is_done():
			break
		var progress := job.progress()
		State.update_operation(_operation_id, progress[1], -1, progress[0])
		await State.get_tree().process_frame
	if job == null or not _selection_current(job):
		return
	job.batch_queue.cancel()
	WorkerThreadPool.wait_for_task_completion(job.worker_task_id)
	_finish_selection()


func _drain_selection_batches(job: WandJob) -> void:
	var changed := false
	var started_us := Time.get_ticks_usec()
	var cursor := job.batch_cursor
	var slice_apply := _apply_selection_slice.bind(job)
	while cursor.apply_slice(MERGE_SLICE, slice_apply):
		changed = true
		if not _selection_current(job):
			return
		if Time.get_ticks_usec() - started_us >= PUBLISH_BUDGET_US:
			break
	if changed:
		_publish_selection()


func _apply_selection_slice(keys: Array, start: int, end: int, job: WandJob) -> bool:
	if not _selection_current(job):
		return false
	if job.mode == 2:
		State.selection.erase_range(keys, start, end)
	else:
		State.selection.add_range(keys, start, end)
	return true


func _publish_selection() -> void:
	State.selection_changed.emit()


func _selection_current(job: WandJob) -> bool:
	return _job == job and State.document == _source_document and State.get_current_voxel_frame() == _source_frame


func is_streaming() -> bool:
	return _job != null and _edit != null


func _retire_job(job: WandJob) -> void:
	job.cancel()
	if job.batch_queue != null:
		job.batch_queue.cancel()
	_retired_jobs.append(job)
	_reap_retired_jobs()


func _reap_retired_jobs() -> void:
	if _reaping:
		return
	_reaping = true
	while not _retired_jobs.is_empty():
		var job := _retired_jobs[0]
		if job.worker_task_id != -1:
			while not WorkerThreadPool.is_task_completed(job.worker_task_id):
				await State.get_tree().process_frame
			WorkerThreadPool.wait_for_task_completion(job.worker_task_id)
		_retired_jobs.pop_front()
	_reaping = false


func _finish_selection() -> void:
	var job := _job
	if job == null:
		return
	var streamed := job.batch_cursor != null
	var committed := job.checkpoint(0) and State.document == _source_document and State.get_current_voxel_frame() == _source_frame
	var tx := _edit
	var operation_id := _operation_id
	_operation_id = 0
	_source_document = null
	_source_frame = null
	if not committed:
		_job = null
		_edit = null
		if tx != null:
			State.cancel_edit(tx)
		State.finish_operation(operation_id)
		return
	if tx == null:
		tx = State.begin_edit()
	if tx == null:
		_job = null
		_edit = null
		State.finish_operation(operation_id)
		return
	if not streamed or State.selection.count() != job.result.size():
		State.selection.restore(job.result)
	if streamed:
		_publish_selection()
		_job = null
		_edit = null
		State.finish_edit(tx, "Wand selection")
	else:
		_job = null
		_edit = null
		State.finish_edit(tx, "Wand selection")
		_publish_selection()
	State.finish_operation(operation_id)


func _cancel_selection() -> void:
	var job := _job
	if job == null and _edit == null:
		return
	_job = null
	if job:
		_retire_job(job)
	var tx := _edit
	_edit = null
	_source_document = null
	_source_frame = null
	var operation_id := _operation_id
	_operation_id = 0
	if tx != null:
		State.cancel_edit(tx)
		_publish_selection()
	State.finish_operation(operation_id)

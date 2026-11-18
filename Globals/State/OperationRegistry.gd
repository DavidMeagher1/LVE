extends RefCounted


signal activity_changed()

var tree: SceneTree

class Operation extends RefCounted:
	var id := 0
	var label := ""
	var phase := ""
	var detail := ""
	var completed := 0
	var total := -1
	var foreground := false
	var cancel_requested := false
	var owner_ref: WeakRef
	var _cancel_callback := Callable()

	func can_cancel() -> bool:
		return not cancel_requested and _cancel_callback.is_valid()

var _operations: Dictionary[int, Operation] = {}
var _next_operation_id := 1
var _activity_started_ms := 0


func begin_operation(label: String, total: int = -1, foreground: bool = false, operation_owner: Node = null, cancel_callback: Callable = Callable()) -> int:
	var operation := Operation.new()
	operation.label = label
	operation.total = total
	operation.foreground = foreground
	operation._cancel_callback = cancel_callback
	if operation_owner:
		operation.owner_ref = weakref(operation_owner)
	if _operations.is_empty():
		_activity_started_ms = Time.get_ticks_msec()
	var operation_id := _next_operation_id
	_next_operation_id += 1
	operation.id = operation_id
	_operations[operation_id] = operation
	activity_changed.emit()
	return operation_id


func cancel_operation(operation_id: int) -> bool:
	var operation: Operation = _operations.get(operation_id)
	if operation == null or not operation.can_cancel():
		return false
	operation.cancel_requested = true
	var callback := operation._cancel_callback
	activity_changed.emit()
	if callback.is_valid():
		callback.call()
	return true


func cancel_activity() -> bool:
	var operation := get_activity()
	if operation == null or not operation.foreground:
		return false
	if operation.cancel_requested:
		return true
	return cancel_operation(operation.id)


func update_operation(operation_id: int, completed: int, total: int = -1, phase: String = "", detail: String = "") -> void:
	var operation: Operation = _operations.get(operation_id)
	if operation == null:
		return
	if operation.completed == completed and operation.total == total and operation.detail == detail and operation.phase == phase:
		return
	operation.completed = completed
	operation.total = total
	operation.detail = detail
	operation.phase = phase
	activity_changed.emit()


func finish_operation(operation_id: int) -> void:
	if not _operations.erase(operation_id):
		return
	if _operations.is_empty():
		_activity_started_ms = 0
	activity_changed.emit()


func clear() -> void:
	_operations.clear()
	_activity_started_ms = 0
	activity_changed.emit()


func run_edit_job(job: VoxelFrame.EditJob, operation_id: int, task_name: String, on_frame: Callable = Callable()) -> void:
	job.worker_task_id = WorkerThreadPool.add_task(job.run, true, task_name)
	while job.worker_task_id >= 0 and not WorkerThreadPool.is_task_completed(job.worker_task_id):
		if on_frame.is_valid():
			on_frame.call()
		var progress := job.progress()
		update_operation(operation_id, progress[1], progress[2], progress[0])
		await tree.process_frame
	job.wait_for_worker()


func has_operation(operation_id: int) -> bool:
	return _operations.has(operation_id)


func get_activity() -> Operation:
	var background_operation: Operation = null
	for operation in _operations.values():
		if operation.foreground:
			return operation
		if background_operation == null:
			background_operation = operation
	return background_operation


func activity_elapsed_ms() -> int:
	return Time.get_ticks_msec() - _activity_started_ms if not _operations.is_empty() else 0


func edit_busy(requester: Node = null) -> bool:
	for operation in _operations.values():
		if operation.foreground and (requester == null or operation.owner_ref == null or operation.owner_ref.get_ref() != requester):
			return true
	return false


func update() -> void:
	for operation_id in _operations.keys():
		var operation: Operation = _operations[operation_id]
		if operation.owner_ref and operation.owner_ref.get_ref() == null:
			finish_operation(operation_id)

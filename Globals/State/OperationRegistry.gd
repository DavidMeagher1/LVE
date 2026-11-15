extends RefCounted

## The tracked operations for the status display.
##
## The registry owns the operation list and the activity clock. An owner starts
## an operation with [method begin_operation] and finishes it with
## [method finish_operation]. State forwards these methods and re-emits
## [signal activity_changed].

## Emitted when an operation starts, updates, or finishes.
signal activity_changed()

## The tree that [method run_edit_job] pumps. State sets it in its _ready.
var tree: SceneTree

## One tracked operation for the status display.
##
## The registry owns the list. The owner starts an operation with
## [method begin_operation] and finishes it with [method finish_operation].
class Operation extends RefCounted:
	## The unique operation id.
	var id := 0
	# The artist-facing identity the owner set at begin_operation. It is stable, so
	# the status display never changes its action name while the operation runs.
	## The artist-facing action name. It stays fixed for the whole operation.
	var label := ""
	# The owner's current progress stage. It is diagnostic only: the status display
	# shows the begin label, not this stage.
	## The owner's current progress stage. It is diagnostic only.
	var phase := ""
	## A diagnostic detail line for the current stage.
	var detail := ""
	## The completed work count.
	var completed := 0
	## The total work count. A value below one means an unknown total.
	var total := -1
	## Whether the operation owns Escape and the status display.
	var foreground := false
	# Set when a cancel request was accepted. The owner finishes the operation, so
	# completion stays with finish_operation.
	## Whether a cancel request was accepted. The owner finishes the operation.
	var cancel_requested := false
	## A weak reference to the operation owner.
	var owner_ref: WeakRef
	# An operation is cancellable only when its owner registered this callback. The
	# capability is explicit, so a foreground operation without one stays visible and
	# is not cancellable.
	var _cancel_callback := Callable()

	## Returns [code]true[/code] when a cancel request can still be accepted.
	func can_cancel() -> bool:
		return not cancel_requested and _cancel_callback.is_valid()

var _operations: Dictionary[int, Operation] = {}
var _next_operation_id := 1
var _activity_started_ms := 0


## Starts one tracked operation and returns its id. [param label] is the artist
## action. A [param total] below one means an unknown total. A [param
## cancel_callback] makes the operation cancellable.
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


# Request the cancellation of one operation. The owner runs its own cooperative
# cancel path, so the request marks the operation and calls its callback. A second
# request returns false, and completion stays with finish_operation. Returns true
# when the request was accepted.
## Requests the cancellation of one operation. Returns [code]true[/code] when
## the request was accepted. A second request returns [code]false[/code]. The
## owner finishes the operation.
func cancel_operation(operation_id: int) -> bool:
	var operation: Operation = _operations.get(operation_id)
	if operation == null or not operation.can_cancel():
		return false
	# Mark the request before the callback, so a repeat request is refused even when
	# the callback defers its work.
	operation.cancel_requested = true
	var callback := operation._cancel_callback
	activity_changed.emit()
	if callback.is_valid():
		callback.call()
	return true


# Cancel the cancellable foreground operation the status bar shows. Esc uses this,
# so it still reaches a tool that a tool switch detached from the tree.
## Cancels the cancellable foreground operation that the status bar shows.
## Returns [code]true[/code] when the request was accepted or already pending.
func cancel_activity() -> bool:
	var operation := get_activity()
	if operation == null or not operation.foreground:
		return false
	# A pending cancellation already owns Esc. Report it as handled, so a repeat
	# Escape is swallowed instead of reaching a tool's own cancel.
	if operation.cancel_requested:
		return true
	return cancel_operation(operation.id)


# Update the measured progress and the internal stage of one operation. The stage
# and the detail are diagnostic: the status display shows only the begin label. The
# begin label is never replaced, so a worker stage cannot change the artist action.
## Updates the measured progress of one operation. [param completed] and [param
## total] drive the percentage. [param phase] and [param detail] are diagnostic
## only.
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


## Finishes one operation and removes it from the list. Does nothing when the id
## is unknown.
func finish_operation(operation_id: int) -> void:
	if not _operations.erase(operation_id):
		return
	if _operations.is_empty():
		_activity_started_ms = 0
	activity_changed.emit()


## Removes every operation and resets the activity clock. A document replacement
## calls it.
func clear() -> void:
	_operations.clear()
	_activity_started_ms = 0
	activity_changed.emit()


# Run one edit job on the worker pool while its progress feeds the operation.
# The caller keeps the job, the operation, the result, and its cancel policy.
# `on_frame` runs once per pumped frame before the progress update, so a caller
# can cancel the job when its context changes. The worker is always joined before
# this returns, even when the operation is removed or the caller detaches. A
# caller that waits for the worker itself retires `worker_task_id` through
# `wait_for_worker`, and this stops without a second wait. `wait_for_worker`
# clears the id after its own wait, so a later external wait never waits on a
# disposed task.
## Runs one edit job on the worker pool and pumps its progress. The worker is
## always joined before this returns. [param on_frame] runs once per pumped
## frame before the progress update.
func run_edit_job(job: VoxelFrame.EditJob, operation_id: int, task_name: String, on_frame: Callable = Callable()) -> void:
	job.worker_task_id = WorkerThreadPool.add_task(job.run, true, task_name)
	while job.worker_task_id >= 0 and not WorkerThreadPool.is_task_completed(job.worker_task_id):
		if on_frame.is_valid():
			on_frame.call()
		var progress := job.progress()
		update_operation(operation_id, progress[1], progress[2], progress[0])
		await tree.process_frame
	job.wait_for_worker()


## Returns [code]true[/code] when the operation id is tracked.
func has_operation(operation_id: int) -> bool:
	return _operations.has(operation_id)


## Returns the operation for the status display. A foreground operation wins. A
## background operation is the fallback.
func get_activity() -> Operation:
	var background_operation: Operation = null
	for operation in _operations.values():
		if operation.foreground:
			return operation
		if background_operation == null:
			background_operation = operation
	return background_operation


## Returns the elapsed time of the current activity in milliseconds. Returns
## zero when no operation runs.
func activity_elapsed_ms() -> int:
	return Time.get_ticks_msec() - _activity_started_ms if not _operations.is_empty() else 0


## Returns [code]true[/code] when a foreground operation blocks an edit. An
## operation that [param requester] owns does not block it.
func edit_busy(requester: Node = null) -> bool:
	for operation in _operations.values():
		if operation.foreground and (requester == null or operation.owner_ref == null or operation.owner_ref.get_ref() != requester):
			return true
	return false


## Finishes every operation whose owner was freed. Call it once per frame.
func update() -> void:
	for operation_id in _operations.keys():
		var operation: Operation = _operations[operation_id]
		if operation.owner_ref and operation.owner_ref.get_ref() == null:
			finish_operation(operation_id)

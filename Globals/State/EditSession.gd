extends RefCounted

## The one open edit and the history steps that it records.
##
## The owner holds the handle that [method begin_edit] returns. A stale handle
## does nothing, so a cancel can never close a replacement edit.

const DocumentSession := preload("res://Globals/State/DocumentSession.gd")
const SelectionState := preload("res://Globals/State/SelectionState.gd")
const EditingAids := preload("res://Globals/State/EditingAids.gd")

## Emitted when an owned edit opens or closes. A history change is refused while
## an edit is open, so observers use this signal to refresh the history controls.
signal edit_state_changed()

## The session that owns the active document and the playback state.
var session: DocumentSession
## The cell selection of the active document.
var selection_state: SelectionState
## The floor, the slice, and the symmetry aids.
var aids: EditingAids
## Commits the active document's undo history. State supplies it.
var commit_history := Callable()
## Emits the cell change signal after a restore. State supplies it.
var cells_changed := Callable()
## Restores one chunk snapshot for a history step. State supplies it, so an undo
## action does not hold this session.
var history_restore_chunks := Callable()

# The one open edit, or null. It supplies the frozen edit context to drawing and
# holds the identity a commit or a cancel must match. The owner holds the handle.
var _active_edit: VoxelEditTransaction


# Begin one owned edit on the current frame or one named frame. The transaction
# captures the frame, the selection, and the frozen edit context. Returns null
# when an edit is already active or the frame is missing, so a caller must check
# before it mutates the model. The caller holds the returned handle for the edit.
## Begins one owned edit on the current frame, or on [param frame_index] when it
## is not negative. Returns null while another edit is active or the frame is
## missing. The caller must check the result before it mutates the model.
func begin_edit(frame_index: int = -1) -> VoxelEditTransaction:
	if _active_edit != null:
		return null
	var frame := _current_frame() if frame_index < 0 else _frame(frame_index)
	if frame == null:
		return null
	_active_edit = VoxelEditTransaction.begin(session.document, frame, selection_state.selection, aids.drawing_context(null))
	edit_state_changed.emit()
	return _active_edit


## Returns the open edit, or null when no edit is active.
func active_edit() -> VoxelEditTransaction:
	return _active_edit


## Returns the frozen context of the open edit, or null when no edit is active.
func frozen_context() -> VoxelFrame.EditContext:
	return _active_edit.edit_context if _active_edit != null else null


# Close one owned edit and record its change as one history action. A stale handle
# that no longer owns the active edit does nothing, so a cancelled edit can never
# finish a newer one or roll back a newer document.
## Closes one owned edit and records its change as one history action. A stale
## handle that no longer owns the active edit does nothing. The default action
## is [code]Stroke[/code].
func finish_edit(tx: VoxelEditTransaction, action: String = "Stroke") -> void:
	if tx == null or tx != _active_edit:
		return
	# Clear the active handle before any signal, so a history handler can begin a
	# new edit without this call clearing it again.
	_active_edit = null
	var change := tx.finish()
	if change == null:
		edit_state_changed.emit()
		return
	var history := session.document.edit_history
	history.create_action(action)
	history.add_undo_method(history_restore_chunks.bind(change.frame, change.undo_chunks, change.undo_selection, change.undo_selection_masks))
	history.add_do_method(history_restore_chunks.bind(change.frame, change.redo_chunks, change.redo_selection, change.redo_selection_masks))
	commit_history.call(false)
	edit_state_changed.emit()


## Closes one owned edit and returns its change without a history action. The
## caller commits one or more changes later with [method commit_changes]. Returns
## null when the handle is stale or the edit changed nothing.
func finish_edit_collect(tx: VoxelEditTransaction) -> VoxelEditTransaction.Change:
	if tx == null or tx != _active_edit:
		return null
	_active_edit = null
	var change := tx.finish()
	edit_state_changed.emit()
	return change


## Records one history action from changes that the caller already applied.
## The do methods run in change order and the undo methods run in reverse order,
## so repeated edits to one frame restore the earliest snapshot last.
func commit_changes(changes: Array, action: String = "Write Cells") -> void:
	if changes.is_empty():
		return
	var history := session.document.edit_history
	history.create_action(action)
	for value in changes:
		var change: VoxelEditTransaction.Change = value
		history.add_do_method(history_restore_chunks.bind(change.frame, change.redo_chunks, change.redo_selection, change.redo_selection_masks))
	for index in range(changes.size() - 1, -1, -1):
		var change: VoxelEditTransaction.Change = changes[index]
		history.add_undo_method(history_restore_chunks.bind(change.frame, change.undo_chunks, change.undo_selection, change.undo_selection_masks))
	commit_history.call(false)


## Restores changes that the caller applied but did not commit. It records no
## history action.
func cancel_changes(changes: Array) -> void:
	if changes.is_empty():
		return
	for index in range(changes.size() - 1, -1, -1):
		var change: VoxelEditTransaction.Change = changes[index]
		_restore_chunks(change.frame, change.undo_chunks, change.undo_selection, change.undo_selection_masks)
	edit_state_changed.emit()


# Roll one owned edit back to its start snapshots. A stale handle does nothing.
## Rolls one owned edit back to its start snapshots. A stale handle does
## nothing.
func cancel_edit(tx: VoxelEditTransaction) -> void:
	if tx == null or tx != _active_edit:
		return
	# Clear the active handle before the restore signals, so a selection handler
	# can begin a new edit and this restore cannot roll it back.
	_active_edit = null
	var rollback := tx.cancel()
	if rollback == null:
		edit_state_changed.emit()
		return
	_restore_chunks(rollback.frame, rollback.chunks, rollback.selection, rollback.selection_masks)
	edit_state_changed.emit()


# Close an edit whose document is replaced. The replacement discards the captured
# frame, so the transaction releases its references without a restore.
## Closes an edit whose document is replaced. The transaction releases its
## references without a restore.
func _abandon_active_edit() -> void:
	if _active_edit == null:
		return
	_active_edit.abandon()
	_active_edit = null


func _restore_chunks(edited_frame: VoxelFrame, chunk_snapshot: Dictionary, selection_snapshot: Dictionary, selection_snapshot_masks: Dictionary = {}) -> void:
	var frame_index := session.document.frames.find(edited_frame)
	if frame_index == -1:
		return
	var cells_restored := edited_frame.chunks != chunk_snapshot
	edited_frame.restore(chunk_snapshot)
	session.document._bounds_dirty = true
	selection_state.selection.restore(selection_snapshot, selection_snapshot_masks)
	if cells_restored:
		var affected_cells: Array[Vector3i] = []
		cells_changed.call(frame_index, affected_cells)
	selection_state.notify_changed()


## Restores one chunk snapshot for a history step.
## [member history_restore_chunks] calls it.
func restore_history_chunks(edited_frame: VoxelFrame, chunk_snapshot: Dictionary, selection_snapshot: Dictionary, selection_snapshot_masks: Dictionary = {}) -> void:
	_restore_chunks(edited_frame, chunk_snapshot, selection_snapshot, selection_snapshot_masks)


func _current_frame() -> VoxelFrame:
	return _frame(session.playback.current_frame)


func _frame(index: int) -> VoxelFrame:
	var frames := session.document.frames
	if index < 0 or index >= frames.size():
		return null
	return frames[index]

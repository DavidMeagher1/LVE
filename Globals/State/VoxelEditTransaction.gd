class_name VoxelEditTransaction
extends RefCounted


var document: VoxelDocument
var frame: VoxelFrame
var edit_context: VoxelFrame.EditContext
var _selection: VoxelSelection
var _start_chunks := {}
var _start_selection := {}
var _start_selection_masks := {}
var _closed := false

static var _profile_chunks_equal_calls := 0
static var _profile_chunks_equal_us := 0


class Change extends RefCounted:
	var frame: VoxelFrame
	var undo_chunks: Dictionary
	var undo_selection: Dictionary
	var undo_selection_masks: Dictionary
	var redo_chunks: Dictionary
	var redo_selection: Dictionary
	var redo_selection_masks: Dictionary


class Rollback extends RefCounted:
	var frame: VoxelFrame
	var chunks: Dictionary
	var selection: Dictionary
	var selection_masks: Dictionary


static func begin(edited_document: VoxelDocument, edited_frame: VoxelFrame, edited_selection: VoxelSelection, context: VoxelFrame.EditContext) -> VoxelEditTransaction:
	var transaction := VoxelEditTransaction.new()
	transaction.document = edited_document
	transaction.frame = edited_frame
	transaction.edit_context = context
	transaction._selection = edited_selection
	transaction._start_chunks = edited_frame.capture()
	transaction._start_selection = edited_selection.capture()
	transaction._start_selection_masks = edited_selection.mask_snapshot()
	return transaction


func is_closed() -> bool:
	return _closed


func finish() -> Change:
	if _closed:
		return null
	_closed = true
	var end_chunks := frame.capture()
	var end_selection_masks := _selection.mask_snapshot()
	var changed := not _chunks_equal(_start_chunks, end_chunks) or not _masks_equal(_start_selection_masks, end_selection_masks)
	var change: Change = null
	if changed:
		change = Change.new()
		change.frame = frame
		change.undo_chunks = _start_chunks
		change.undo_selection = _start_selection
		change.undo_selection_masks = _start_selection_masks
		change.redo_chunks = end_chunks
		change.redo_selection = _selection.capture()
		change.redo_selection_masks = end_selection_masks
	_release()
	return change


func cancel() -> Rollback:
	if _closed:
		return null
	_closed = true
	var rollback := Rollback.new()
	rollback.frame = frame
	rollback.chunks = _start_chunks
	rollback.selection = _start_selection
	rollback.selection_masks = _start_selection_masks
	_release()
	return rollback


func abandon() -> void:
	if _closed:
		return
	_closed = true
	_release()


func _release() -> void:
	document = null
	frame = null
	edit_context = null
	_selection = null
	_start_chunks = {}
	_start_selection = {}
	_start_selection_masks = {}


static func _masks_equal(first_masks: Dictionary, second_masks: Dictionary) -> bool:
	if first_masks.size() != second_masks.size():
		return false
	for location in first_masks:
		var second_grids = second_masks.get(location)
		if second_grids == null:
			return false
		var first_grids: Array = first_masks[location]
		if first_grids[0] != second_grids[0] or first_grids[1] != second_grids[1] or first_grids[2] != second_grids[2]:
			return false
	return true


static func _chunks_equal(first_chunks: Dictionary, second_chunks: Dictionary) -> bool:
	var started := Time.get_ticks_usec()
	var result := _compare_chunks(first_chunks, second_chunks)
	_profile_chunks_equal_calls += 1
	_profile_chunks_equal_us += Time.get_ticks_usec() - started
	return result


static func _compare_chunks(first_chunks: Dictionary, second_chunks: Dictionary) -> bool:
	if first_chunks.size() != second_chunks.size():
		return false
	for chunk_location in first_chunks:
		if not second_chunks.has(chunk_location):
			return false
		var first_chunk: VoxelFrame.Chunk = first_chunks[chunk_location]
		var second_chunk: VoxelFrame.Chunk = second_chunks[chunk_location]
		if first_chunk != second_chunk and not first_chunk.equals(second_chunk):
			return false
	return true

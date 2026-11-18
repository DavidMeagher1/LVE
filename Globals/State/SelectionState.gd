extends RefCounted


const DocumentSession := preload("res://Globals/State/DocumentSession.gd")

signal selection_changed()

var session: DocumentSession

var selection: VoxelSelection:
	get:
		return session.document.edit_selection


func clear_selection() -> void:
	if selection.is_empty():
		return
	selection.clear()
	selection_changed.emit()


func selection_context(drawing: VoxelFrame.EditContext) -> VoxelFrame.EditContext:
	var context := drawing.duplicate()
	context.selection = {}
	context.bounded_axes = 0
	return context


func selection_region(region: VoxelSelection, context: VoxelFrame.EditContext, frame: VoxelFrame) -> VoxelSelection:
	var result := VoxelSelection.new()
	result.restore(context.expand(region.capture(), frame, false, null))
	return result


func notify_changed() -> void:
	selection_changed.emit()

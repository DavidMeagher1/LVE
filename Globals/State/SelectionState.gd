extends RefCounted

## The cell selection of the active document.
##
## The selection lives on the document, so the model reads it through the
## session. State forwards the selection and re-emits the change signal.

const DocumentSession := preload("res://Globals/State/DocumentSession.gd")

## The cell selection of the active document.
signal selection_changed()

## The session that owns the active document.
var session: DocumentSession

## The cell selection of the active document.
var selection: VoxelSelection:
	get:
		return session.document.edit_selection


## Clears the cell selection.
func clear_selection() -> void:
	if selection.is_empty():
		return
	selection.clear()
	selection_changed.emit()


## Returns an edit context that carries the symmetry and the slice, but not the
## selection filter. [param drawing] supplies the symmetry, the slice, and the
## document size.
func selection_context(drawing: VoxelFrame.EditContext) -> VoxelFrame.EditContext:
	var context := drawing.duplicate()
	context.selection = {}
	# Selection and transform are not limited by the document size.
	context.bounded_axes = 0
	return context


## Returns the region after the symmetry expansion. [param context] supplies the
## symmetry and the slice. The selection filter is not applied.
func selection_region(region: VoxelSelection, context: VoxelFrame.EditContext, frame: VoxelFrame) -> VoxelSelection:
	var result := VoxelSelection.new()
	result.restore(context.expand(region.capture(), frame, false, null))
	return result


## Emits [signal selection_changed] after a caller mutates the selection.
func notify_changed() -> void:
	selection_changed.emit()

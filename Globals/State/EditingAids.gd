extends RefCounted

## The floor plane, the slice, and the symmetry editing aids.
##
## The aids build the edit context that drawing uses. The context freezes the
## symmetry, the slice, the selection, and the document size for one stroke.

const DocumentSession := preload("res://Globals/State/DocumentSession.gd")
const SelectionState := preload("res://Globals/State/SelectionState.gd")

## Emitted when the floor axis or the floor index changes.
signal floor_plane_changed()
## Emitted when the slice option changes.
signal slice_changed()
## Emitted when the symmetry axes or the symmetry origin change.
signal symmetry_changed()

## The largest slice layer count on each side.
const MAX_SLICE_LAYERS := 8
## The default symmetry origin, at the corner between eight cells.
const DEFAULT_SYMMETRY_ORIGIN := Vector3(-0.5, -0.5, -0.5)

## The session that owns the active document.
var session: DocumentSession
## The cell selection of the active document.
var selection_state: SelectionState

## The world axis of the floor plane. Axis 0 is X, axis 1 is Y, and axis 2 is Z.
var floor_axis: Vector3.Axis = Vector3.Axis.AXIS_Y:
	set(value):
		if value == floor_axis:
			return
		floor_axis = value
		floor_plane_changed.emit()

## The cell index of the floor plane along [member floor_axis].
var floor_index := 0:
	set(value):
		if value == floor_index:
			return
		floor_index = value
		floor_plane_changed.emit()

## Whether the slice limits every edit. It is a view of [member slice_layers],
## so 0 layers means every layer is writable.
var slice_enabled: bool:
	get:
		return slice_layers > 0
	set(value):
		slice_layers = 1 if value else 0

## The number of writable and visible layers on each side of the floor plane. 0
## shows every layer. 1 keeps one layer on each side of the plane.
var slice_layers := 0:
	set(value):
		value = clampi(value, 0, MAX_SLICE_LAYERS)
		if value == slice_layers:
			return
		slice_layers = value
		slice_changed.emit()

## The symmetry axes as a bit mask. Bit 0 is X, bit 1 is Y, and bit 2 is Z.
var symmetry_axes := 0:
	set(value):
		value &= 7
		if value == symmetry_axes:
			return
		symmetry_axes = value
		symmetry_changed.emit()

## The symmetry origin in cell units. It snaps to half units.
var symmetry_origin := DEFAULT_SYMMETRY_ORIGIN:
	set(value):
		value = value.snapped(Vector3.ONE * 0.5)
		if value == symmetry_origin:
			return
		symmetry_origin = value
		symmetry_changed.emit()


## Returns the first layer of the slice.
func slice_first() -> int:
	return floor_index - slice_layers


## Returns the last layer of the slice.
func slice_last() -> int:
	return floor_index + slice_layers - 1 if slice_layers > 0 else floor_index


## Returns the number of layers in the slice. The floor plane splits the slab
## evenly, so the floor layer is the first layer above it.
func slice_count() -> int:
	return slice_layers * 2 if slice_layers > 0 else 1


## Returns the world level of the slice plane.
func slice_level() -> float:
	return float(floor_index) - 0.5


## Returns the transform that mirrors a point for one symmetry mask.
func symmetry_transform(mask: int, origin: Vector3) -> Transform3D:
	var reflection := Vector3.ONE
	for axis in 3:
		if mask & (1 << axis):
			reflection[axis] = -1.0
	return Transform3D(Basis.from_scale(reflection), origin - origin * reflection)


## Returns the edit context for the current drawing. [param frozen] is the
## context of the open edit, or null to build a live context.
func drawing_context(frozen: VoxelFrame.EditContext = null) -> VoxelFrame.EditContext:
	# A stroke keeps the context it captured at begin, so a symmetry or selection
	# change during the stroke cannot alter the cells it writes.
	if frozen != null:
		return frozen
	return _live_context()


## Returns a live edit context. It reads the symmetry, the slice, the selection,
## and the document size that exist now.
func _live_context() -> VoxelFrame.EditContext:
	var context := VoxelFrame.EditContext.new()
	context.axes = symmetry_axes
	context.origin_twice = Vector3i(symmetry_origin * 2.0)
	context.selection = selection_state.selection.capture()
	context.selection.make_read_only()
	if slice_enabled:
		context.slice_axis = floor_axis
		context.slice_index = slice_first()
		context.slice_count = slice_count()
	var document := session.document
	if document.has_size():
		for axis in 3:
			if document.size[axis] <= 0:
				continue
			var cell_range := document.axis_cell_range(axis)
			context.bounded_axes |= 1 << axis
			context.bounds_min[axis] = cell_range.x
			context.bounds_max[axis] = cell_range.y
	return context

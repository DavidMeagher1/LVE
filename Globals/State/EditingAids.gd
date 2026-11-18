extends RefCounted


const DocumentSession := preload("res://Globals/State/DocumentSession.gd")
const SelectionState := preload("res://Globals/State/SelectionState.gd")

signal floor_plane_changed()
signal slice_changed()
signal symmetry_changed()

const MAX_SLICE_LAYERS := 8
const DEFAULT_SYMMETRY_ORIGIN := Vector3(-0.5, -0.5, -0.5)

var session: DocumentSession
var selection_state: SelectionState

var floor_axis: Vector3.Axis = Vector3.Axis.AXIS_Y:
	set(value):
		if value == floor_axis:
			return
		floor_axis = value
		floor_plane_changed.emit()

var floor_index := 0:
	set(value):
		if value == floor_index:
			return
		floor_index = value
		floor_plane_changed.emit()

var slice_enabled: bool:
	get:
		return slice_layers > 0
	set(value):
		slice_layers = 1 if value else 0

var slice_layers := 0:
	set(value):
		value = clampi(value, 0, MAX_SLICE_LAYERS)
		if value == slice_layers:
			return
		slice_layers = value
		slice_changed.emit()

var symmetry_axes := 0:
	set(value):
		value &= 7
		if value == symmetry_axes:
			return
		symmetry_axes = value
		symmetry_changed.emit()

var symmetry_origin := DEFAULT_SYMMETRY_ORIGIN:
	set(value):
		value = value.snapped(Vector3.ONE * 0.5)
		if value == symmetry_origin:
			return
		symmetry_origin = value
		symmetry_changed.emit()


func slice_first() -> int:
	return floor_index - slice_layers


func slice_last() -> int:
	return floor_index + slice_layers - 1 if slice_layers > 0 else floor_index


func slice_count() -> int:
	return slice_layers * 2 if slice_layers > 0 else 1


func slice_level() -> float:
	return float(floor_index) - 0.5


func symmetry_transform(mask: int, origin: Vector3) -> Transform3D:
	var reflection := Vector3.ONE
	for axis in 3:
		if mask & (1 << axis):
			reflection[axis] = -1.0
	return Transform3D(Basis.from_scale(reflection), origin - origin * reflection)


func drawing_context(frozen: VoxelFrame.EditContext = null) -> VoxelFrame.EditContext:
	if frozen != null:
		return frozen
	return _live_context()


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

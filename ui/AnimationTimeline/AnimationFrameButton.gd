extends Button

## The drag handle of one animation frame cell.
##
## A drag carries the source frame index. A drop moves that frame to the
## dropped cell.

## The drag data type that marks one frame drag.
const DRAG_TYPE := "voxel_frame"

## The frame cell that owns this button. The parent sets it.
var frame: AnimationFrame


func _get_drag_data(_at_position: Vector2) -> Variant:
	if frame == null:
		return null
	var data := {"type": DRAG_TYPE, "from": frame.frame_index}
	if get_viewport() and get_viewport().gui_is_dragging():
		var preview := Label.new()
		preview.text = "Frame %d" % (frame.frame_index + 1)
		set_drag_preview(preview)
	return data


func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.get("type", "") == DRAG_TYPE


func _drop_data(_at_position: Vector2, data) -> void:
	if frame == null:
		return
	if data is Dictionary and data.get("type", "") == DRAG_TYPE:
		State.move_frame(data["from"], frame.frame_index)

extends "res://plugins/brush/StrokeTool.gd"


func _init() -> void:
	_settings = preload("./StampSettings.tres")


func handle_input(event: InputEvent, pos: Vector2) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and _settings.pattern().is_empty():
		return false
	return super.handle_input(event, pos)


func open_stroke() -> VoxelEditTransaction:
	var tx := super.open_stroke()
	if tx != null and _edit_context != null:
		_edit_context = _edit_context.duplicate()
		_edit_context.selection = {}
	return tx


func close_stroke(_action: String = "Stamp") -> void:
	var tx := _edit
	if tx == null:
		return
	_edit = null
	State.finish_edit(tx, "Stamp")

extends ToolMenuButton


const GRAB_ID := 0
const POSE_ID := 1

var _settings := preload("./DeformSettings.tres")


func _ready() -> void:
	get_popup().index_pressed.connect(_on_index_pressed)
	_settings.tool_changed.connect(_sync_icon)
	_sync_icon(_settings.tool)


func _on_index_pressed(index: int) -> void:
	_select_id(get_popup().get_item_id(index))


func _select_id(id: int) -> void:
	var item_index := get_popup().get_item_index(id)
	if item_index < 0:
		return
	_settings.tool = _tool_for_id(id)
	_sync_icon(_settings.tool)
	button_pressed = true


func _sync_icon(tool: int) -> void:
	var id := POSE_ID if tool == _settings.Tools.POSE else GRAB_ID
	var item_index := get_popup().get_item_index(id)
	if item_index >= 0:
		icon = get_popup().get_item_icon(item_index)


func _tool_for_id(id: int) -> int:
	match id:
		POSE_ID:
			return _settings.Tools.POSE
	return _settings.Tools.GRAB

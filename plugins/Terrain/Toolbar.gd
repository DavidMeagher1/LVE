extends ToolMenuButton


const BUILD_ID := 0
const FLATTEN_ID := 1
const SMOOTH_ID := 2

var _settings := preload("./TerrainSettings.tres")


func _ready() -> void:
	get_popup().index_pressed.connect(_on_index_pressed)
	_settings.tool_changed.connect(_sync_icon)
	_sync_icon(_settings.tool)


func _on_index_pressed(index: int) -> void:
	_select_id(get_popup().get_item_id(index))


func _sync_icon(tool: int) -> void:
	var item_index := get_popup().get_item_index(tool)
	if item_index >= 0:
		icon = get_popup().get_item_icon(item_index)


func _select_id(id: int) -> void:
	var item_index := get_popup().get_item_index(id)
	if item_index < 0:
		return
	_settings.tool = _tool_for_id(id)
	icon = get_popup().get_item_icon(item_index)
	button_pressed = true


func _tool_for_id(id: int) -> int:
	match id:
		FLATTEN_ID:
			return _settings.Tools.FLATTEN
		SMOOTH_ID:
			return _settings.Tools.SMOOTH
	return _settings.Tools.BUILD

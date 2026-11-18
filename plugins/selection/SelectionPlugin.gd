extends VoxelPlugin


const TOOL_ID := "selection"

var _settings := preload("./SelectionSettings.tres")

@onready var _toolbar:MenuButton = preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _selection := preload("./SelectionPreview.tscn").instantiate()

@onready var _box := preload("./tools/BoxSelectTool.tscn").instantiate()
@onready var _wand := preload("./tools/WandSelectTool.tscn").instantiate()
@onready var _lasso := preload("./tools/LassoSelectTool.tscn").instantiate()

var _current_tool:Node = null
var _active := false

func _ready() -> void:
	name = "SelectionPlugin"
	State.selection_changed.connect(_on_selection_changed)
	_settings.tool_changed.connect(_on_tool_changed)
	add_tool_bar_item(_toolbar, _settings, TOOL_ID)
	add_editor_node(_selection)

	_on_selection_changed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _selection, _box, _wand, _lasso]:
			if is_instance_valid(node):
				node.free()


func _on_selection_changed() -> void:
	var progressive: bool = _wand != null and is_instance_valid(_wand) and _wand.is_streaming()
	_selection.show_selection(State.selection, progressive)


func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	_active = true
	add_option_bar_item(_options)
	_on_tool_changed(_settings.tool)


func _end_deactivation() -> void:
	_active = false
	remove_option_bar_item(_options)
	if _current_tool:
		_current_tool.finish_on_switch()
		remove_editor_node(_current_tool)


func _on_tool_changed(tool: int):
	if not _active:
		return
	if _current_tool:
		_current_tool.finish_on_switch()
		remove_editor_node(_current_tool)
		_current_tool = null
	match tool:
		_settings.Tools.BOX:
			_current_tool = _box
		_settings.Tools.WAND:
			_current_tool = _wand
		_settings.Tools.LASSO:
			_current_tool = _lasso
	add_editor_node(_current_tool)

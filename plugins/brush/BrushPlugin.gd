extends VoxelPlugin


const TOOL_ID := "brush"

@onready var _toolbar := preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _brush_tool := preload("./BrushTool.tscn").instantiate()
@onready var _line_tool := preload("./LineTool.tscn").instantiate()
var _tool: Node3D
var _settings := preload("./BrushSettings.tres")
var _active_mode := 0


func _ready() -> void:
	name = "BrushPlugin"
	_tool = _brush_tool
	_active_mode = _settings.mode
	_settings.changed.connect(_on_settings_changed)
	add_tool_bar_item(_toolbar, _settings, TOOL_ID)
	add_option_bar_item(_options)
	activate_tool()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _brush_tool, _line_tool]:
			if is_instance_valid(node):
				node.free()


func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	add_editor_node(_tool)
	add_option_bar_item(_options)

func _end_deactivation() -> void:
	_tool.finish_on_switch()
	remove_editor_node(_tool)
	remove_option_bar_item(_options)


func _on_settings_changed() -> void:
	var mode_changed := _settings.mode != _active_mode
	_active_mode = _settings.mode
	var next_tool: Node3D = _line_tool if _settings.mode == _settings.BrushMode.LINE else _brush_tool
	if next_tool == _tool:
		if mode_changed:
			_tool.finish_on_switch()
		return
	_tool.finish_on_switch()
	remove_editor_node(_tool)
	_tool = next_tool
	if _toolbar.button_pressed:
		add_editor_node(_tool)

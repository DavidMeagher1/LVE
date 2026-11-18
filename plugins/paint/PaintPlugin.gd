extends VoxelPlugin


const TOOL_ID := "paint"

var _settings := preload("./PaintSettings.tres")

@onready var _toolbar: MenuButton = preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _paintbrush_tool := preload("./PaintBrushTool.tscn").instantiate()
@onready var _fill_tool := preload("./FillTool.tscn").instantiate()
@onready var _spray_tool := preload("./SprayTool.tscn").instantiate()
@onready var _dither_tool := preload("./DitherTool.tscn").instantiate()

var _tool: Node3D
var _active := false


func _ready() -> void:
	name = "PaintPlugin"
	_settings.tool_changed.connect(_on_tool_changed)
	add_tool_bar_item(_toolbar, _settings, TOOL_ID)
	_set_tool(_settings.tool)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _paintbrush_tool, _fill_tool, _spray_tool, _dither_tool]:
			if is_instance_valid(node):
				node.free()


func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	_active = true
	add_editor_node(_tool)
	add_option_bar_item(_options)


func _end_deactivation() -> void:
	_active = false
	_tool.finish_on_switch()
	remove_editor_node(_tool)
	remove_option_bar_item(_options)


func _on_tool_changed(tool: int) -> void:
	if _tool:
		_tool.finish_on_switch()
		remove_editor_node(_tool)
	_set_tool(tool)
	if _active:
		add_editor_node(_tool)


func _set_tool(tool: int) -> void:
	match tool:
		_settings.Tools.FILL:
			_tool = _fill_tool
		_settings.Tools.SPRAY:
			_tool = _spray_tool
		_settings.Tools.DITHER:
			_tool = _dither_tool
		_:
			_tool = _paintbrush_tool

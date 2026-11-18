extends VoxelPlugin


const TOOL_ID := "deform"

var _settings := preload("./DeformSettings.tres")

@onready var _toolbar: MenuButton = preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _grab := preload("./GrabTool.tscn").instantiate()
@onready var _pose := preload("./PoseTool.tscn").instantiate()

var _current_tool: Node = null
var _active := false


func _ready() -> void:
	name = "DeformPlugin"
	_settings.tool_changed.connect(_on_tool_changed)
	_options.bind(_settings)
	add_tool_bar_item(_toolbar, _settings, TOOL_ID)
	_select_tool(_settings.tool)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _grab, _pose]:
			if is_instance_valid(node):
				node.free()


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


func _on_tool_changed(tool: int) -> void:
	_select_tool(tool)
	if _active:
		add_editor_node(_current_tool)


func _select_tool(tool: int) -> void:
	if _current_tool:
		_current_tool.finish_on_switch()
		remove_editor_node(_current_tool)
	match tool:
		_settings.Tools.POSE:
			_current_tool = _pose
		_:
			_current_tool = _grab

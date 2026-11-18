extends VoxelPlugin


const TOOL_ID := "eyedropper"

@onready var _toolbar := preload("./Toolbar.tscn").instantiate()
@onready var _tool := preload("./EyedropperTool.tscn").instantiate()

func _ready() -> void:
	name = "EyedropperPlugin"
	add_tool_bar_item(_toolbar, null, TOOL_ID)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _tool]:
			if is_instance_valid(node):
				node.free()


func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	add_editor_node(_tool)


func _end_deactivation() -> void:
	_tool.cancel_stroke()
	remove_editor_node(_tool)

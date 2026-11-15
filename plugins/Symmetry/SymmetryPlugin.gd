extends VoxelPlugin

## The symmetry plugin.
##
## It adds the symmetry tool and its option bar. The symmetry tool toggles the
## mirror axes and moves the symmetry origin.

## The stable id of the symmetry toolbar. The persisted active tool uses it.
const TOOL_ID := "symmetry"

@onready var _toolbar := preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _tool := preload("./SymmetryTool.tscn").instantiate()


func _ready() -> void:
	name = "SymmetryPlugin"
	add_tool_bar_item(_toolbar, null, TOOL_ID)
	add_editor_node(_tool)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _tool]:
			if is_instance_valid(node):
				node.free()


## Activates the symmetry tool and shows its option bar.
func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	_tool.active = true
	add_option_bar_item(_options)


## Deactivates the symmetry tool and hides its option bar.
func _end_deactivation() -> void:
	_tool.active = false
	remove_option_bar_item(_options)



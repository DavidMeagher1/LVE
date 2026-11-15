extends VoxelPlugin

## The plane plugin.
##
## It adds the plane tool and its axis option bar. The plane tool moves the
## floor plane.

@onready var _toolbar := preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _tool := preload("./PlaneTool.tscn").instantiate()

func _ready() -> void:
	name = "PlanePlugin"
	add_tool_bar_item(_toolbar)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _tool]:
			if is_instance_valid(node):
				node.free()


## Activates the plane tool and shows its option bar.
func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	add_editor_node(_tool)
	add_option_bar_item(_options)


## Deactivates the plane tool and hides its option bar.
func _end_deactivation() -> void:
	remove_editor_node(_tool)
	remove_option_bar_item(_options)



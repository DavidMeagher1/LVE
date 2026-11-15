extends VoxelPlugin

## The terrain plugin.
##
## It owns the terrain tool and adds its toolbar and option bar. A tool switch
## ends an open stroke like a release, so the queued work commits as one history
## action.

## The stable id of the terrain toolbar. The persisted active tool uses it.
const TOOL_ID := "terrain"

var _settings := preload("./settings.tres")

@onready var _toolbar := preload("./Toolbar.tscn").instantiate()
@onready var _options := preload("./Options.tscn").instantiate()
@onready var _terrain_tool := preload("./TerrainTool.tscn").instantiate()

var _tool: Node3D
var _active := false


func _ready() -> void:
	name = "TerrainPlugin"
	_tool = _terrain_tool
	_options.bind(_settings)
	add_tool_bar_item(_toolbar, _settings, TOOL_ID)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for node in [_toolbar, _options, _terrain_tool]:
			if is_instance_valid(node):
				node.free()


## Activates the terrain tool and shows its option bar.
func activate_tool() -> void:
	if not _toolbar.button_pressed:
		_toolbar.button_pressed = true
		return
	_active = true
	add_editor_node(_tool)
	add_option_bar_item(_options)


## Deactivates the terrain tool and hides its option bar. It ends an open stroke
## like a release.
func _end_deactivation() -> void:
	_active = false
	# A switch ends the stroke like a release. Escape and a context change keep
	# their rollback.
	_tool.finish_on_switch()
	remove_editor_node(_tool)
	remove_option_bar_item(_options)


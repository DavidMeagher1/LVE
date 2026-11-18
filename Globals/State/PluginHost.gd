class_name PluginHost
extends Node


const PLUGIN_PATHS := [
	"res://plugins/brush/BrushPlugin.gd",
	"res://plugins/Primitive/PrimitivePlugin.gd",
	"res://plugins/Stamp/StampPlugin.gd",
	"res://plugins/Eyedropper/EyedropperPlugin.gd",
	"res://plugins/paint/PaintPlugin.gd",
	"res://plugins/Terrain/TerrainPlugin.gd",
	"res://plugins/Deform/DeformPlugin.gd",
	"res://plugins/selection/SelectionPlugin.gd",
	"res://plugins/Transform/TransformPlugin.gd",
	"res://plugins/Symmetry/SymmetryPlugin.gd",
	"res://plugins/Plane/PlanePlugin.gd",
	"res://plugins/Export/ExportPlugin.gd",
	"res://plugins/Clipboard/ClipboardPlugin.gd",
	"res://plugins/ImageImport/ImageImportPlugin.gd",
]

var context: EditorContext


func add_plugin(plugin: VoxelPlugin) -> void:
	if plugin == null:
		return
	plugin.context = context
	get_node("/root").add_child.call_deferred(plugin, true)


func remove_plugin(plugin: VoxelPlugin) -> void:
	if plugin == null:
		return
	var root := get_node("/root")
	if plugin.get_parent() == root:
		root.remove_child(plugin)
	plugin.queue_free()


func clear_plugins() -> void:
	var root := get_node("/root")
	for child in root.get_children():
		if child is VoxelPlugin:
			remove_plugin(child)


func reset_plugins() -> void:
	clear_plugins()
	for path in PLUGIN_PATHS:
		add_plugin(load(path).new())

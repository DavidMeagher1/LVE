class_name TerrainToolSettings
extends Resource


signal tool_changed(tool: Tools)

enum Tools {
	BUILD,
	FLATTEN,
	SMOOTH
}

enum BuildMode {
	ADD,
	REMOVE
}

@export var tool: Tools = Tools.BUILD:
	set(value):
		if value == tool:
			return
		tool = value
		tool_changed.emit(tool)
		emit_changed()

@export_range(1, 32, 1) var radius := 4:
	set(value):
		value = clampi(value, 1, 32)
		if value == radius:
			return
		radius = value
		emit_changed()

@export_range(1, 16, 1) var strength := 1:
	set(value):
		value = clampi(value, 1, 16)
		if value == strength:
			return
		strength = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var falloff := 0.5:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value == falloff:
			return
		falloff = value
		emit_changed()

@export var build_mode: BuildMode = BuildMode.ADD:
	set(value):
		if value == build_mode:
			return
		build_mode = value
		emit_changed()

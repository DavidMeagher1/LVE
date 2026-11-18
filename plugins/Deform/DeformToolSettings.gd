class_name DeformToolSettings
extends Resource


signal tool_changed(tool: Tools)

enum Tools {
	GRAB,
	POSE
}

@export var tool: Tools = Tools.POSE:
	set(value):
		if value == tool:
			return
		tool = value
		tool_changed.emit(tool)
		emit_changed()

@export_range(1, 32, 1) var size := 4:
	set(value):
		value = clampi(value, 1, 32)
		if value == size:
			return
		size = value
		emit_changed()

@export var snap := false:
	set(value):
		if value == snap:
			return
		snap = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var falloff := 0.5:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value == falloff:
			return
		falloff = value
		emit_changed()

@export var connected := false:
	set(value):
		if value == connected:
			return
		connected = value
		emit_changed()

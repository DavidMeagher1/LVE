class_name PrimitiveToolSettings
extends Resource


signal tool_changed(tool: Tools)
signal commit_requested()
signal cancel_requested()

enum Tools {
	BOX,
	ELLIPSOID,
	CYLINDER
}

enum Op {
	ADD,
	SUBTRACT,
	INTERSECT
}

@export var tool: Tools = Tools.BOX:
	set(value):
		if value == tool:
			return
		tool = value
		tool_changed.emit(tool)
		emit_changed()

@export var op: Op = Op.ADD:
	set(value):
		if value == op:
			return
		op = value
		emit_changed()

@export_range(0.0, 1.0, 0.05) var smooth := 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(value, smooth):
			return
		smooth = value
		emit_changed()

@export_range(0, 16, 1) var shell := 0:
	set(value):
		value = clampi(value, 0, 16)
		if value == shell:
			return
		shell = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var second_radius := 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(value, second_radius):
			return
		second_radius = value
		emit_changed()

@export_range(0.0, 1.0, 0.05) var roundness := 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if is_equal_approx(value, roundness):
			return
		roundness = value
		emit_changed()

var editing := false:
	set(value):
		if value == editing:
			return
		editing = value
		emit_changed()

func commit() -> void:
	commit_requested.emit()

func cancel() -> void:
	cancel_requested.emit()

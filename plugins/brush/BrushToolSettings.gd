class_name BrushToolSettings
extends "res://plugins/brush/StampToolSettings.gd"


enum BrushMode {
	PENCIL,
	LINE,
	ERASER
}


const PatternJob := preload("./StampPatternJob.gd")

@export var mode:BrushMode = BrushMode.PENCIL :
	set(value):
		if value == mode:
			return
		mode = value
		emit_changed()


func _build_pattern(brush_diameter: int, brush_shape: int) -> Dictionary:
	return PatternJob.build_pattern(brush_diameter, brush_shape)


func create_pattern_job():
	return PatternJob.new()


static func build_pattern(brush_diameter: int, brush_shape: int, job = null) -> Dictionary:
	return PatternJob.build_pattern(brush_diameter, brush_shape, job)
